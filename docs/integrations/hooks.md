# Hooks

Hooks are external contracts bound to a market at deployment. An enabled
callback can inspect intermediate market state, reject an action, and, in a few
specific cases, constrain values before the market applies them.

The market uses ordinary external calls, not `delegatecall`. A hook cannot write
market storage or bypass market authorization. If it reverts, the entire market
action reverts.

Core interfaces:

- [`IHooks`](../../src/access/IHooks.sol): creation and ordinary callbacks
- [`HooksConfig`](../../src/types/HooksConfig.sol): hook address and enabled
  callback flags
- [`IHooksFactory`](../../src/IHooksFactory.sol): template, instance, and market
  provenance

## Template, instance, and market

The hook lifecycle has three layers:

1. A **template** is approved initcode stored by `HooksFactory`, plus its name
   and fee configuration. The code starts with a non-executable byte. The
   factory skips that byte when it copies the initcode for deployment.
2. A **hooks instance** is a contract deployed from one template. It holds its
   own configuration and can serve several markets.
3. A **market binding** is the instance address and callback flags stored in the
   market's immutable `HooksConfig`.

A caller deploying an instance or market must resolve to a registered borrower
principal. The factory indexes instances under that principal.

During market creation, the factory:

1. resolves the caller's principal;
2. computes the future market address;
3. calls `onCreateMarket` before code exists at that address;
4. receives the final `HooksConfig`; and
5. deploys and registers the market.

The administered templates require the resolved principal to match their
administrator. `onCreateMarket` validates deployment parameters and initializes
market-specific hook state.

Disabling a template blocks new instances. It does not disable existing
instances or markets, and an existing instance can still be attached to a new
market. Template disabling is not a kill switch.

## Callback flags

Each template returns optional and required flags from `config()`:

- Required flags are always enabled.
- Optional flags are enabled when requested or required by the instance's
  market configuration.
- `onCreateMarket` returns the final flags stored by the market.

The hook address and enabled flags are immutable after market deployment. The
hook's own state and administration can still change if its implementation
allows it. Reusing an instance means sharing its state and authority domain
across markets.

## Callback surface

### Lender and token actions

- `deposit` and `depositUpTo` call `onDeposit` with the lender and scaled mint
  amount.
- `queueWithdrawal`, `queueWithdrawalScaled`, and `queueFullWithdrawal` call
  `onQueueWithdrawal` with the lender, batch expiry, and scaled amount.
- `executeWithdrawal` and `executeWithdrawals` call `onExecuteWithdrawal` with
  the lender, exact batch expiry, and normalized amount. The batched function
  calls the hook once per withdrawal.
- `transfer` and `transferFrom` call `onTransfer` with the caller, sender,
  recipient, and scaled amount.

### Credit and lifecycle actions

- `borrow` calls `onBorrow` with the normalized amount.
- `repay` and `repayAndProcessUnpaidWithdrawalBatches` call `onRepay` when the
  repayment amount is nonzero.
- `closeMarket` calls `onCloseMarket`. If closure needs a final repayment, it
  calls `onRepay` first.
- `nukeFromOrbit` calls `onNukeFromOrbit`, then queues the sanctioned lender's
  balance through `onQueueWithdrawal`. Term and withdrawal-window policy can
  therefore delay quarantine.

### Parameter changes

- `setMaxTotalSupply` calls `onSetMaxTotalSupply` before applying the cap.
- `setAnnualInterestAndReserveRatioBips` calls
  `onSetAnnualInterestAndReserveRatioBips`. The hook returns the APR and reserve
  ratio the market will validate and apply.
- `setProtocolFeeBips` calls `onSetProtocolFeeBips` before the factory-supplied
  fee takes effect.
- `executePendingAnnualInterestBipsReduction` uses a separate flag and calls
  the periodic hook directly. The hook returns the pending APR. The market only
  applies it if it is below the current APR.

The pending-reduction path comes from
[`IPeriodicTermAprReductionHooks`](../../src/market/WildcatMarketConfig.sol).
It is not an `IHooks.on*` callback.

## Built-in parameter constraints

`OpenTermHooks`, `FixedTermHooks`, and `PeriodicTermHooks` share these creation
bounds:

```text
annualInterestBips          0 .. 10_000
delinquencyFeeBips          0 .. 10_000
withdrawalBatchDuration     0 .. 365 days
reserveRatioBips            0 .. 10_000
delinquencyGracePeriod      0 .. 90 days
```

For ordinary APR updates, built-in hooks ignore the borrower-supplied reserve
ratio. They keep the current ratio unless the APR reduction policy below
replaces it.

The first APR reduction starts a two-week update period anchored to the
original APR and reserve ratio.

- A relative reduction of 25% or less keeps the original reserve ratio.
- A larger reduction uses:

```text
max(original reserve ratio, min(100%, 2 * relative APR reduction))
```

- Another reduction starts a fresh two-week period.
- A partial recovery below the original APR keeps the current expiry.
- Returning to or above the original APR cancels the period and restores the
  original reserve ratio.
- At or after expiry, a non-decreasing update expires the period and restores
  the original ratio. Another reduction starts a new period from the stored
  original values.

Fixed-term hooks reject reductions before maturity, then use this policy.
Periodic-term hooks use their proposal path for reductions and preserve the
current reserve ratio. Unchanged APRs and increases still use the shared path.

## Intermediate-state ordering

The market usually accrues interest and fees and processes expired withdrawal
state before it calls a hook. The `MarketState` passed to the hook is a snapshot
from before the primary action's own accounting changes.

Important boundaries:

- `onQueueWithdrawal` sees a new `pendingWithdrawalExpiry`, but not the new
  amount in the account, batch, or market totals.
- `onExecuteWithdrawal` receives the exact batch expiry being claimed. It must
  not infer that value from `state.pendingWithdrawalExpiry`, which describes the
  current pending batch.
- Repayment assets arrive before `onRepay`. Repayment accounting happens after
  the hook.
- `onSetAnnualInterestAndReserveRatioBips` can replace its two proposed values.
  Ordinary callbacks can reject an action but cannot replace arguments.
- The periodic APR-reduction path returns one APR. The market keeps its current
  reserve ratio.

Callbacks are not a complete accounting feed. Partial withdrawal-batch payments
have no callback. A hook that needs exact pending or unpaid withdrawal state
must read the market and apply its accounting rules.

## `extraData`

Most hooked entrypoints accept an implicit raw calldata suffix. The suffix is
not part of the Solidity signature. Callers append bytes directly after the
canonical ABI calldata, with no extra offset, length, or padding word. The
market passes those bytes to the callback as `bytes extraData`.

Each hook decides how to decode it. Access-control hooks use `extraData` for
provider selection and credentials. Other templates may use another encoding.

Exceptions and edge cases:

- `executeWithdrawal` accepts a suffix. `executeWithdrawals` deliberately sends
  empty `extraData` to every callback.
- `nukeFromOrbit` accepts a suffix.
- `executePendingAnnualInterestBipsReduction` has no `extraData`.
- Market creation uses the factory's explicit `hooksData` argument instead of a
  suffix.
- The factory-only `setProtocolFeeBips` callback has the same ABI, but the
  supported factory path sends no extra data.

## Integration boundaries

Hooks can reject enabled actions, keep external state, and coordinate several
markets. They cannot replace a transfer recipient, force a withdrawal, or
write market storage. Their authority is limited to enabled callbacks and any
mutable state their implementation exposes.

Indexers should identify instances through known factory events and retain the
template-to-instance-to-market relationship. A display name or `version()`
string is metadata, not implementation identity. See
[Events](./events.md) for ordering and provenance.

See [role providers](./role-providers.md) for credentials, then
[access control](./access-control.md),
[fixed-term hooks](./fixed-term-hooks.md), and
[periodic-term hooks](./periodic-term-hooks.md) for template behavior.

## Tests

- [`HooksConfig.t.sol`](../../test/types/HooksConfig.t.sol): flag packing,
  optional and required merging, and callback encoding
- [`MarketConstraintHooks.t.sol`](../../test/access/MarketConstraintHooks.t.sol):
  creation bounds and APR/reserve-ratio transitions
- [`HooksFactories.t.sol`](../../test/factories/HooksFactories.t.sol): templates,
  instances, identity resolution, market binding, and provenance
- [`WildcatMarket.t.sol`](../../test/market/WildcatMarket.t.sol): callback
  dispatch and action ordering

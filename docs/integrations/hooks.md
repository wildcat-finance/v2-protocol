# Hooks

Hooks are external contracts bound to a Wildcat market at deployment. Enabled
callbacks can inspect an intermediate market state, reject an action, and, in
narrow cases, constrain values before the market applies them.

The market calls hooks with ordinary external calls, not `delegatecall`. Hooks
cannot write market storage directly or bypass market authorization. A hook
revert bubbles through the market and reverts the entire action.

The core interfaces are:

- [`IHooks`](../../src/access/IHooks.sol), which defines creation and ordinary
  market callbacks;
- [`HooksConfig`](../../src/types/HooksConfig.sol), which binds a hook address
  to enabled callback flags; and
- [`IHooksFactory`](../../src/IHooksFactory.sol), which defines template,
  instance, and market provenance.

## Template, instance, and market

1. A **template** is approved stored initcode plus a name and fee configuration
   in `HooksFactory`. Its code begins with a non-executable byte; the factory
   copies the remaining initcode when deploying an instance.
2. A **hooks instance** is a deployed contract created from one template. An
   instance can hold its own configuration and may serve several markets.
3. A **market binding** is the instance address and callback flags stored in the
   market's immutable `HooksConfig`.

A caller deploying an instance or market must resolve to a registered borrower
principal. Instances are indexed under the resolved principal. When a market is
created, the factory passes the caller's resolved principal to `onCreateMarket`;
the current administered templates require it to match their administrator.

For a successful market deployment, the factory computes the market address and
calls `onCreateMarket` before code exists at that address. The hook validates
the deployment parameters, initializes its market-specific state, and returns
the final `HooksConfig`. The factory then deploys and registers the market.

Disabling a template prevents new instances. It does not disable existing
instances or markets, and existing instances may still be used for new markets.
Template disabling is not a kill switch.

## Optional and required callbacks

Each template exposes optional and required flags through `config()`:

- required flags are always enabled for markets using that template;
- optional flags are enabled only when requested or required by the instance's
  market configuration; and
- `onCreateMarket` returns the effective flags stored by the market.

The hook address and effective flags cannot change after market deployment.
The hook contract's own state and administration may still change if its
implementation permits it. Reusing an instance therefore shares that instance's
state and authority domain across its markets.

## Callback surface

### Lender and token paths

- `deposit` and `depositUpTo` call `onDeposit` with the lender and scaled mint
  amount.
- `queueWithdrawal`, `queueWithdrawalScaled`, and `queueFullWithdrawal` call
  `onQueueWithdrawal` with the lender, batch expiry, and scaled amount.
- `executeWithdrawal` and `executeWithdrawals` call `onExecuteWithdrawal` with
  the lender, exact batch expiry, and normalized amount withdrawn. The batched
  entry point calls the hook once per withdrawal.
- `transfer` and `transferFrom` call `onTransfer` with the caller, sender,
  recipient, and scaled amount.

### Credit and lifecycle paths

- `borrow` calls `onBorrow` with the normalized amount.
- `repay` and `repayAndProcessUnpaidWithdrawalBatches` call `onRepay` when the
  repayment amount is nonzero.
- `closeMarket` calls `onCloseMarket`. If the market must pull a final repayment
  first, it calls `onRepay` before `onCloseMarket`.
- `nukeFromOrbit` calls `onNukeFromOrbit`, then queues the sanctioned lender's
  balance through the ordinary `onQueueWithdrawal` path. Term and withdrawal-
  window restrictions can therefore defer quarantine.

### Parameter paths

- `setMaxTotalSupply` calls `onSetMaxTotalSupply` before applying the new cap.
- `setAnnualInterestAndReserveRatioBips` calls
  `onSetAnnualInterestAndReserveRatioBips`, which returns the APR and reserve
  ratio the market will validate and apply.
- `setProtocolFeeBips` calls `onSetProtocolFeeBips` before the factory-supplied
  fee takes effect.
- `executePendingAnnualInterestBipsReduction` uses a separate flag and calls the
  periodic hook directly. The hook returns the pending APR; the market requires
  it to be lower than the current APR before applying it.

The pending-APR-reduction path is specialized behavior defined by
[`IPeriodicTermAprReductionHooks`](../../src/market/WildcatMarketConfig.sol), not
an `IHooks.on*` callback.

## Built-in parameter constraints

`OpenTermHooks`, `FixedTermHooks`, and `PeriodicTermHooks` inherit the same
creation-time bounds:

```text
annualInterestBips          0 .. 10_000
delinquencyFeeBips          0 .. 10_000
withdrawalBatchDuration     0 .. 365 days
reserveRatioBips            0 .. 10_000
delinquencyGracePeriod      0 .. 90 days
```

For ordinary APR updates, the built-in hooks ignore the borrower-supplied
reserve ratio. They preserve the current reserve ratio unless the shared APR
reduction policy below replaces it.

An APR reduction starts a two-week update period anchored to the APR and
reserve ratio before the first reduction. A reduction of at most 25% preserves
that original reserve ratio. A larger reduction sets the temporary ratio to:

```text
max(original reserve ratio, min(100%, 2 * relative APR reduction))
```

A further reduction starts a fresh two-week period. A partial recovery below
the original APR keeps the existing expiry. Returning to or above the original
APR cancels the period and restores the original reserve ratio. At or after
expiry, a non-decreasing update expires the period and restores the original
ratio; a further reduction starts another period against the stored original
values.

Fixed-term markets reject reductions before maturity, then use this shared
policy. Periodic-term reductions instead use their proposal path and preserve
the current reserve ratio; unchanged APRs and increases use the shared path.

## Intermediate-state ordering

The market normally accrues interest and fees and processes expired withdrawal
state before invoking a hook. The supplied `MarketState` is then a snapshot from
before the primary action's accounting effects.

Important boundaries:

- `onQueueWithdrawal` sees a newly created `pendingWithdrawalExpiry`, but not
  the requested amount added to the account, batch, or market totals.
- `onExecuteWithdrawal` receives the exact batch expiry being claimed. It must
  not infer that value from `state.pendingWithdrawalExpiry`, which identifies
  the current pending batch.
- repayment assets reach the market before `onRepay`; repayment accounting is
  applied after the hook.
- `onSetAnnualInterestAndReserveRatioBips` may replace its two proposed values.
  Ordinary callbacks can reject an action but cannot replace its arguments.
- the periodic APR-reduction hook returns one APR through its specialized path;
  the market preserves the existing reserve ratio.

Callbacks are not a complete external accounting ledger. In particular,
partial payments to withdrawal batches have no dedicated hook. A hook that
needs exact pending or unpaid withdrawal state must query the market and apply
the market's accounting rules rather than reconstructing it from callbacks
alone.

## `extraData`

Most hooked market entry points accept an implicit raw suffix. The suffix is not
part of the Solidity function signature. Callers append bytes directly after
the canonical ABI calldata, without another offset, length, or padding word.
The market wraps those bytes as the callback's `bytes extraData` argument.

`extraData` is interpreted by the selected hook implementation. Access-control
hooks use it for provider selection and credential material; other templates
may define different encodings.

There are three relevant boundaries:

- `executeWithdrawal` can carry a suffix, but `executeWithdrawals` deliberately
  passes empty `extraData` to every callback.
- `nukeFromOrbit` can carry a suffix. Earlier documentation incorrectly excluded
  it.
- `executePendingAnnualInterestBipsReduction` has no `extraData` parameter.
  Market creation uses the factory's explicit `hooksData` argument instead of a
  market-calldata suffix.

The factory-only `setProtocolFeeBips` callback uses the same callback ABI, but
the supported factory update path supplies no extra data.

## Integration boundaries

Hooks can restrict enabled actions, maintain external state, and coordinate
several markets. They cannot change a transfer recipient, force a withdrawal,
or mutate market storage directly. Their meaningful authority comes from the
callbacks a market enabled and from any mutable state exposed by the hook
implementation.

Indexers should identify instances through known factory events and preserve
the template-to-instance-to-market relationship. A display name or `version()`
string is metadata, not implementation identity. See
[`events.md`](./events.md) for event ordering and provenance rules.

Access-control credential behavior is documented in
[`role-providers.md`](./role-providers.md). See
[`access-control.md`](./access-control.md),
[`fixed-term-hooks.md`](./fixed-term-hooks.md), and
[`periodic-term-hooks.md`](./periodic-term-hooks.md) for template-specific
behavior.

## Tests

- [`HooksConfig.t.sol`](../../test/types/HooksConfig.t.sol) covers flag packing,
  optional and required merging, and callback encoding.
- [`MarketConstraintHooks.t.sol`](../../test/access/MarketConstraintHooks.t.sol)
  covers creation bounds and APR/reserve-ratio transitions.
- [`HooksFactories.t.sol`](../../test/factories/HooksFactories.t.sol) covers
  templates, instances, identity resolution, market binding, and provenance.
- [`WildcatMarket.t.sol`](../../test/market/WildcatMarket.t.sol) covers callback
  dispatch and action ordering.

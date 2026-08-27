# Periodic Term Hooks

[`PeriodicTermHooks`](../../src/access/PeriodicTermHooks.sol) adds recurring
withdrawal windows and advance notice for APR reductions. It shares the
credential and lender-policy system described in [access control](./access-control.md).

## Withdrawal schedule

### Configuration

Market creation supplies three required ABI words, followed by two optional
words:

```text
uint32 firstWithdrawalWindowStart
uint32 periodDuration
uint32 withdrawalWindowDuration
uint96 minimumDeposit       // optional; defaults to zero
bool transfersDisabled      // optional; defaults to false
```

`firstWithdrawalWindowStart` is the schedule anchor. It may be in the past. If
it is in the future, it cannot be more than
`MaximumInitialWithdrawalWindowDelay` after market creation.

The current bounds are:

| Parameter | Value |
| --- | ---: |
| `MinimumPeriodDuration` | 6 minutes |
| `MaximumPeriodDuration` | 365 days |
| `MinimumWithdrawalWindowDuration` | 1 minute |
| `MaximumInitialWithdrawalWindowDelay` | 365 days |

The window duration must also be strictly shorter than the period. These are
the values enforced by this source revision. The contract marks all four for
finalization before mainnet; they are not a mainnet parameter commitment.

### Queueing and execution

For an open market, a window is active when:

```text
timestamp >= anchor && (timestamp - anchor) % periodDuration < windowDuration
```

The start is inclusive and the end is exclusive. `queueWithdrawal`,
`queueWithdrawalScaled`, and `queueFullWithdrawal` revert with
`WithdrawOutsideWindow` at every other time.

The window gates queueing only. Existing batches retain the market's immutable
`withdrawalBatchDuration`, and executing a queued withdrawal is not
window-gated. Closing a market removes the queueing restriction and cancels any
pending APR-reduction proposal.

### Sanctioned accounts

`nukeFromOrbit` moves a sanctioned account's full balance through the ordinary
queue-withdrawal path. On an open periodic market it therefore reverts outside
a withdrawal window. It can succeed when a window opens or after the market is
closed. This is deliberate current behavior, not an administrative bypass of
the term policy.

## APR reductions

The hooks administrator may propose a reduction. The market's stored APR does
not change until the proposal is executed.

1. **Propose.** The market must be open, the call must occur outside a
   withdrawal window, and the proposed APR must be in range and strictly below
   the market's current APR. The next scheduled window is stored as the lender
   response window. A new proposal cancels and replaces the previous one.
2. **Respond.** Lenders may queue withdrawals during the stored response
   window while the old APR remains active.
3. **Execute.** Execution begins at the response window's end and remains
   available until the next window begins. It requires the exact proposed APR,
   a rate still below the market's current APR, and zero
   `scaledPendingWithdrawals`.

With the current `AprReductionProposalValidityPeriods == 1`, the execution
interval is:

```text
[responseWindowEnd, responseWindowStart + periodDuration)
```

Either path applies the same gates:

- anyone may call the market's
  `executePendingAnnualInterestBipsReduction`; or
- the market borrower may call
  `setAnnualInterestAndReserveRatioBips` with the exact proposed APR.

Both paths preserve the market's current reserve ratio. A reserve-ratio value
supplied with the borrower path is not applied to the reduction.

An APR increase needs no proposal and cancels a pending reduction. Setting the
APR to its current value does not cancel one. Market closure cancels one.
Expiry prevents execution but does not clear storage; an expired proposal
remains readable until another cancelling transition occurs.

### Lender-facing state

A pending proposal adds no deposit or transfer restriction; the market's
ordinary access, minimum-deposit, transfer, and capacity rules still apply. A
lender entering after proposal receives no separate response window.

Interfaces should show the current APR, proposed APR, and stored response-window
bounds. After the response window ends, an executable proposed APR should be
treated as the effective entry rate even though the stored market APR changes
only on execution.

`pendingAprChanges(market)` preserves the first template revision's two-value
ABI. `getPendingAprChange(market)` also returns the stored response-window
bounds. `templateVersion()` returns `2`; `version()` remains
`'PeriodicTermHooks'` for integration compatibility.

## Other market policy

`minimumDeposit` is stored as `uint96`; the existing
`setMinimumDeposit(address,uint128)` input is checked before downcasting. A
positive initial minimum enables the deposit callback. A market created with a
zero minimum and no deposit callback cannot later adopt a positive minimum.

The hook compares the configured minimum and tendered amount after flooring
both to scaled units. The market's independent nonzero-mint, supply-cap,
balance, and allowance checks still apply.

Withdrawal access requires deposit access and either transfer access or
disabled transfers. See [access control](./access-control.md) for credential,
known-lender, deposit-block, and transfer behavior.

## Tests

- [`PeriodicTermHooks.t.sol`](../../test/access/PeriodicTermHooks.t.sol) covers
  schedule boundaries, configuration, proposal transitions, and hook policy.
- [`ProductionMatrixScenarios.t.sol`](../../test/integration/ProductionMatrixScenarios.t.sol)
  covers the periodic template through deployed standard and revolving markets.

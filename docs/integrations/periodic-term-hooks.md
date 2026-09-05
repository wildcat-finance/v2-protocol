# Periodic-term hooks

[`PeriodicTermHooks`](../../src/access/PeriodicTermHooks.sol) adds recurring
withdrawal windows and advance notice for APR reductions. It uses the
credential and lender policy described in [Access control](./access-control.md).

## Withdrawal schedule

### Configuration

Market creation supplies three required ABI words and up to two optional words:

```text
uint32 firstWithdrawalWindowStart
uint32 periodDuration
uint32 withdrawalWindowDuration
uint96 minimumDeposit       // optional; defaults to zero
bool transfersDisabled      // optional; defaults to false
```

`firstWithdrawalWindowStart` anchors the schedule. It can be in the past. A
future start cannot be more than `MaximumInitialWithdrawalWindowDelay` after
market creation.

Current bounds:

| Parameter                             |     Value |
| ------------------------------------- | --------: |
| `MinimumPeriodDuration`               | 6 minutes |
| `MaximumPeriodDuration`               |  365 days |
| `MinimumWithdrawalWindowDuration`     |  1 minute |
| `MaximumInitialWithdrawalWindowDelay` |  365 days |

The window must be shorter than the period. These values are enforced by this
source revision, but the contract marks all four for finalization before
mainnet. They are not a mainnet parameter commitment.

### Queueing and execution

An open market is inside a withdrawal window when:

```text
timestamp >= anchor && (timestamp - anchor) % periodDuration < windowDuration
```

The start is inclusive; the end is exclusive. `queueWithdrawal`,
`queueWithdrawalScaled`, and `queueFullWithdrawal` revert with
`WithdrawOutsideWindow` at every other time.

The schedule only gates queueing:

- Existing batches keep the market's immutable `withdrawalBatchDuration`.
- Withdrawal execution is not window-gated.
- Closing the market removes the queueing restriction and cancels any pending
  APR-reduction proposal.

### Sanctioned accounts

`nukeFromOrbit` sends a sanctioned account's balance through the ordinary
queueing path. On an open periodic market, it reverts outside a withdrawal
window. It can succeed when a window opens or after closure.

This is the current policy. `nukeFromOrbit` is not an administrative bypass of
the term schedule.

## APR reductions

The hooks administrator can propose a reduction. The market's stored APR stays
unchanged until execution.

1. **Propose:** The market must be open, and the call must happen outside a
   withdrawal window. The proposed APR must be in range and below the current
   APR. The hook stores the next scheduled window as the lender response window.
   A new proposal replaces the old one.
2. **Respond:** Lenders can queue withdrawals during that response window while
   the old APR remains active.
3. **Execute:** Execution opens when the response window ends and closes when
   the next window begins. The caller must provide the exact proposed APR. It
   must still be below the current APR, and `scaledPendingWithdrawals` must be
   zero.

With `AprReductionProposalValidityPeriods == 1`, execution is available during:

```text
[responseWindowEnd, responseWindowStart + periodDuration)
```

Either of these paths can execute:

- anyone calls `executePendingAnnualInterestBipsReduction`; or
- the borrower calls `setAnnualInterestAndReserveRatioBips` with the exact
  proposed APR.

Both paths keep the current reserve ratio. The borrower path ignores any new
reserve-ratio value supplied with the reduction.

Other proposal transitions:

- An APR increase cancels a pending reduction and needs no proposal.
- Setting the APR to its current value does not cancel a proposal.
- Closing the market cancels a proposal.
- Expiry blocks execution but does not clear storage. The expired proposal
  remains readable until another transition clears or replaces it.

### Lender-facing state

A pending proposal adds no deposit or transfer restriction. Ordinary access,
minimum-deposit, transfer, and capacity rules still apply. A lender entering
after the proposal gets no separate response window.

Interfaces should show:

- current APR;
- proposed APR; and
- stored response-window bounds.

After the response window ends, an executable proposed APR should be treated as
the effective entry rate even though the stored market APR changes only on
execution.

`pendingAprChanges(market)` keeps the first template revision's two-value ABI.
`getPendingAprChange(market)` also returns the response-window bounds.
`templateVersion()` returns `2`; `version()` remains `'PeriodicTermHooks'` for
integration compatibility.

## Other market policy

`minimumDeposit` is stored as `uint96`. The existing
`setMinimumDeposit(address,uint128)` input is checked before downcasting.

A positive initial minimum enables the deposit callback. A market created with
a zero minimum and no deposit callback cannot add a positive minimum later. The
hook compares the minimum and tendered amount after flooring both to scaled
units. Independent nonzero-mint, supply-cap, balance, and allowance checks still
apply.

Withdrawal access requires deposit access and either transfer access or
disabled transfers. See [Access control](./access-control.md) for credentials,
known-lender state, deposit blocks, and transfer policy.

## Tests

- [`PeriodicTermHooks.t.sol`](../../test/access/PeriodicTermHooks.t.sol): schedule
  boundaries, configuration, proposal transitions, and hook policy
- [`ProductionMatrixScenarios.t.sol`](../../test/integration/ProductionMatrixScenarios.t.sol):
  standard and revolving market deployments using this template

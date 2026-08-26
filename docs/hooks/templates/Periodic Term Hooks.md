# Periodic Term Hooks

`PeriodicTermHooks` restricts withdrawals to a recurring scheduled window, sitting between the open template (withdraw any time) and the fixed template (withdraw only after a single end date). It inherits the same access-control machinery as the other templates (see [Access Control Hooks](../../integrations/access-control.md)) and adds two mechanisms: withdrawal windows and gated APR reductions.

## Withdrawal windows

At market creation the borrower configures:

- `firstWithdrawalWindowStart` — when the first window opens (at most one maximum period in the future)
- `periodDuration` — how often a window recurs
- `withdrawalWindowDuration` — how long each window stays open (must be shorter than the period)

Windows are start-inclusive and end-exclusive: withdrawals may be queued at `windowStart` and may not at `windowStart + withdrawalWindowDuration`. Between windows, `queueWithdrawal`, `queueWithdrawalScaled`, and `queueFullWithdrawal` revert `WithdrawOutsideWindow`. Withdrawal *batches* still expire on the market's immutable `withdrawalBatchDuration`, independent of the window schedule. The window gates only when a withdrawal can be *queued*.

A closed market bypasses the window entirely: once the borrower closes, lenders can exit at any time.

Because `nukeFromOrbit` routes through the ordinary withdrawal path (see Known Issues, CAF-03), sanctioned accounts on a periodic market can only be quarantined while a window is open. This recurs each period and was reviewed and accepted as the same trade-off as a long fixed term.

## APR reductions

On open markets a borrower can lower the APR at will (subject to the temporary reserve-ratio penalty in `MarketConstraintHooks`). On periodic markets, lenders can only respond during windows — so APR reductions are gated behind a proposal flow that guarantees lenders one full withdrawal window to exit at the old rate:

1. **Propose.** The borrower calls `proposeAnnualInterestBips(market, newBips)` with a value strictly below the current APR, outside a withdrawal window and on an open market. The response window is fixed at proposal time: the next scheduled withdrawal window.
2. **Respond.** Lenders who object exit during that window at the unreduced APR.
3. **Execute.** After the response window ends — and before the proposal expires (`AprReductionProposalValidityPeriods` periods after the response window starts) — the reduction can be executed, provided there are no unpaid withdrawal batches. Execution happens either through the borrower calling the market's `setAnnualInterestAndReserveRatioBips` with the exact proposed value, or **permissionlessly by anyone** through the market's `executePendingAnnualInterestBipsReduction`, so a proposal that lenders implicitly accepted cannot be held hostage by borrower inaction.

Proposals are cancelled by: proposing again (overwrite), raising the APR through the ordinary setter, or closing the market. Expired proposals cannot be executed and must be re-proposed.

APR *increases* need no proposal and pass straight through to the base constraint hooks.

Deposits and transfers remain open throughout the proposal lifecycle. A new lender does not receive a separate response window: the pending reduction is part of the disclosed entry terms. Market and deposit interfaces must show the current APR, proposed APR, and response-window timing. Once the response window has ended, interfaces should treat the executable proposed APR as the effective entry rate even though the market's stored APR does not change until execution.

## Configuration notes

- `minimumDeposit` and `transfersDisabled` behave as in the other templates, except that this template stores the minimum as `uint96` (checked downcast; the external `setMinimumDeposit(address,uint128)` ABI is unchanged) to keep its market config in one storage slot. The minimum-deposit check compares in scaled units (see [Scale Factor — Rounding](../../protocol/scaling-and-rounding.md#rounding)), so depositing exactly the minimum always succeeds.
- The template rejects inconsistent access configurations at market creation: withdrawal access control requires deposit access control, and transfer access control unless transfers are disabled.
- `pendingAprChanges(market)` retains the ABI of the first template revision; `getPendingAprChange(market)` additionally returns the response window bounds. `templateVersion()` distinguishes template revisions while `version()` remains `'PeriodicTermHooks'` for subgraph matching.

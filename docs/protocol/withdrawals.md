# Withdrawals

Wildcat groups lender withdrawal requests into fixed-duration batches. Batches
give lenders in the same period a pro-rata claim on available liquidity when a
market cannot immediately satisfy every request.

## Queueing and Batch Ownership

If no current batch exists, the first request creates one. Later requests join
that batch until its expiry.

Markets expose three queueing methods:

- `queueWithdrawal(uint256)` requests a normalized market-token amount;
- `queueWithdrawalScaled(uint256)` requests an exact scaled amount for wrapper
  and other scaled-balance integrations; and
- `queueFullWithdrawal()` requests the caller's entire direct market-token
  balance.

Queueing removes the scaled amount from the lender's balance and assigns it to
the batch. It does not reduce total supply. The batch continues earning interest
until underlying assets are reserved and the corresponding scaled tokens are
burned.

Batch ownership is recorded in scaled units. Equal normalized requests queued
at different scale factors may therefore settle to slightly different final
normalized amounts. This reflects interest accrued between the queue events,
not the order in which lenders later execute paid withdrawals.

`queueWithdrawalScaled` preserves the requested scaled amount exactly and
derives its normalized event amount at queue time. `queueFullWithdrawal` only
queues the caller's direct market-token balance.

## Batch States

- **Current:** accepts requests until expiry. It may remain recorded as current
  after its timestamp passes, until the next state update processes it.
- **Unpaid:** expired without enough reserved assets to cover every request.
- **Paid:** has enough assets reserved, although lenders may not yet have
  executed their individual claims.

## Expiry and Priority

An underfunded batch enters a first-in-first-out queue of unpaid batches.
Earlier unpaid batches receive payment priority. Lenders within one batch share
the assets allocated to it pro rata by scaled ownership.

When the current batch expires, its immediately available liquidity is the
market's total underlying balance minus:

- paid but unclaimed withdrawals;
- the normalized value of prior unpaid withdrawals; and
- accrued protocol fees.

This calculation can fully pay the expiring batch while older unpaid batches
exist only when the market already holds enough assets to cover those older
obligations as well. Once a batch enters the unpaid queue, it is processed in
FIFO order. See
[`WithdrawalLib.availableLiquidityForPendingBatch`](../../src/libraries/Withdrawal.sol).

## Payment and Execution

*Payment* reserves underlying assets for a batch and burns the corresponding
scaled market tokens. The burned amount stops accruing interest. The reserved
underlying is added to `normalizedUnclaimedWithdrawals` and cannot be borrowed,
used for protocol fees, or allocated to another batch.

Payment may occur:

- when a lender adds a request to the current batch;
- during a state update for the current batch; or
- through `repayAndProcessUnpaidWithdrawalBatches` for expired unpaid batches.

Each partial payment converts available underlying into a settleable scaled
amount. Its normalized payment value is rounded down independently, discarding
less than one atomic unit of the underlying. Fractional remainders are not
carried between payments.

Plain `repay` transfers assets into the market and updates state, but does not
walk the unpaid queue. Callers that want the same transaction to route new
liquidity through that queue must use
`repayAndProcessUnpaidWithdrawalBatches`.

*Execution* transfers a lender's paid pro-rata claim out of the market. It is
permissionless for an account and batch, but only after batch expiry. If the
lender is sanctioned, execution routes the assets to that lender's sanctions
escrow instead.

See
[`WildcatMarketWithdrawals`](../../src/market/WildcatMarketWithdrawals.sol) for
queueing, payment, and execution.

## Representation Limits

Batch totals, paid scaled amounts, and each account's queued amount are stored as
`uint104`. Totals are cumulative for one expiry and do not shrink when paid
shares are executed. Checked arithmetic reverts rather than wrapping if a batch
or account reaches the representation limit.

## Closing a Market

`closeMarket()` processes every unpaid withdrawal batch before marking the
market closed. Gas cost therefore grows with the unpaid queue. A caller can
bound that work beforehand with
`repayAndProcessUnpaidWithdrawalBatches(0, maxBatches)`, then close after the
queue is small enough for one transaction.

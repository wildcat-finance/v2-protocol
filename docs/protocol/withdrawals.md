# Withdrawals

Wildcat groups withdrawal requests into fixed-duration batches. If a market
cannot satisfy every request immediately, lenders in the same batch share the
available liquidity pro rata.

## Queueing and batch ownership

The first request creates a batch. Later requests join it until expiry.

Markets expose three queueing methods:

- `queueWithdrawal(uint256)` queues a normalized market-token amount.
- `queueWithdrawalScaled(uint256)` queues an exact scaled amount. Wrappers and
  other scaled-balance integrations should use this path.
- `queueFullWithdrawal()` queues the caller's full direct market-token balance.

Queueing moves the scaled amount out of the lender's balance and into the
batch. It does not reduce total supply. The batch keeps earning interest until
the market reserves underlying assets and burns the corresponding scaled
tokens.

Batch ownership is stored in scaled units. Two equal normalized requests made
at different scale factors may settle to slightly different normalized
amounts. That difference comes from interest between the queue events, not the
order in which lenders later execute.

`queueWithdrawalScaled` preserves the exact requested scaled amount. Its event
reports the normalized value at queue time. `queueFullWithdrawal` only includes
the caller's direct market-token balance.

## Batch states

- **Current:** accepts requests until expiry. It can remain recorded as current
  after its timestamp passes, until the next state update processes it.
- **Unpaid:** expired without enough reserved assets to cover every request.
- **Paid:** has enough assets reserved, but lenders may not have executed their
  claims yet.

## Expiry and priority

An underfunded batch enters the unpaid queue. That queue is first in, first out.
Earlier batches get paid first; lenders inside one batch split its allocation
by scaled ownership.

At expiry, the current batch can use the market's underlying balance after
subtracting:

- paid but unclaimed withdrawals;
- the normalized value of earlier unpaid withdrawals; and
- accrued protocol fees.

If expiry is processed by a later transaction, the batch uses the last
underlying balance observed by a market state write at or before expiry. Assets
first observed after expiry remain available from that checkpoint onward, but
cannot retroactively change batch settlement or delinquency for the elapsed
interval.

The ERC-20 does not record when an asset was transferred directly to the
market. To make a direct transfer count at expiry, call `updateState()` after
the transfer and no later than the expiry timestamp. Repayment and other market
actions write state themselves.

An expiring batch can be paid while older unpaid batches exist only if the
market already holds enough assets for those older obligations. Once a batch
enters the unpaid queue, later payments follow FIFO order. See
[`WithdrawalLib.availableLiquidityForPendingBatch`](../../src/libraries/Withdrawal.sol).

## Payment and execution

_Payment_ reserves underlying assets for a batch and burns the matching scaled
market tokens. Burned tokens stop earning interest. Reserved assets move into
`normalizedUnclaimedWithdrawals`; they cannot be borrowed, paid as protocol
fees, or allocated to another batch.

Payment can happen:

- when a lender adds a request to the current batch;
- during a state update for the current batch; or
- through `repayAndProcessUnpaidWithdrawalBatches` for expired unpaid batches.

Each partial payment converts available underlying into a settleable scaled
amount. The normalized payment rounds down independently, discarding less than
one atomic unit of the underlying. Fractional remainders do not carry into the
next payment.

Plain `repay` transfers assets into the market and updates state. It does not
walk the unpaid queue. Use `repayAndProcessUnpaidWithdrawalBatches` when the
same transaction should route new liquidity through that queue.

A repayment made after an unprocessed expiry first settles the expiry against
the checkpointed balance. The combined repayment path can then apply the newly
received assets to the resulting unpaid queue in the same transaction, subject
to `maxBatches` and FIFO order.

_Execution_ transfers a lender's paid pro-rata claim out of the market. Anyone
can execute for an account and batch after the batch expires. If the lender is
sanctioned, the market sends the assets to that lender's sanctions escrow.

See
[`WildcatMarketWithdrawals`](../../src/market/WildcatMarketWithdrawals.sol) for
queueing, payment, and execution.

## Representation limits

Batch totals, paid scaled amounts, and each account's queued amount use
`uint104`. Totals are cumulative for one expiry and do not shrink when lenders
execute paid shares. Checked arithmetic reverts instead of wrapping if a batch
or account reaches the limit.

## Closing a market

`closeMarket()` processes every unpaid withdrawal batch before closing the
market. Its gas cost grows with the unpaid queue.

Before closing, a caller can bound that work with:

```solidity
repayAndProcessUnpaidWithdrawalBatches(0, maxBatches)
```

Once the queue is small enough, `closeMarket()` can finish it in one
transaction.

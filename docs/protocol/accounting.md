# Accounting and State Updates

Wildcat markets use scaled balances so lender interest can accrue without
updating every account. See [Scaling and Rounding](./scaling-and-rounding.md)
for the conversion rules.

## Collateral Obligation

Market tokens in a current or expired unpaid withdrawal batch must be covered
100% by underlying assets. Tokens that are not pending withdrawal are covered
at the configured reserve ratio. The latter are the market's *outstanding
supply*.

Paid but unclaimed withdrawals must remain fully reserved until execution.
Accrued protocol fees are also part of the market's obligation. Neither balance
earns lender interest.

`state.liquidityRequired()` is the sum of:

- normalized pending withdrawals;
- normalized unclaimed withdrawals;
- the reserve ratio applied to outstanding supply; and
- accrued protocol fees.

```solidity
uint256 normalizedPendingWithdrawals = state.normalizeAmount(state.scaledPendingWithdrawals);
uint256 normalizedOutstandingSupply = state.totalSupply() - normalizedPendingWithdrawals;

normalizedPendingWithdrawals
+ normalizedOutstandingSupply.bipMul(state.reserveRatioBips)
+ state.normalizedUnclaimedWithdrawals
+ state.accruedProtocolFees
```

Outstanding supply and pending withdrawals are kept in the same rounding
domain. At a 100% reserve ratio they recombine exactly to `state.totalSupply()`.
See [`MarketState.liquidityRequired`](../../src/libraries/MarketState.sol) for
the implementation.

## Delinquency

A market is delinquent when its underlying assets are below
`state.liquidityRequired()`. While delinquent, `state.timeDelinquent` increases
once per second. While healthy, it decreases toward zero.

The delinquency fee applies for time spent above `delinquencyGracePeriod`.
Because the timer decays rather than resetting immediately, a borrower that
remains beyond the grace period is penalized both while the timer rises and
while the excess later decays.

## Interest and Fees

Accrual uses two lender rates and one protocol-fee fraction:

- `annualInterestBips` is the base annual rate paid to lenders;
- `delinquencyFeeBips` is added while the market is in penalized delinquency;
  and
- `protocolFeeBips` is the protocol's fraction of base interest, charged in
  addition to lender interest.

Base interest and delinquency fees increase `scaleFactor`. Protocol fees are
calculated from base interest and added separately to `accruedProtocolFees`;
they do not increase the lender scale factor. See
[`FeeMath.updateScaleFactorAndFees`](../../src/libraries/FeeMath.sol).

## State Updates

State-changing market functions calculate updated market state before applying
their own action. Interest and fee accrual advance only when the timestamp has
changed, so later calls in the same timestamp do not accrue the interval again.

Without an expired batch, an update:

1. accrues base interest, delinquency fees, and protocol fees;
2. advances or decays the delinquency timer; and
3. applies available liquidity to the current withdrawal batch.

If the current batch expired between updates, accrual is split at its expiry.
The market accrues to the expiry, processes the batch, accrues from the expiry
to the current timestamp, then applies liquidity to any remaining current
batch. This prevents the borrower from paying interest after assets could have
been reserved for an expiring withdrawal.

The final state write recalculates delinquency from the updated liquidity
requirement and current underlying balance. See
[`WildcatMarketBase._getUpdatedState`](../../src/market/WildcatMarketBase.sol)
and [Withdrawals](./withdrawals.md).

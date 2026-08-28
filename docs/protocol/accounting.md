# Accounting and state updates

Wildcat markets use scaled balances so lender interest can accrue without
updating every account. [Scaling and rounding](./scaling-and-rounding.md) covers
the conversion rules.

## Collateral obligation

The market must hold enough underlying assets to cover:

- 100% of market tokens in the current withdrawal batch;
- 100% of market tokens in expired, unpaid batches;
- the configured reserve ratio for every other market token; and
- accrued protocol fees.

Tokens outside a withdrawal batch make up the market's _outstanding supply_.
Paid but unclaimed withdrawals remain fully reserved until execution. Neither
that balance nor accrued protocol fees earns lender interest.

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

Outstanding supply and pending withdrawals use the same rounding domain. At a
100% reserve ratio, they add back to exactly `state.totalSupply()`. See
[`MarketState.liquidityRequired`](../../src/libraries/MarketState.sol).

## Delinquency

A market is delinquent when its underlying balance is below
`state.liquidityRequired()`.

- While delinquent, `state.timeDelinquent` increases once per second.
- While healthy, it decreases toward zero.

The delinquency fee applies to time above `delinquencyGracePeriod`. The timer
decays instead of resetting. Once it passes the grace period, the borrower pays
the penalty while the timer rises and while the excess later decays.

Each accrual interval uses the previously stored `isDelinquent` value. The final
state write compares the updated liquidity requirement with the current
underlying balance. That result becomes the status for the next interval.

Nothing changes autonomously between state writes.

## Interest and fees

Accrual uses two lender rates and one protocol-fee fraction:

- `annualInterestBips` is the base annual rate paid to lenders;
- `delinquencyFeeBips` is added while the market is in penalized delinquency;
  and
- `protocolFeeBips` is the protocol's fraction of base interest, charged on top
  of lender interest.

Base interest and delinquency fees increase `scaleFactor`. Protocol fees are
calculated from base interest and added to `accruedProtocolFees`. They do not
increase the lender scale factor. See
[`FeeMath.updateScaleFactorAndFees`](../../src/libraries/FeeMath.sol).

Each accrual interval rounds its protocol fee to the underlying asset's atomic
unit. Fractional remainders do not carry into the next update. More frequent
updates can therefore change the aggregate protocol fee through repeated
rounding. Lender interest is unaffected.

## State updates

Every state-changing market function updates market state before applying its
own action. Interest and fees only advance when the timestamp changes. Later
calls in the same timestamp do not accrue the interval again.

Without an expired batch, an update:

1. accrues base interest, delinquency fees, and protocol fees;
2. advances or decays the delinquency timer; and
3. applies available liquidity to the current withdrawal batch.

If the current batch expired between updates, the market splits accrual at the
expiry:

1. accrue to the batch expiry;
2. process the batch;
3. accrue from expiry to the current timestamp; and
4. apply liquidity to any remaining current batch.

The borrower does not pay interest on assets after they could have been reserved
for the expiring withdrawal.

The final write recalculates delinquency from the updated liquidity requirement
and current underlying balance. See
[`WildcatMarketBase._getUpdatedState`](../../src/market/WildcatMarketBase.sol)
and [Withdrawals](./withdrawals.md).

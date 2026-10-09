# Accounting and state updates

Wildcat markets use scaled balances so lender interest can accrue without
updating every account. [Scaling and rounding](./scaling-and-rounding.md) covers
the conversion rules.

## Total debt and withdrawal fractions

`totalSupply()` reports the normalized value of live scaled shares. It does
not include the fractions retained between withdrawal payments.

Each batch carries a `paymentRemainder` below `RAY`. The market's
`withdrawalRemainder` is the sum of retained batch fractions. They remain debt,
but no longer earn interest after the corresponding shares burn. Debt accounting
combines live shares and these fractions before rounding:

```text
lenderDebt = (scaledTotalSupply * scaleFactor + withdrawalRemainder + RAY / 2) / RAY
totalDebts = lenderDebt + normalizedUnclaimedWithdrawals + accruedProtocolFees
```

These formulas use integer division and `RAY = 1e27`. Use `totalDebts()` for
funding and surplus calculations; adding plain `totalSupply()` to funded claims
and fees omits the retained fractions. See
[withdrawal payments](./withdrawals.md#payment-and-execution) for accumulation
and final release.

## Collateral obligation

The market must hold enough underlying assets to cover:

- 100% of market tokens in the current withdrawal batch;
- 100% of market tokens in expired, unpaid batches;
- the configured reserve ratio for every other market token; and
- accrued protocol fees.

Tokens outside a withdrawal batch make up the market's _outstanding supply_.
Paid but unclaimed withdrawals remain fully reserved until execution. Neither
that balance nor accrued protocol fees earns lender interest. Retained payment
fractions are included with pending withdrawals before normalization.

`state.liquidityRequired()` is the sum of:

- normalized pending withdrawals;
- normalized unclaimed withdrawals;
- the reserve ratio applied to outstanding supply; and
- accrued protocol fees.

```solidity
uint256 normalizedPendingWithdrawals =
  state.normalizeWithRemainder(state.scaledPendingWithdrawals, state.withdrawalRemainder);
uint256 normalizedLenderDebt =
  state.normalizeWithRemainder(state.scaledTotalSupply, state.withdrawalRemainder);
uint256 normalizedOutstandingSupply = normalizedLenderDebt - normalizedPendingWithdrawals;

normalizedPendingWithdrawals
+ normalizedOutstandingSupply.bipMul(state.reserveRatioBips)
+ state.normalizedUnclaimedWithdrawals
+ state.accruedProtocolFees
```

Outstanding supply and pending withdrawals use the same rounding domain. Their
sum is exactly the carry-aware lender debt, not plain `state.totalSupply()`.
At a 100% reserve ratio, `liquidityRequired()` equals `totalDebts()`. See
[`MarketState.liquidityRequired`](../../src/libraries/MarketState.sol).

## Delinquency

A market is delinquent when its underlying balance is below
`state.liquidityRequired()`.

- While delinquent, `state.timeDelinquent` increases once per second.
- While healthy, it decreases toward zero.

The delinquency fee applies to time above `delinquencyGracePeriod`. The timer
decays instead of resetting. Once it passes the grace period, the borrower pays
the penalty while the timer rises and while the excess later decays.

At an enabled repayment date, underfunded intervals incur penalty immediately;
unused grace no longer delays it. The separate 90-day default run resets on a
healthy state write, even if the ordinary delinquency timer still has residual
decay. See [repayment and default](./repayment-and-default.md).

Each accrual interval uses the previously stored `isDelinquent` value. The final
state write compares the updated liquidity requirement with the current
underlying balance. That result becomes the status for the next interval.

Views can project accrued state, but only a successful state write commits
accounting, default records and events.

## Interest and fees

Accrual uses two lender rates and one protocol-fee fraction:

- `annualInterestBips` is the base annual rate paid to lenders;
- `delinquencyFeeBips` is added while the market is in penalized delinquency;
  and
- `protocolFeeBips` is the protocol's fraction of base interest, charged on top
  of lender interest.

In revolving markets, base lender interest combines the fixed commitment fee
and utilization-weighted APR. Both contribute to the protocol-fee basis;
delinquency fees do not.

Base interest and delinquency fees increase `scaleFactor`. Protocol fees are
calculated from base interest and added to `accruedProtocolFees`. They do not
increase the lender scale factor. See
[`WildcatMarketBase._updateScaleFactorAndFees`](../../src/market/WildcatMarketBase.sol).

Each accrual interval rounds its protocol fee to the underlying asset's atomic
unit. Fractional remainders do not carry into the next update. More frequent
updates can therefore change the aggregate protocol fee through repeated
rounding. This fee rounding does not change lender balances.

Base lender interest is linear within one accrual interval and is applied to
the scale factor stored at the interval's start. More frequent checkpoints split
the same wall-clock span into more compounding intervals, so checkpoint cadence
can change aggregate lender interest. This is separate from protocol fee
rounding.

## State updates

State-changing market functions advance prior accounting before giving their
own economic effect to an elapsed interval. Repayment assets may be transferred
first so one transaction can also process withdrawals, but an unprocessed
expiry or repayment boundary uses the asset balance from the preceding
checkpoint. Interest and fees only advance when the timestamp changes.
Later calls in the same timestamp do not accrue the interval again.

Without an intervening expiry or repayment boundary, an update:

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

Scheduled markets also split at the repayment date and inclusive deadline.
The same transition calculation serves views and state updates. Coincident
boundaries apply the date, then judge the deadline, then process batch expiry;
the default marker is not recorded at the cutoff timestamp itself. Full
historical funding can close a scheduled market at its repayment date. No
interest accrues after that effective closure timestamp.

The final write recalculates delinquency from the updated liquidity requirement
and current underlying balance. See
[`WildcatMarketBase._getUpdatedState`](../../src/market/WildcatMarketBase.sol)
and [Withdrawals](./withdrawals.md).

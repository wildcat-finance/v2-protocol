# Repayment and default

New V2.5 standard and revolving markets support optional scheduled repayment
and a permanent default marker. Fixed maturity and periodic withdrawal windows
remain hook policies. They do not set the market's repayment date.

Repayment requires full funding and ends in automatic closure. Default records
an unmet obligation; it does not itself close a market, accelerate repayment,
change rates, or open withdrawals.

## Repayment terms

Both factories accept `uint32 repaymentDate` and `uint32 repaymentPeriod` in
`DeployMarketInputs`. The hook receives them during `onCreateMarket`, before
market code exists. The market stores them immutably and exposes:

| Getter | Meaning |
| --- | --- |
| `repaymentDate()` | Unix timestamp at which full repayment begins; zero disables scheduled repayment. |
| `repaymentPeriod()` | Seconds from that date through the inclusive deadline. |
| `repaymentDeadline()` | Date plus period, or zero when disabled. |
| `defaultedAt()` | The permanent default timestamp already recorded by a state update; zero means none recorded. |

These getters can be read during hook callbacks. Borrower and hook-administrator
transfers cannot change the terms.

The market constructor enforces:

- A zero date requires a zero period.
- A nonzero date must be strictly in the future.
- Date plus period must fit a `uint32` timestamp.

A nonzero date with a zero period is valid. Its deadline is the date itself,
so funding must be observed no later than that timestamp. Interfaces should
explain that there is no additional repayment interval.

The supplied hooks impose further creation limits through
`getParameterConstraints()`:

| Policy | Maximum period | Repayment-date limit |
| --- | ---: | --- |
| Open and periodic | 90 days | At most 730 days after creation. |
| Fixed | 90 days | On or after fixed maturity; no additional date-delay cap beyond the market's timestamp bound. |

These are the current template limits. A registered template's
`_getParameterConstraints()` controls both discovery and enforcement. Limits
are not chosen through arbitrary borrower constructor data. Final network
parameters belong to the [deployment preparation](../operations/deployment.md#release-workflow).

## Reaching the date

From `repaymentDate`, an open market:

1. Requires 100% reserves without a borrower setter call or prior funding.
2. Applies the delinquency rate immediately while underfunded, with no remaining
   grace period. The configured penalty rate and its full-balance basis are unchanged.
3. Rejects deposits and borrowing. `maximumDeposit()` and `borrowableAssets()`
   return zero.
4. Skips `onQueueWithdrawal`, including its access and term restrictions.
   Market sanctions checks still apply.

The configured batch duration, pro-rata allocation and FIFO priority continue
during repayment. Reaching the date does not shorten an existing batch or make
unfunded claims collectible. See [withdrawals](./withdrawals.md).

Neither APR path can restore a lower reserve ratio. While the market is
underfunded, its funding check prevents APR updates; once fully funded,
automatic closure prevents them. Scheduled repayment does not restart an
existing penalty run or give an already defaulted market another grace period.

## Funding and the inclusive deadline

Full funding means underlying assets cover `totalDebts()`:

```text
totalSupply + normalizedUnclaimedWithdrawals + accruedProtocolFees
```

Total supply includes unpaid withdrawal shares. Lenders do not have to collect
every claim before the obligation is funded.

Funding observed by a successful market state write at the exact deadline
counts, including a later transaction with the same block timestamp. An
unfunded deadline is recorded as default only at a later timestamp. A late
repayment can fund and close the market but cannot erase the missed deadline.

When no transaction occurs at a boundary, the market replays it on the next
update using the last asset balance checkpointed at or before it. A repayment
transfers assets before updating state; those newly arrived assets cannot
retroactively satisfy an earlier deadline. A direct token transfer is a
donation, not an explicit principal repayment. It must be followed by a market
state write by the deadline to count as observed funding then.

If the repayment date, deadline and batch expiry coincide, accounting handles
the date first, then the deadline, then expiry. Deadline failure is judged only
when the current timestamp is strictly later. This also makes a zero-period
market's deadline inclusive.

## Consecutive penalty default

Every new V2.5 market tracks an uninterrupted period of underfunded penalty,
including markets without repayment terms. After 90 days, an uncured run
records default at its cutoff. The market waits until a strictly later
timestamp before recording it, so a full cure at the exact cutoff still counts.

This run is separate from `timeDelinquent`:

- Ordinary grace determines when the run starts. At the repayment date, unused
  grace ends without restarting an earlier run.
- A successful healthy state write resets the run. The existing delinquency
  timer still decays, and its residual penalty fees can continue before repayment.
- Partial funding that leaves the market delinquent does not reset it.
- The penalty condition counts even when `delinquencyFeeBips` is zero.
- A cure first observed after the cutoff cannot erase the completed run.

The first qualifying cutoff sets `defaultedAt` once. There is no administrative
setter, clearing function, or reason field. Later repayment, authority changes,
closure, or another trigger do not replace that timestamp.

## Automatic closure and collection

At or after the repayment date, full funding closes the market permanently.
If checkpointed assets were already sufficient at the date, closure is effective
then, even when the next transaction arrives later. Otherwise closure happens
when an update observes sufficient funding. Full funding before the date, or
without repayment terms, does not trigger automatic closure.

Closure sets APR to zero, keeps 100% reserves, stops accrual, clears the
delinquency timer and closes the current batch. Older unpaid batches remain
fully backed and can be allocated in bounded calls to
`repayAndProcessUnpaidWithdrawalBatches(0, maxBatches)`. Lenders can continue
queueing and collecting. Deposits and borrowing never resume.

Automatic closure does not call `onCloseMarket` or transfer surplus to the
borrower. The borrower separately recovers assets above all debts with
`rescueTokens(asset)`. A failed surplus transfer affects only that call.
See [market closure](./markets.md#closure) for the manual path and surplus rules.

A nonzero repayment to an already closed market reverts. This also applies
when replay discovers that the market was fully funded and closed at an earlier
boundary. Use `updateState()` to commit that state and the zero-repayment batch
processor to finish allocation.

Withdrawal execution never calls a hook in new V2.5 markets, with or without
repayment terms. Funding, batch accounting and sanctions escrow still govern
collection. The constructor rejects the execution-hook flag.

## Reads and events

`currentState()` and `isClosed()` project accrued state without writing it.
`previousState()`, stored APR/reserve getters and `defaultedAt()` report
committed values. A zero default marker is not proof that an unprocessed
deadline was met. A reverting transaction commits no transitions or events.

Factories emit `MarketRepaymentTerms` at deployment. Markets emit
`RepaymentDateReached` and `DefaultRecorded` when their updates commit the
respective transition. Effective timestamps can precede the emitting block.
Use the [event guide](../integrations/events.md#repayment-default-and-closure)
and [lens guide](../integrations/lenses.md#repayment-and-default) when indexing
or displaying lifecycle state.

## Tests

- [`RepaymentPrototype.t.sol`](../../test/integration/RepaymentPrototype.t.sol):
  creation limits, both market types and all supplied term policies.
- [`LifecycleScenarios.t.sol`](../../test/invariants/LifecycleScenarios.t.sol):
  inclusive deadlines, unobserved donations, boundary ordering and closure.
- [`PenaltyLifecycleScenarios.t.sol`](../../test/invariants/PenaltyLifecycleScenarios.t.sol):
  exact-cutoff cures and reset behavior.
- [`RepaymentLifecycleInvariant.t.sol`](../../test/invariants/RepaymentLifecycleInvariant.t.sol)
  and [`PenaltyLifecycleInvariant.t.sol`](../../test/invariants/PenaltyLifecycleInvariant.t.sol):
  stateful checks against independent lifecycle models.
- [`MarketSurplus.t.sol`](../../test/market/MarketSurplus.t.sol): protected
  liabilities, failed borrower transfers and post-closure batch processing.

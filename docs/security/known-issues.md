# Known limitations and accepted behavior

This page records deliberate V2.5 behavior that can look like a vulnerability
without the surrounding assumptions. It covers the active source, not every
historical deployment. Use deployment provenance to decide which generation a
market actually runs.

This is not an exhaustive safe-harbor list. Report any materially different
path, earlier boundary, arithmetic error, or practical loss that is not the
behavior described here.

## Credit and borrower authority

Wildcat markets make undercollateralized loans. Borrower default is credit risk.
So is adverse use of authority that a market explicitly grants its borrower,
including drawing available assets and making permitted term changes. A lender
must evaluate the borrower, market terms, and hook policy.

Closing a market returns only assets left after all lender debt, paid and unpaid
withdrawal liabilities, and protocol fees are accounted for. If the operational
borrower or its recorded principal has since been flagged by the sanctions
oracle, closure can still send that unencumbered surplus to the operational
borrower. The sanctions check on `borrow` prevents either flagged identity from
drawing lender-backed value; closure is allowed to settle the market.

## Lazy delinquency accounting

Market accounting advances on state writes. An elapsed interval uses the
previously stored delinquency flag, then the final state write records whether
the market is delinquent for the next interval. A threshold crossed between
transactions is therefore recognized at the next checkpoint, not at the exact
second of the crossing. Permissionless state updates and the Hydra keeper
reduce this timing difference but cannot remove block and polling latency.

Withdrawal expiry is a stricter boundary. A delayed update settles the expired
batch and classifies the post-expiry interval using the last asset balance that
the market checkpointed at or before expiry. A direct transfer first observed
after expiry becomes current liquidity but does not rewrite the elapsed
history. Because an ERC-20 balance does not retain transfer timestamps, a
direct transfer intended to count at expiry must be followed by a market state
write no later than that timestamp.

Closing accrues through the close timestamp, then clears the delinquency timer.
Interest and delinquency fees do not continue through the remaining grace or
decay period after closure.

See [accounting](../protocol/accounting.md#delinquency) and
[market closure](../protocol/markets.md#closure).

## Finite accounting representations

### Timestamp horizon

V2.x encodes absolute Unix timestamps in `uint32` across market accrual
checkpoints, withdrawal-batch expiries, hook deadlines, and lender credentials.
The final representable timestamp is `type(uint32).max`, or
2106-02-07 06:28:15 UTC. This is an accepted lifetime bound for the V2.x
generation, not a rollover scheme.

A new withdrawal batch can be created only while
`block.timestamp + withdrawalBatchDuration <= type(uint32).max`. For the
maximum supported 365-day duration, the final representable creation timestamp
is 2105-02-07 06:28:15 UTC; shorter batches reach the limit later. The checked
conversion deliberately reverts rather than wrapping into an old batch key.
During the final two weeks, applicable temporary APR-reduction deadlines wrap
into the past, so a follow-up update can release the temporary reserve early.
At the 2106 boundary, an accrual checkpoint can wrap and replay a century-scale
interval, credentials can no longer be refreshed, and no new withdrawal batch
can be created.

A successor deployment does not migrate immutable markets or lender balances.
Every V2.x market must be closed or migrated, with lender positions fully
exited, before the earliest applicable timestamp cutoff and with sufficient
operational margin to finish withdrawal execution. A market can require an
earlier retirement under the scale-factor bound below.

### Scale factor

`MarketState.scaleFactor` is a `uint112`. Checked casts revert rather than
truncate if the next compounded scale factor exceeds the representation. Since
ordinary market actions accrue first, a market at the ceiling cannot recover
through the usual close, rate-change, transfer, or withdrawal paths.

Under maximally frequent checkpoints, the theoretical shortest horizons are
about 7.7 years for a standard market at 100% APR plus a 100% delinquency rate,
and about 5.15 years for a fully drawn revolving market at a 100% commitment
rate, 100% APR, and 100% delinquency rate. At a 28% cumulative rate the horizon
exceeds 55 years; at typical 10-15% rates it exceeds 100 years. Markets must
close, reduce rates, or offer a migration well before the ceiling.

### Withdrawal batches

Batch totals, paid shares, and each account's queued amount are cumulative
`uint104` values for one expiry. Checked arithmetic reverts instead of wrapping.
At the minimum scale factor, saturation requires roughly `2.03e13` nominal
tokens for an 18-decimal asset or `2.03e25` for a 6-decimal asset, together with
repeated replacement of paid shares before the same expiry. Revisit the bound
before listing assets with higher decimals or unusually valuable atomic units.

See [scaling](../protocol/scaling-and-rounding.md#finite-scale-factor-representation),
[withdrawal representation limits](../protocol/withdrawals.md#representation-limits),
and [credential lifetime](../integrations/role-providers.md#credential-lifetime-and-failure).

## Withdrawal batches and rounding

All lenders entering one batch share its aggregate normalized payments pro rata
according to final scaled ownership. Because payments can reserve assets and
burn shares before later requests join, this averages payment vintages across
the batch: early-paid lenders can receive part of the interest attached to
later-paid shares, while later entrants can share interest already accrued by
earlier unpaid shares. This is intentional: creating the batch should not
penalize the first lender that benefits everyone else.

`nukeFromOrbit` uses the same accounting when it forces a sanctioned lender's
full direct balance into the current batch. The forced lender and existing
members receive the same averaged result as voluntary participants with the
same scaled amounts and entry timing; execution routes the sanctioned lender's
share to escrow. The caller controls when quarantine is attempted but receives
no special entitlement, and the batch conserves its aggregate reserved assets.

Each partial payment to a batch floors its normalized payment independently.
The discarded fraction is less than one atomic unit of the underlying per
payment and is not carried forward.

`closeMarket()` walks every unpaid withdrawal batch. Its gas cost is unbounded
in the queue length. Work down a large queue in bounded calls to
`repayAndProcessUnpaidWithdrawalBatches(0, maxBatches)` before closing.

## Protocol fees

Each accounting checkpoint rounds that interval's protocol fee independently
to the underlying atomic unit. Fractional remainders are not carried, so update
cadence can change the total protocol fee and can round short intervals to zero.
Lender balances are unaffected by the protocol-fee rounding itself.

The stated lender APR is linear inside each accrual interval and is applied to
the scale factor stored at that checkpoint. Splitting one wall-clock span across
more checkpoints therefore compounds lender interest. For example, at 10% APR,
one annual interval multiplies the scale factor by `1.10`, while two half-year
intervals multiply it by `1.05 * 1.05 = 1.1025`. Permissionless
`updateState()` calls and ordinary market actions create checkpoints; calls at
the same timestamp do not accrue twice. This is the intended interest model.

A market's fee recipient is immutable. Template fee-recipient changes apply to
new markets, while a fee-rate push changes only the rate of an existing market.
V2.5 rejects a positive fee-rate push to a market whose immutable recipient is
zero.

## Hooks

The selected hook address and enabled callback set are immutable. Mutable hook
state or administration can still make an enabled callback reject its market
action. A bad hook implementation can permanently disable the corresponding
path; a defect in a protocol-supplied hook template is still reportable.

Hooks are not an exact accounting event stream. Withdrawal-batch payments do
not have a dedicated callback, so consumers that need exact live batch or
account state must query the market and perform the corresponding accounting.

## ERC-4626 wrapper surplus

Direct transfers of market tokens to a wrapper increase its scaled backing but
do not mint wrapper shares. The current operational borrower may sweep only the
scaled backing above wrapper share supply. This surplus is not attributed to
existing wrapper shareholders. Other ERC-20 balances sent to the wrapper can be
swept in full, subject to the recipient sanctions check.

## Sanctions dependency

Sanctions-gated paths fail if the sentinel or its external list reverts or
returns malformed data. This is an accepted external liveness dependency. See
[security assumptions](./assumptions.md#sanctions-dependency) for the affected
paths and override boundary.

`nukeFromOrbit` intentionally uses the ordinary withdrawal hook. Fixed-term and
periodic-term restrictions can therefore defer quarantine until withdrawals
are permitted. In a periodic market, the delay can recur once per period.

## Assets

The protocol assumes listed assets have stable ERC-20 transfer and metadata
behavior. Fee-on-transfer, rebasing, callbacks, mutable or malformed metadata,
and unusual zero-value transfer behavior can break accounting, deployment,
lens reads, or fee paths. Listing review is the control; arbitrary deployability
does not establish compatibility.

## Reused singleton behavior

The V2.5 release plan reuses the deployed ArchController and sanctions
contracts. The following runtime limitations remain relevant:

- Malformed ArchController pagination ranges can panic after clamping. Callers
  must use half-open ranges satisfying `start <= min(end, count)`.
- Privileged ArchController registration accepts raw addresses without proving
  code or every expected relationship. Ceremony tooling and operators must
  validate code, interfaces, and factory relationships before registration.
- SphereX-protected registered contracts cache their engine. V2.5 factories
  source the engine assigned to new markets directly from the ArchController,
  but rotations must still keep the old engine operational and migrate
  registered contracts in bounded batches.

V2 bytecode also requires EIP-1153 transient storage. Deployment is restricted
to chains where every execution path supports `TSTORE` and `TLOAD`.

## Dormant borrower-account factory surface

The identity registry trusts an approved account factory to bind an account to
the principal it reports. That binding has no principal-side revocation path.
The current V2.5 deployment baseline does not include an account factory. Before
activating one, its registration flow must authenticate principal consent, bind
the intended account code, and handle replay and front-running. Treat approval
of such a factory as a new security boundary, not an ordinary configuration
change.

## Legacy deployments

These limitations apply to older deployed generations, not canonical new V2.5
markets:

- A pre-V2.5 market does not register its canonical ERC-4626 wrapper. Its
  borrower must retain a sanctions override for the pooled wrapper address.
- Hooks deployed before the CAF-04, CAF-05, CAF-10, and CAF-11 remediations
  retain their original entry/withdrawal combinations, push-credential timing,
  provider classification, and repeated-provider-query behavior.

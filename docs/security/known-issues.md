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

Manual closure returns only assets left after all lender debt, paid and unpaid
withdrawal liabilities, and protocol fees are accounted for. Automatic closure
retains that surplus for a separate borrower call to `rescueTokens(asset)`.
If the operational borrower or its recorded principal has since been flagged
by the sanctions oracle, manual closure and surplus recovery can still send
that unencumbered value to the operational borrower. The sanctions check on
`borrow` prevents either flagged identity from drawing lender-backed value;
closure and recovery are allowed to settle the market. A token's own recipient
restriction can make recovery fail, but automatic closure does not attempt that
transfer and therefore does not pass that failure on to lender actions.

## Lazy delinquency accounting

Market accounting advances on state writes. An elapsed interval uses the
previously stored delinquency flag, then the final state write records whether
the market is delinquent for the next interval. A threshold crossed between
transactions is therefore recognized at the next checkpoint, not at the exact
second of the crossing. Permissionless state updates and the Hydra keeper
reduce this timing difference but cannot remove block and polling latency.

Withdrawal expiry and repayment boundaries use historical asset checkpoints.
A delayed update settles them against the last asset balance the market
recorded at or before each boundary. A transfer first observed later becomes
current liquidity but cannot rewrite that history. Because an ERC-20 balance
does not retain transfer timestamps, a direct transfer intended to count at
expiry or at a repayment deadline must be followed by a market state write no
later than that timestamp.

`defaultedAt` is a permanent stored marker, not a live prediction. It can remain
zero after an uncured cutoff until a successful update records it. A healthy
write at the exact 90-day cutoff resets the separate penalty run; default is
sealed only at a later timestamp. The ordinary `timeDelinquent` decay and fee
calculation remain separate. A zero-day repayment period is valid and gives no
extra interval beyond the repayment-date timestamp. See
[repayment and default](../protocol/repayment-and-default.md).

Closing accrues through the close timestamp, then clears the delinquency timer.
Interest and delinquency fees do not continue through the remaining grace or
decay period after closure.

See [accounting](../protocol/accounting.md#delinquency) and
[market closure](../protocol/markets.md#closure).

## Finite accounting representations

### Timestamp horizon

V2.x encodes absolute Unix timestamps in `uint32` across market accrual
checkpoints, withdrawal-batch expiries, repayment terms, default records, hook
deadlines, and lender credentials.
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

Batch totals, paid shares, and each account's queued amount are declared as
cumulative `uint128` values for one expiry, but the active source caps valid
batch ownership at `type(uint104).max`. Payment burns live shares, so repeated
replacement before one expiry can reach that cap even when every individual
deposit fits and live supply remains below it.

At the initial scale factor, the cumulative cap represents roughly `2.03e13`
tokens for an 18-decimal asset or 20.28 tokens for a 30-decimal asset. If a
request would cross the cap, voluntary queues and `nukeFromOrbit` revert; the
balance remains live until a later batch opens. Existing batch claims remain
payable. Even at the maximum `uint112` scale factor, the cap keeps one batch's
cumulative normalized payments below `uint128.max`.

`normalizedUnclaimedWithdrawals` is a `uint128` total across batches. At extreme
factors, several uncollected batches can temporarily consume that capacity and
make a later payment revert. Older batches are already executable when a new
batch opens, and anyone can execute those claims to release the global capacity
before retrying payment. A failing or restricted underlying-token transfer can
delay that recovery under the unsupported-token behaviors below. Underlying
assets are not assumed to be Foundation-preapproved, so assess denominations
and expected amounts against the cumulative batch cap.

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

Earlier market sources floor every partial payment independently, losing less
than one atomic unit per payment. Arbitrary ERC20 admission has always been
possible; reconsidering this issue does not reflect a policy change.

This experimental branch carries the fraction between payments and includes it
in debt and reserve accounting. The smaller candidate fits the market bytecode
limit, but is not an approved release and still requires consumer migration.
It does not change the disposition of existing markets.
See [the implementation and tradeoffs](./withdrawal-rounding-experiment.md).
Final per-lender pro-rata division still leaves indivisible token dust.

`closeMarket()` walks every unpaid withdrawal batch. Its gas cost is unbounded
in the queue length. Work down a large queue in bounded calls to
`repayAndProcessUnpaidWithdrawalBatches(0, maxBatches)` before closing.

Automatic closure pays and releases the current batch but leaves older batches
for that bounded processor. Their funds remain protected after closure. The
repayment date itself leaves batching unchanged while the market is open.

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

Factory fee-update pages skip markets whose `isClosed()` view is true, including
pending automatic closure. That read does not itself commit closure. A failed
or malformed read, or a failed update to an open market, still reverts the whole
page.

Revolving markets also floor the utilization-weighted interest rate to ray
precision at each checkpoint. A fraction below one ray is discarded when the
timestamp advances. Its magnitude depends on supply, scale factor and update
cadence; a decimal range alone is not a universal economic bound. See the
[utilization-interest precision review](./revolving-interest-dust-review.md)
for quantified examples and the distinction from protocol-fee rounding.

## Hooks

The selected hook address and enabled callback set are immutable. Mutable hook
state or administration can still make an enabled callback reject its market
action. New V2.5 markets never dispatch execution hooks; dated repayment also
bypasses queue hooks and automatic-closure hooks. For other enabled paths, a
bad hook implementation can permanently disable the action. A defect in a
protocol-supplied hook template is still reportable.

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
are permitted. In a periodic market, the delay can recur once per period before
an enabled repayment date. From that date, queue-hook restrictions are skipped;
the nuke callback and remaining sanctions checks still apply.

## Assets

The protocol assumes listed assets have stable ERC-20 transfer and metadata
behavior. Fee-on-transfer, rebasing, callbacks, mutable or malformed metadata,
and unusual zero-value transfer behavior can break accounting, deployment,
lens reads, or fee paths. There is no built-in metadata allowlist, and creation
checks cannot establish that metadata will remain readable or stable. Arbitrary
deployability does not establish compatibility.

The current source accepts canonical empty names and symbols. Lens cosmetic
metadata reads are bounded and best effort: failure yields empty text rather
than aborting a market/token batch. Decimals and required accounting remain
strict. Long factory labels, failed or changing decimals, and client handling
of opaque text remain compatibility limitations. See the
[lens metadata contract](../integrations/lenses.md#token-labels-and-denominations)
and [metadata review](./token-metadata-review.md).

The current factories skip origination-fee transfers when the fee amount is
zero, while still requiring the supplied token and amount to match the template
and recording both in deployment events. Positive fees require a successful
transfer. Legacy factories retain the zero-transfer behavior. Optional
zero-amount draws, empty rescues and empty sanctions-escrow releases can still
fail on tokens rejecting zero transfers; this alone does not make positive
payments fail. See the [zero-transfer review](./zero-value-transfer-review.md).

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

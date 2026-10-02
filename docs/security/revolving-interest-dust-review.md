# Revolving utilization-interest precision review

Observed 2026-09-30 against
`0d93ead315fc1d1f27c069104dbdf0510369b5f8`. This review adds characterization
tests and documentation only; it changes no production code and does not adopt
the paused withdrawal experiments inherited by this source. Historical CAF-21
and WKI-028 dispositions remain historical evidence, not proofs for every asset.
No deployment or asset-price observation is claimed.

## What is lost

`WildcatMarketRevolving._calculateBaseInterest` calculates commitment interest
on the whole supply and utilization interest on the drawn portion. For an open
market with nonzero supply and positive elapsed time, the utilization component
is:

```text
R = 10^27; Y = 365 days; b = utilization APR in basis points
t = elapsed seconds; S = normalized supply; D = min(drawn principal, S)
A = floor(b * 10^23 * t / Y)
utilizationInterestRay = floor(A * D / S)
```

`A` is the same time-rate quantization used by standard markets. The additional
division by supply can discard a fraction of one **ray**, not a fraction of one
whole underlying token. The stored scale factor preserves rate precision down
to that quantum. If utilization interest is below one ray, its contribution is
zero and is forgotten when the accrual timestamp advances. Repeated checkpoints
can therefore lose more than one long interval.

This affects lender interest. Protocol fees derive from the resulting base rate
and may also lose a share of the discarded interest, before the separate fee
rounding assessed as item #3. Commitment interest is calculated independently;
a positive commitment fee does not recover the missing utilization fraction.

There is no revolving market implementation in source tags `v2.0.0` or
`v2.1.0`, so this additional utilization division is specific to the revolving
generation. The ordinary linear-rate quantization is shared with those tags.
This is a source comparison, not a claim about deployed generations.

## Exact threshold and ordinary-sized examples

For positive `A`, the minimum draw yielding a nonzero utilization rate is
`ceil(S / A)`. This is a minimum **draw**, not a minimum whole interest payment.
Positive sub-atom interest can survive in the stored scale factor even when a
token balance has not yet increased by one atomic unit.

The following initial-factor examples use 110 million tokens of supply and
one-bip APR (0.01%). Labels describe denominations; they are not fresh evidence
of a live market or Foundation admission policy.

| Decimals | Checkpoint interval | Minimum draw in atomic units | Minimum draw in tokens |
| --- | --- | --- | --- |
| 0 | 12 seconds | 1 | 1 |
| 6 | 12 seconds | 1 | 0.000001 |
| 18 | 12 seconds | 2,890,800,001 | 0.000000002890800001 |
| 18 | 1 second | 34,689,600,001 | 0.000000034689600001 |
| 18 | 1 day | 401,501 | 0.000000000000401501 |

Local contract tests using real factories, revolving markets and open/fixed
hooks reproduce the six-decimal nonzero rate for a one-atom draw at both
1,000-token and 110-million-token supply. The token and cached market decimals
are actually six in those fixtures.

For an 18-decimal 110-million-token market, a draw of 2,890,800,000 atoms lies
just below the 12-second threshold. One hundred 12-second checkpoints record no
utilization interest. One update over the same 1,200 seconds recognizes eleven
atoms, matching the exact linear interest on that fixed principal. Eleven atoms
are `0.000000000000000011` tokens. Adding one atomic unit to that draw reaches
the threshold: the 12-second update preserves one ray in the factor, even though the normalized
supply still rounds to its original whole-atom value.

Both checkpoint tests set commitment, protocol and delinquency rates to zero,
keep drawn principal constant and make no other balance changes. They isolate
the utilization rounding rather than comparing unrelated compounding paths.

## Bound and limitations of the old disposition

The utilization division discards less than one ray per interval. Let `Q` be
scaled supply and `F` the old scale factor. Before the later scale-factor
rounding, that discarded rate contributes less than:

```text
Q * F / R^2 underlying atomic units
```

At the initial factor `F = R`, this is exactly `S / R` atoms. For the
110-million-token example it is less than `1.1e-19` tokens per checkpoint,
regardless of denomination. If supply remains bounded by that amount, summing
only this utilization-division error over 365 days of 12-second intervals gives
less than `2.8908e-13` tokens. This is a bound on that rounding operation along
the actual state path; it excludes initial time-rate quantization, later
scale-factor/balance rounding and propagation through a different counterfactual
state path. Growing supply requires using the changing bound, not freezing it.

Consequently, frequent updates do not ordinarily discard meaningful lender
interest through this division at the expected 6- and 18-decimal market sizes.
The old blanket "no impact within a valid decimal range" wording is stronger
than the evidence: magnitude depends on supply, factor, update count and asset
value, not decimals alone. No Foundation allowlist guarantees those conditions.

A synthetic initial-factor arithmetic test at maximum `uint104` supply
discards 20,282 whole atomic units in one 12-second interval for a draw just
below the threshold. It is below the analytical bound and is not an assertion
of realistic volume or reachable deployed exposure. It demonstrates why a
universal one-atom bound or a denomination-only proof would be incorrect.

## Remediation choices

- **Retain with qualified bounds: recommended for the expected assets.** Record
  the precision limit rather than claiming an impossible zero-loss guarantee.
  Reassess a concrete asset's amounts and cadence if its economics fall outside
  these examples.
- **Round utilization up:** removes the zero-rate threshold for a positive draw,
  but systematically overcharges instead of undercharging by up to a ray.
  It does not preserve accumulated fractions and is not an accuracy fix.
- **Carry the fraction:** potentially improves accuracy, but the denominator
  `S` changes on accrual, deposits and withdrawals. A raw remainder modulo the
  old supply cannot simply be carried into the next division by a different
  supply. A complete design must define a consistent rate or debt unit, changing
  principal/rates, zero-supply periods and closure, and fit the market budget.
- **Increase precision or change the accrual representation:** a broader
  protocol/read-contract change. Reordering operations to quantize the final
  factor increment can reduce amplification at high factors, but cannot remove
  all finite precision or justify a blanket support claim without a new bound.

No arithmetic prototype or carry implementation is selected here. Retention is
a recommendation awaiting the user's disposition; item #3's acceptance is not
silently applied to this separate item.

## Verification

```sh
forge test --match-path test/market/WildcatMarket.t.sol --match-test 'test_revolvingAccrual' -vv
forge test --match-path test/market/RevolvingInterestDustReview.t.sol -vv
```

The existing four accrual tests cover combined rates/fees, delinquency, zero
time/supply, clamped utilization and previous dust thresholds. The new four
characterizations cover actual six-decimal smallest draws, repeated 18-decimal
checkpoint loss, retention at the exact threshold and the synthetic arithmetic
boundary. Contract characterizations cover both open-term and fixed-term hooks.
The boundary is a library arithmetic check, not a live-market fixture. All eight
tests passed with Solidity 0.8.25 and the unchanged Foundry profile; formatting
and diff checks passed. These checks characterize unchanged behavior; they do not prove remediation or
deployment identity. Production source is unchanged, so no full-suite rebuild,
consumer migration or new size measurement is required for this review.

# Protocol-fee rounding review

Status: characterization and design discussion; no production remediation.
Observed 2026-09-29 against source
`7b7db0e7517401da002239470a8aff3802e3c646`.
The fee calculation is unchanged from development base `7d79281`; the same
calculation is present at tags `v2.0.0` and `v2.1.0`. These are source
comparisons, not new deployment observations.

## What rounds

[FeeMath.applyProtocolFee](../../src/libraries/FeeMath.sol) rounds to nearest
at three stages: the protocol share of the base-interest rate, its application
to the scale factor, then the normalized fee on live scaled supply. The
fractional part is forgotten at every checkpoint.

This differs from withdrawal payment rounding, which floors each payment.
Protocol fees can be understated or overstated by repeated rounding. Final
token-unit rounding alone contributes at most half an atom per interval;
the earlier ray-rounding errors can be amplified by the factor and supply.

The exact reference for an interval, using the same stored factor and the same
integer base-interest rate as production, is:

```text
S = live scaled supply; F = old scale factor
I = calculated baseInterestRay; A = protocolFeeBips
unrounded fee = S * F * I * A / (RAY * RAY * BIP)
```

The reference sums those fractions across the actual checkpoint sequence
before rounding once. It does not compare daily compounding with one annual
interest calculation. More frequent interest compounding is intentional;
fee-rounding error is measured separately.

## Local contract results

APR/base rate is 10%; the protocol share is 10% of base interest. The balance
stays live for 365 daily checkpoints; no withdrawals occur. Revolving fixtures
use a 10% commitment rate and zero drawn-interest rate, giving the same base
rate without changing utilization. Amounts are underlying atomic units;
decimals do not enter this fee calculation.

| Initial scaled units | Fees recorded | Same-path unrounded sum | Sum rounded once |
| -------------------- | ------------: | ----------------------: | ---------------: |
| 1,000                |             0 |            10.515578... |               11 |
| 20,000               |           365 |           210.311563... |              210 |

Both results reproduce in standard/revolving markets with open/fixed hooks.
The latter 365 units are collectible through the real fee-collection function.
A no-fee control follows exactly the same lender scale-factor path. Repeating
an update at the same timestamp accrues nothing.

These can be economically relevant when one atom has meaningful value. For a
zero-decimal asset, the table amounts denote whole tokens. The tests do not
assert that these fixtures represent a deployed market or an approved asset.

The isolated library test also observes a 6,085-atom shortfall from the first
intermediate rounding at maximum uint104 supply, factor RAY, one-bip APR,
10% protocol share and a 12-second interval. This is a representation-boundary
case, not an assertion of realistic volume. It disproves a blanket half-atom
bound on the entire three-stage calculation.

[Contract tests](../../test/market/ProtocolFeeRoundingReview.t.sol):
`forge test --match-path test/market/ProtocolFeeRoundingReview.t.sol -vv`
passes all three tests. They characterize the existing rounding behavior;
passing does not mean the rounding issue is fixed. No full-suite rerun is
claimed because production source was unchanged.

## Carry options and constraints

A single fee carry per market can remove repeated whole-unit rounding. Fee
collection must preserve it; rate changes must not erase earned fractions.
Zero-rate periods, lifecycle boundaries and closure need an explicit policy.
A terminal discarded fraction must have a stated bound.

Unlike withdrawals, fee accrual does not burn lender shares and there is no
per-lender allocation or set of batch remainders. The whole fee returned by
accrual is already included in fees, debt and reserves. This makes the accounting
problem smaller; it does not make an unimplemented carry safe.

A carry of the final division alone needs fewer than 90 bits but retains the
earlier ray-rounding errors. Computing the fee from normalized live supply
first, then retaining the combined rate/application fraction, is another option:
its carry denominator is RAY\*BIP, needing 104 bits. That changes the fee basis
by the rounding of normalized supply and needs a separate accuracy bound.
An exact carry of the displayed full rational expression needs 193 bits and
full-precision arithmetic; it cannot be presented as the same cheap option.

The existing lifecycle slot contains only a uint32 default timestamp and uint40
penalty cutoff. A 96- or 104-bit carry could fit there without another slot
or extending the hook-facing MarketState tuple. The carry must participate
in the shared transition preview and commit path; simply storing it beside
the accrual helper would be incomplete. An exact 193-bit carry does not fit
in that slot's remaining 184 bits.

These are design options, not tested production patches. No bytecode size or
consumer compatibility claim is made for a carry. The current combined
withdrawal candidate has only 22 runtime bytes of revolving-market headroom,
so a fee fix requires an actual deployment-profile size measurement.

## Disposition

The former Foundation asset-admission assumption cannot justify ignoring this
for every asset. Reassess the economic tolerance explicitly. If remediation is
selected, a single-market carry is a plausible direction, with the precision
basis and terminal rounding policy chosen before implementation.
See [current fee limitations](./known-issues.md#protocol-fees).

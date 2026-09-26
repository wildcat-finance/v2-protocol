# E08: remove provably unreachable addition checks

Source parent: `16b3d4d`; canonical source E02 + E03 + E04.

Hypothesis: liability additions cannot overflow uint256 under MarketState's
field widths, so their checks can be removed without reducing the accepted
input range. Keep supply-minus-pending subtraction checked.

A broader first draft also specialized bounded normalization and reserve
multiplication. It passed 154 tests but grew creation code by 33/11 bytes at
runs 44; at E05 settings it grew standard by one byte and saved only 14 on
revolving. [Rejected broader patch](./patches/e08-bounded-normalization.patch).

The retained draft only puts three liability additions in unchecked blocks.
Normalization, multiplication, division and the pending-supply subtraction keep
their existing checked helpers and rounding. A uint104 supply at a uint112 scale
normalizes below 128 bits. A full uint16 reserve ratio keeps the collateral sum
below 132 bits; adding two uint128 liabilities is therefore safe in uint256.
This proof does not require reserveRatioBips to be at most 10,000.

| Settings          | Standard creation saved | Revolving creation saved |
| ----------------- | ----------------------: | -----------------------: |
| Canonical runs 44 |                      11 |                       15 |
| E05 runs 1/no F   |                      12 |                       16 |

Runtime saves the same amounts. Full ABIs and normalized layouts are unchanged.
[Measurements](./results/e08.json). Other measured targets are unchanged.

Validation: **154 tests passed on the retained draft**, including the existing
14 MarketState tests and three new differential tests against the prior checked
formulas. Fuzz inputs span the full field widths, including invalid pending
supply and reserve ratios above 10,000. Explicit maximum-field/zero-scale cases
match, and invalid pending supply keeps its arithmetic panic. Existing market,
repayment and revolving regressions also pass. Evidence: external
`e08-additions-behavior/`. The broader draft's test receipt is separate.

Decision: retain the small addition-only candidate. No generic arithmetic
utility or protocol field bounds were changed.

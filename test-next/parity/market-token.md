# Market token parity

Status: all shared standard/fixed-term ERC-20 market-token properties replaced.

## Family boundary

The legacy `WildcatMarketTokenTest` inherits 17 generic ERC-20 entries and declares three market
specific entries. `FixedTermWildcatMarketTokenTest` then recompiles the same 20 properties solely
to replace OpenTerm hooks with an already-matured FixedTerm instance. The replacement deploys both
hook kinds at runtime from one concrete suite, so the shared behavior is compiled once.

The market and hooks are production artifacts. Lightweight artifact-backed controller, registry,
sentinel, asset, and parameter-factory contracts provide only the constructor/call surfaces needed
by this behavior slice. The full factory/CREATE2 deployment path is already owned by
`hooks-factory-templates.md`; this fixture configures each production hook immediately after market
construction and before the first market call.

| Shared behavior slice                              | Legacy entries | Replacement entries |
| -------------------------------------------------- | -------------: | ------------------: |
| Metadata                                           |              2 |                   1 |
| Mint and burn accounting                           |              6 |                   1 |
| Exact approvals                                    |              4 |                   1 |
| Transfers, self-transfers, and supply preservation |              4 |                   1 |
| Finite/infinite `transferFrom` and self-transfer   |              6 |                   1 |
| Insufficient balance and allowance failures        |             12 |                   1 |
| Zero transfers and blocked recipients              |              6 |                   1 |
| **Total**                                          |         **40** |               **7** |

The fuzzed accounting property covers partial and full burns from one token through the maximum
`uint104` market supply. Transfer properties preserve ordinary and self-transfer branches, finite
allowance decrement, infinite allowance retention, total-supply identity, and exact sender and
recipient balances. Failure cases preserve the arithmetic panic for balance/allowance underflow
and the market errors for zero scaled transfers and blocked recipients.

The metadata property also checks the v2.5 version and `scaleAmountDown` rounding marker. The
legacy token helper minted the underlying twice and transferred the freshly deposited market
tokens to the same account; the replacement removes those fixture-only no-ops while asserting the
same observable supply and balance state. FixedTerm cases start with an end time equal to the test
timestamp rather than deploying a future term and reducing it immediately; term mutation itself
is already covered by `fixed-term-hooks.md`.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for
`WildcatMarketToken`. All seven properties pass at the fixed timestamp and seed. Five properties
run 1,000 fixed-seed cases, and every property executes both OpenTerm and FixedTerm variants.

| Market-token artifact                     | Initcode bytes | Runtime bytes | Test entries |
| ----------------------------------------- | -------------: | ------------: | -----------: |
| Legacy `WildcatMarketTokenTest`           |        175,187 |        54,891 |           20 |
| Legacy `FixedTermWildcatMarketTokenTest`  |        176,461 |        56,165 |           20 |
| **Legacy total**                          |    **351,648** |   **111,056** |       **40** |
| Replacement `WildcatMarketTest` (current) |         15,940 |        15,914 |            7 |
| **Difference**                            |   **-335,708** |   **-95,142** |      **-33** |
| **Reduction**                             |     **95.47%** |    **85.67%** |   **82.50%** |

The replacement artifact is intentionally named for the whole standard market family. Later base,
configuration, lifecycle, and withdrawal slices will add properties to this one concrete suite
instead of producing more inherited fixture artifacts.

# Market configuration parity

Status: all direct standard/fixed-term `WildcatMarketConfigTest` properties replaced.

## Family boundary

The legacy suite declares 44 properties, then `FixedTermWildcatMarketConfigTest` recompiles all 44
through inheritance. Ten declarations exercise `MarketConstraintHooks` state transitions and are
mapped separately in `market-constraint-hooks.md`. The remaining 34 declarations exercise the
market entrypoints and are replaced by 15 properties on `WildcatMarketTest`.

Production OpenTerm and FixedTerm hooks are exercised at runtime wherever the hook kind can change
the result. The pending-APR tests use one narrow `MarketConfigHooks` boundary because that behavior
requires a hook-controlled return value. The sanctions tests use the fixture sentinel only for its
sanction and escrow boundary; production sentinel and escrow behavior already has its own complete
replacement family.

| Shared behavior slice                                                     | Legacy entries | Replacement entries |
| ------------------------------------------------------------------------- | -------------: | ------------------: |
| Public configuration reads, deposit capacity, and interest above capacity |             10 |                   1 |
| Reserved borrower slot and authority                                      |              2 |                   1 |
| Sanctions queueing, escrow execution, empty/idempotent paths, and term    |             12 |                   3 |
| Capacity changes, authority, closure, and numeric bounds                  |              8 |                   2 |
| Shared APR constraints and temporary-reserve-ratio state                  |             20 |                   7 |
| Market APR application, authority, output bounds, closure, and liquidity  |             18 |                   3 |
| Permissionless pending-APR execution and rejection paths                  |             10 |                   2 |
| Factory protocol-fee updates and rejection paths                          |              8 |                   2 |
| Canonical wrapper registration and sanctions protection                   |              0 |                   1 |
| **Total**                                                                 |         **88** |              **22** |

The getter property fills a market, advances one year, and proves accrued interest cannot create
new deposit capacity above the configured maximum. Capacity updates cover values above and below
live supply, exact event data, unauthorized and closed-market calls, and the previously implicit
`uint128` overflow boundary. The borrower property also mutates the reserved storage slot directly
and proves authority follows that slot rather than fixture state.

The sanctions slice queues the lender's full scaled balance, checks the event and withdrawal
record, executes the matured batch into escrow, and verifies a second nuke is idempotent. Empty,
zero-address, unsanctioned, canonical-wrapper, and pre-maturity FixedTerm cases preserve the
important negative paths. Wrapper registration is added coverage: only the configured wrapper
factory can set it, and it can only be set once.

APR coverage is split at the actual contract boundary. `MarketConstraintHooksTest` owns the
formula, temporary reserve ratio, reduction/update/cancel/expiry transitions, and deployment
bounds. `WildcatMarketTest` proves the production hooks' output is applied end to end, rejects
unauthorized, closed, over-APR, and over-reserve results, and enforces both the old and proposed
liquidity ratios. Pending execution is permissionless, passes the intermediate state to the hook,
preserves the reserve ratio, and rejects disabled, closed, equal, increasing, and delinquent
states. Protocol-fee coverage includes the same-value no-op in addition to the legacy success and
revert cases.

## Coverage and canonical result

The fixed-seed legacy oracle passes all 88 concrete entries. The replacement passes all 22 mapped
properties: seven in `MarketConstraintHooksTest` and 15 configuration properties in
`WildcatMarketTest`. Focused accurate coverage reports 100% lines, statements, branches, and
functions for `WildcatMarketConfig` (78/78 lines, 86/86 statements, 19/19 branches, and 12/12
functions). `WildcatMarketToken` remains at 100% across all four measures.

The comparison below measures the whole legacy configuration family because its hook-state and
market-entrypoint properties share the same two large suite artifacts. The replacement row includes
the constraint suite, growth of the shared market artifact from the base checkpoint, the pending-APR
hook, and conservatively the entire sanctions-sentinel support artifact even though most of that
artifact already belonged to earlier slices.

| Configuration-family artifacts                    | Initcode bytes | Runtime bytes | Test entries |
| ------------------------------------------------- | -------------: | ------------: | -----------: |
| Legacy standard/fixed suites and pending-APR hook |        456,281 |       215,006 |           88 |
| Replacement properties and support                |         38,042 |        37,944 |           22 |
| **Difference**                                    |   **-418,239** |  **-177,062** |      **-66** |
| **Reduction**                                     |     **91.66%** |    **82.35%** |   **75.00%** |

Across the complete token, base, and configuration family, the legacy suite emits 1,256,315 bytes
of initcode and 533,854 bytes of runtime bytecode across 162 entries. The replacement emits
74,679/74,509 bytes across 36 entries, including all shared support above: a 94.06% initcode,
86.04% runtime, and 77.78% entry reduction.

The full replacement checkpoint is 535 tests across 35 suites with zero inherited entries,
648,619 bytes of test-side initcode, and 639,436 bytes of runtime bytecode. A forced canonical
compile-to-green took 1m48.26s, including 105.14s in solc, peaked at 2,966,276 KiB RSS, and
executed all tests in 1.83s.

# Market-to-hook dispatch parity

Status: complete.

## Family boundary

This family covers all 18 entries in `test/HooksIntegration.t.sol`. It is intentionally about
the market's generic callback plumbing: flag gating, caller identity, intermediate state, exact
callback calldata, trailing data, and return-value handling. Provider-specific and hook-specific
policy remains in those families.

One artifact-backed fixture deploys the production `WildcatMarket` with a small parameter-serving
factory and a recording hook. This keeps the real market code on every path without inheriting the
legacy full-protocol fixture.

| Behavior slice                          | Legacy entries | Replacement entries |
| --------------------------------------- | -------------: | ------------------: |
| `deposit` and `depositUpTo`             |              2 |                   1 |
| Three queue-withdrawal entrypoints      |              3 |                   1 |
| Nuke callback and nested queue callback |              2 |                   1 |
| Single and batched withdrawal execution |              2 |                   2 |
| `transfer` and `transferFrom`           |              2 |                   1 |
| Borrow                                  |              1 |                   1 |
| Repay and repay-plus-process            |              2 |                   1 |
| Close market                            |              1 |                   1 |
| Set maximum supply                      |              1 |                   1 |
| Set protocol fee                        |              1 |                   1 |
| Set APR and reserve ratio               |              1 |                   1 |
| **Total**                               |         **18** |              **12** |

Every replacement property covers both enabled and disabled callback paths and fuzzes arbitrary
trailing data. The assertions preserve the less-obvious ABI behavior as well:

- the nuke callback receives the caller's trailing data, while its nested queue callback receives
  empty data
- batched withdrawal execution sends empty trailing data to every callback
- transfer callbacks retain the external caller separately from `from`
- the APR callback's returned values control the values applied by the market
- callback state is checked at the exact intermediate point used by the production market

## Coverage comparison

Focused accurate-coverage runs passed all 18 legacy properties and all 12 replacement properties.
An LCOV hit-set comparison found no executable-line regression in any dispatch routine:

| `HooksConfig` dispatch routine | Legacy lines hit | Replacement lines hit |
| ------------------------------ | ---------------: | --------------------: |
| Deposit                        |            19/19 |                 19/19 |
| Queue withdrawal               |            20/20 |                 20/20 |
| Execute withdrawal             |            20/20 |                 20/20 |
| Transfer                       |            21/21 |                 21/21 |
| Borrow                         |            18/18 |                 18/18 |
| Repay                          |            18/18 |                 18/18 |
| Close market                   |            17/17 |                 17/17 |
| Set maximum supply             |            18/18 |                 18/18 |
| Set APR and reserve ratio      |            19/21 |                 19/21 |
| Set protocol fee               |            18/18 |                 18/18 |
| Nuke from orbit                |            18/18 |                 18/18 |

The hit sets, not only the totals, are identical. The legacy file also touches unrelated
`HooksConfig` construction helpers through its broad fixture; those lines remain assigned to the
hooks-configuration family rather than being counted as dispatch coverage.

## Canonical result

All 12 properties pass at the fixed timestamp and seed with 1,000 fuzz runs.

| Dedicated family artifacts |  Legacy | Replacement |    Delta | Reduction |
| -------------------------- | ------: | ----------: | -------: | --------: |
| Initcode bytes             | 200,778 |      29,892 | -170,886 |    85.11% |
| Runtime bytes              |  87,282 |      29,639 |  -57,643 |    66.04% |

The full replacement checkpoint is 446 tests across 30 suites with zero inherited entries,
466,686 bytes of test-side initcode, and 457,824 bytes of runtime bytecode. A forced canonical
compile-to-green took 87.21 seconds, including 84.92 seconds in solc, and peaked at 2,690,600 KiB
RSS.

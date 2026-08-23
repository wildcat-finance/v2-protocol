# Libraries and types parity

Status: first migration family complete.

## Property disposition

- All meaningful properties from the 10 legacy library suites and four type suites are retained.
- The legacy `LenderStatusTest` entry performed setup but made no assertion. It is retired and
  replaced by four direct properties for expiry, credential presence, setting, and clearing.
- Three truth-table properties add direct coverage for `BoolUtils`; the legacy suite had none.
- One property each adds the previously uncovered `MarketState.totalDebts` and memory-based
  `LibStoredInitCode` deployment paths.
- Three `HooksConfig` properties add flag/address utilities, exact hook-revert bubbling, and
  malformed APR-hook return data. The periodic APR callback flag is included in every structured
  config comparison.
- Artifact-backed helpers replace constructor-embedded fixtures. In particular, `FeeMathTest` no
  longer inherits and deploys the entire protocol fixture.

## Canonical-profile result

The replacement has 165 meaningful properties versus 154 legacy entries. The increase is from
closing the gaps above, not splitting existing cases into smaller tests.

| Measure                                                   |          Legacy libraries/types | Replacement family |              Delta |
| --------------------------------------------------------- | ------------------------------: | -----------------: | -----------------: |
| Runnable suites                                           |                              14 |                 15 |                 +1 |
| Test entries                                              |                             154 |                165 |                +11 |
| Parameterized entries                                     |                              91 |                101 |                +10 |
| Initcode, including replacement support artifacts         |                   314,141 bytes |      126,897 bytes | -187,244 (-59.61%) |
| Runtime bytecode, including replacement support artifacts |                   171,407 bytes |      124,018 bytes |  -47,389 (-27.65%) |
| Accurate line coverage                                    | current legacy coverage blocked |             99.32% |                n/a |
| Accurate statement coverage                               | current legacy coverage blocked |             99.25% |                n/a |
| Accurate branch coverage                                  | current legacy coverage blocked |             97.83% |                n/a |
| Accurate function coverage                                | current legacy coverage blocked |               100% |                n/a |

The replacement totals conservatively include the dedicated `HooksConfig` caller/targets and
shared PRNG artifact. The legacy column is the exact library/type artifact total from
`legacy-suite.json`; constructor-embedded fixture bytecode is already part of those test
contracts.

All 165 properties pass the fixed timestamp and seed at the canonical compiler settings. The
remaining uncovered lines are low-level malformed-token/deployment edges; every function in the
family is exercised.

# Sanctions parity

Status: sanctions detection, borrower overrides, deterministic escrow deployment, and escrow
release behavior are complete.

## Family boundary

This checkpoint covers all 24 entries in `SentinelTest` and `EscrowTest`. The two legacy files
deploy nearly identical fixtures and split one state machine across separate suites; the
replacement keeps that state machine in one concrete suite.

## Property disposition

Eleven focused properties replace the family. They use production Sentinel and Escrow contracts,
a minimal sanctions-list mock, and an artifact-loaded ERC-20.

| Legacy behavior group                                    | Entries | Replacement entries |
| -------------------------------------------------------- | ------: | ------------------: |
| Constructor dependencies, initcode hash, and temp state  |       3 |                   1 |
| Chainalysis response validation and revert bubbling      |       1 |                   1 |
| Sanction lookup and borrower override composition        |       2 |                   1 |
| Override add/remove state and events                     |       2 |                   1 |
| Deterministic escrow address                             |       2 |                   1 |
| Escrow creation, initialization, events, and idempotency |       2 |                   1 |
| Escrow immutables, asset, and live balance               |       6 |                   1 |
| Release availability from sanctions and overrides        |       2 |                   1 |
| Permissionless release and exact full-balance transfer   |       2 |                   1 |
| Release after borrower override                          |       1 |                   1 |
| Rejection while an active sanction remains               |       1 |                   1 |
| **Total**                                                |  **24** |              **11** |

The replacement retains both contract event surfaces, strict low-level Chainalysis return-data
validation, bubbled revert data, borrower-scoped overrides, exact CREATE2 derivation, the
Sentinel's temporary constructor handoff/reset, repeat-create behavior, permissionless release,
and sanctioned-account rejection. It strengthens the release path by asserting the account's
received balance and the escrow's complete balance drain, rather than checking only the latter.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for both
`WildcatSanctionsSentinel` and `WildcatSanctionsEscrow`. The run uses the temporary SphereX patch
through `scripts/test-next-coverage.sh` with `FOUNDRY_TEST=test-next/sanctions`; the script restored
the production source cleanly afterward.

| Measure                                                 | Legacy family | Replacement family |             Delta |
| ------------------------------------------------------- | ------------: | -----------------: | ----------------: |
| Runnable suites                                         |             2 |                  1 |                -1 |
| Test entries                                            |            24 |                 11 |               -13 |
| Parameterized entries                                   |             7 |                  4 |                -3 |
| Inherited entries                                       |             0 |                  0 |                 0 |
| Initcode, including dedicated support artifacts         |  43,206 bytes |       11,830 bytes | -31,376 (-72.62%) |
| Runtime bytecode, including dedicated support artifacts |  43,080 bytes |       11,779 bytes | -31,301 (-72.66%) |

All 11 properties pass at the fixed timestamp and seed with 1,000 fuzz runs. The complete
replacement checkpoint now has 393 tests across 26 suites, zero inherited entries, 376,781 bytes
of test-side initcode, and 369,366 bytes of runtime bytecode. A forced canonical AST
compile-to-green took 77.13 seconds, including 75.42 seconds in solc, and peaked at 2,412,868 KiB
RSS.

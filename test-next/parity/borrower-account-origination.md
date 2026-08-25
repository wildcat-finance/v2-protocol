# Borrower-account origination parity

Status: borrower-account origination through standard and revolving factories is complete.

## Family boundary

This checkpoint covers all 11 entries in `BorrowerAccountOriginationTest`. It is an integration
slice across the identity registry, both factory types, OpenTerm hooks, and both market types; it
does not claim complete factory, hook, or market behavior coverage.

## Property disposition

One nine-property suite replaces the family. Shared semantics run as a two-factory runtime matrix
instead of compiling separate standard and revolving test bodies. Production contracts and their
stored market/hook initcode are loaded from canonical artifacts.

| Legacy behavior group                                | Entries | Replacement entries |
| ---------------------------------------------------- | ------: | ------------------: |
| Deploy hooks, then market: standard and revolving    |       2 |                   1 |
| Deploy market and hooks together: both factories     |       2 |                   1 |
| Borrower account pays origination fees               |       1 |                   1 |
| Origination follows the registry's current principal |       1 |                   1 |
| Accounts under one principal share hooks             |       1 |                   1 |
| Accounts under one principal share deployment nonce  |       1 |                   1 |
| Removed principal can no longer originate            |       1 |                   1 |
| Existing identity survives account-factory removal   |       1 |                   1 |
| Account cannot use another principal's hooks         |       1 |                   1 |
| **Total**                                            |  **11** |               **9** |

The replacement retains exact operational borrower, resolved principal, hook administrator,
factory administrator indexes/nonces, market ownership checks, fee payer/recipient balances,
multi-account hook sharing, principal-transfer behavior, removed-factory continuity, and
cross-principal rejection. Each matrix property executes both production factory and market
implementations.

## Canonical result

Accurate non-IR coverage is not available for this integration graph. After applying the normal
temporary SphereX coverage patch, Solidity reports stack-too-deep in
`HooksFactoryRevolving.deployMarketAndHooks`; `--ir-minimum` then fails Yul stack allocation in
the same factory. No coverage-only source change is retained. Exact factory coverage remains a
cutover item for the dedicated factory migration rather than being inferred from an inaccurate
via-IR coverage report.

| Measure                                         | Legacy family | Replacement family |              Delta |
| ----------------------------------------------- | ------------: | -----------------: | -----------------: |
| Runnable suites                                 |             1 |                  1 |                  0 |
| Test entries                                    |            11 |                  9 |                 -2 |
| Parameterized entries                           |             0 |                  0 |                  0 |
| Inherited entries                               |             0 |                  0 |                  0 |
| Dedicated initcode, including support artifacts | 137,599 bytes |       13,177 bytes | -124,422 (-90.42%) |
| Dedicated runtime bytecode                      | 137,399 bytes |       13,151 bytes | -124,248 (-90.43%) |

The already-migrated borrower identity mocks are shared with this slice and are not charged a
second time. All nine properties pass at the fixed timestamp and seed. The complete replacement
checkpoint now has 377 tests across 24 suites, zero inherited entries, 357,324 bytes of test-side
initcode, and 349,986 bytes of runtime bytecode. A forced canonical AST compile-to-green took
75.62 seconds, including 74.01 seconds in solc, and peaked at 2,353,872 KiB RSS.

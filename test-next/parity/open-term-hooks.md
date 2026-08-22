# OpenTerm hooks parity

Status: all direct OpenTerm hook properties replaced; shared market-constraint state transitions
remain in their term-hooks slice.

## Family boundary

This checkpoint covers all 27 properties declared in `test/access/OpenTermHooks.t.sol`. The 70
shared `BaseAccessControls` properties inherited by the legacy concrete suite were already
replaced once in `access-controls.md`; they are not compiled into this suite again.

The replacement deploys the production `OpenTermHooks` artifact and real mock role providers from
a small test contract that supplies only the factory callback and borrower-registration surface.
It does not import the legacy fixture or deploy a market, ArchController, sanctions sentinel, or
hooks factory.

| Direct behavior slice                                      | Legacy entries | Replacement entries |
| ---------------------------------------------------------- | -------------: | ------------------: |
| Existing, new, mixed, and invalid provider initialization  |              5 |                   4 |
| Version, deployment config, and parameter constraints      |              3 |                   1 |
| Market creation, flag policy, overflow, and admin transfer |              9 |                   4 |
| Minimum-deposit administration                             |              4 |                   1 |
| Callback access paths and rejections                       |              6 |                   3 |
| **Direct-property total**                                  |         **27** |              **13** |
| Additional production-policy properties                    |              0 |                   2 |
| **Replacement total**                                      |         **27** |              **15** |

The callback properties preserve known-lender withdrawals after credential revocation,
hooks-data validation for unknown lenders, disabled-transfer rejection, all three unhooked-market
errors, exact access errors, and stored lender-status effects. The successful market matrix keeps
requested versus forced deposit/transfer flags distinct from the stored access policy, including
minimum-deposit auto-enablement and queue-withdrawal requirements.

The two added properties exercise behavior that the direct legacy file left to broad market
fixtures:

- deposit minimum, block, open-access, restricted-access, and first-known-lender behavior
- every unrestricted callback selector plus the OpenTerm-to-`MarketConstraintHooks` APR delegate

Batch market reads and both transfer-policy queries are also asserted directly.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for
`OpenTermHooks`. `MarketConstraintHooks` is intentionally partial here: this checkpoint proves the
OpenTerm delegate, while temporary-reserve-ratio state transitions belong to the shared
market-constraint slice.

All 15 properties pass at the fixed timestamp and seed, including 1,000 runs for each of the three
parameterized provider-construction matrices.

| Test artifact                   | Initcode bytes | Runtime bytes | Test entries |
| ------------------------------- | -------------: | ------------: | -----------: |
| Legacy `OpenTermHooksTest`      |        146,404 |       141,626 |           97 |
| Replacement `OpenTermHooksTest` |         26,593 |        26,567 |           15 |

The legacy artifact's 97 entries include the 70 shared inherited access-control properties, so
those byte counts are not presented as a standalone reduction. The completed fair access-family
comparison is recorded in `periodic-term-hooks.md`.

The full replacement checkpoint is 461 tests across 31 suites with zero inherited entries,
493,279 bytes of test-side initcode, and 484,391 bytes of runtime bytecode. A forced canonical
compile-to-green took 90.33 seconds, including 87.97 seconds in solc, and peaked at 2,770,084 KiB
RSS.

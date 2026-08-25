# Hooks administrator transfer parity

Status: hooks-instance administrator association and transfer behavior is complete across standard
and revolving factories.

## Family boundary

This checkpoint covers all five entries in `HooksAdministratorTransferTest`. It owns the
cross-contract association between `BaseAccessControls` and each factory; the complete hook and
factory state machines remain in their dedicated families.

## Property disposition

One five-property suite retains the legacy property count while running each property as a
two-factory runtime matrix. Production factories and OpenTerm hooks are loaded from canonical
artifacts rather than embedding both factory, hook, and market creation graphs in the suite.

| Legacy behavior group                                     | Entries | Replacement entries |
| --------------------------------------------------------- | ------: | ------------------: |
| Initial administrator indexes and compatibility aliases   |       1 |                   1 |
| Accepted transfer updates hooks and factory association   |       1 |                   1 |
| Transfer preserves swap-pop indexes                       |       1 |                   1 |
| Factory callback authenticates hook and pending transfer  |       1 |                   1 |
| Original administrator deployment nonce survives transfer |       1 |                   1 |
| **Total**                                                 |   **5** |               **5** |

The replacement retains both hook/factory transfer events, pending versus accepted state,
previous/new administrator enumeration, compatibility aliases, invalid direct/replayed callback
guards, first-slot and final-slot removal, and post-transfer nonce/address behavior for both
factory implementations.

## Canonical result

This graph shares the accurate-coverage compiler block documented for borrower-account
origination: non-IR compilation is stack-too-deep in `HooksFactoryRevolving`, while
`--ir-minimum` fails Yul stack allocation. No coverage-only source change is retained. Exact
callback coverage remains assigned to the dedicated factory migration; all canonical via-IR
properties are green.

| Measure                    | Legacy family | Replacement family |              Delta |
| -------------------------- | ------------: | -----------------: | -----------------: |
| Runnable suites            |             1 |                  1 |                  0 |
| Test entries               |             5 |                  5 |                  0 |
| Parameterized entries      |             0 |                  0 |                  0 |
| Inherited entries          |             0 |                  0 |                  0 |
| Dedicated initcode         | 124,577 bytes |        7,627 bytes | -116,950 (-93.88%) |
| Dedicated runtime bytecode | 124,536 bytes |        7,601 bytes | -116,935 (-93.90%) |

All five properties pass at the fixed timestamp and seed. The complete replacement checkpoint
now has 382 tests across 25 suites, zero inherited entries, 364,951 bytes of test-side initcode,
and 357,587 bytes of runtime bytecode. A forced canonical AST compile-to-green took 75.79 seconds,
including 74.16 seconds in solc, and peaked at 2,378,532 KiB RSS.

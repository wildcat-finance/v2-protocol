# WildcatArchController parity

Status: direct registry behavior and registered-contract SphereX propagation are complete.

## Family boundary

This checkpoint covers 47 legacy entries:

- 41 `WildcatArchControllerTest` entries
- 6 `WildcatArchControllerIntegrationTest` entries

The direct suite repeated the same registration, removal, membership, enumeration, and
pagination behavior across controller factories, controllers, markets, borrowers, and the asset
blacklist. The integration suite inherited the full market fixture to exercise one
ArchController dispatch function.

## Property disposition

One 12-property suite replaces the family. Registry behavior runs as a five-kind runtime matrix;
SphereX propagation uses lightweight registered targets and an `ISphereXEngine` implementation.

| Legacy behavior group                                      | Entries | Replacement entries |
| ---------------------------------------------------------- | ------: | ------------------: |
| Registration events, caller authorization, duplicate guard |      15 |                   3 |
| Removal events, missing-entry guard, owner authorization   |      15 |                   3 |
| Membership, enumeration, pagination, count, and swap-pop   |      10 |                   1 |
| SphereX propagation and null-engine behavior               |       2 |                   2 |
| Missing factory, controller, and market rejection          |       3 |                   1 |
| SphereX operator/admin authorization                       |       1 |                   1 |
| Registered-contract revert bubbling                        |       1 |                   1 |
| **Total**                                                  |  **47** |              **12** |

Every matrix entry exercises all five registries with fresh ArchController state. The
enumeration property preserves insertion order, end clamping, partial pages, exact counts, and
swap-pop behavior after removing the first of two entries. Both the owner/admin and configured
SphereX operator paths execute the propagation method.

The SphereX targets are deliberately small. They retain the behavior owned by the
ArchController: registry validation, `changeSphereXEngine` dispatch, engine allowlisting, event
order, null-engine handling, authorization, and revert bubbling. Target-specific engine update
behavior remains with the hooks factory, hooks, and market families instead of pulling the full
protocol fixture into this suite.

The commented CAF-13 pagination-remediation cases and CAF-16 registered-target validation cases
were not runnable legacy entries. They remain omitted here so the replacement matches the
deployed singleton's current semantics rather than asserting an undeployable remediation.

## Coverage and canonical result

`WildcatArchController` has 100% line, statement, branch, and function coverage in this focused
slice.

| Measure                                                 | Legacy family | Replacement family |              Delta |
| ------------------------------------------------------- | ------------: | -----------------: | -----------------: |
| Runnable suites                                         |             2 |                  1 |                 -1 |
| Test entries                                            |            47 |                 12 |                -35 |
| Parameterized entries                                   |             3 |                  1 |                 -2 |
| Inherited entries                                       |             0 |                  0 |                  0 |
| Initcode, including dedicated support artifacts         | 195,663 bytes |       15,393 bytes | -180,270 (-92.13%) |
| Runtime bytecode, including dedicated support artifacts |  75,304 bytes |       15,222 bytes |  -60,082 (-79.79%) |

All 12 properties pass at the fixed timestamp and seed with 1,000 runs for the parameterized
authorization property. The complete replacement checkpoint now has 320 tests across 21 suites,
zero inherited entries, 290,941 bytes of test-side initcode, and 284,697 bytes of runtime
bytecode. A forced canonical AST compile-to-green took 68.10 seconds, including 66.58 seconds in
solc, and peaked at 2,088,680 KiB RSS.

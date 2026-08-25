# MockArchControllerOwner parity

Status: executor administration, testnet onboarding, owner actions, legacy fee configuration, and
SphereX handoff behavior are complete.

## Family boundary

This checkpoint covers all 17 entries in `MockArchControllerOwnerTest`. It tests the ceremony
helper in `script/mock/MockArchControllerOwner.sol`; it does not broaden that helper into a
production protocol surface.

## Property disposition

One 16-property suite replaces the family. The production ArchController and helper are loaded
from canonical artifacts. Small bound-target, legacy-factory, and access-controlled SphereX
engine artifacts keep the real cross-contract authorization paths without embedding their
creation code in the concrete suite.

| Legacy behavior group                                   | Entries | Replacement entries |
| ------------------------------------------------------- | ------: | ------------------: |
| Constructor state and invalid executor/controller data  |       2 |                   2 |
| Executor authorization, validation, and final guard     |       3 |                   3 |
| Permissionless single/batch testnet borrower onboarding |       2 |                   1 |
| Returning ArchController ownership                      |       1 |                   1 |
| Generic owner action, return data, events, and errors   |       5 |                   5 |
| Legacy protocol-fee configuration                       |       1 |                   1 |
| ArchController SphereX admin/operator handoff           |       1 |                   1 |
| SphereX engine default-admin/role handoff               |       1 |                   1 |
| Concurrent old/new executor operation                   |       1 |                   1 |
| **Total**                                               |  **17** |              **16** |

The replacement retains exact helper events and revert data, the authorized-account list's
swap-pop behavior, recovery ownership, permissionless testnet onboarding, direct ArchController
actions, bound protocol targets, the legacy V2 fee call, and both sides of the staged SphereX
handoff. It additionally checks removal of the final list slot and malformed/reverting
`archController()` responses from otherwise valid contract targets.

## Coverage and canonical result

The helper reports 100% line and function coverage, 98.78% statement coverage, and 94.12% branch
coverage. Forge does not credit the `onlyAuthorized` modifier's revert statement/branch even
though multiple properties assert its exact `NotAuthorized` selector through `authorizeAccount`,
`executeProtocolAction`, and `setProtocolFeeConfiguration`. All other helper statements and
branches are covered.

| Measure                                                 | Legacy family | Replacement family |             Delta |
| ------------------------------------------------------- | ------------: | -----------------: | ----------------: |
| Runnable suites                                         |             1 |                  1 |                 0 |
| Test entries                                            |            17 |                 16 |                -1 |
| Parameterized entries                                   |             0 |                  0 |                 0 |
| Inherited entries                                       |             0 |                  0 |                 0 |
| Initcode, including dedicated support artifacts         |  47,776 bytes |       26,321 bytes | -21,455 (-44.91%) |
| Runtime bytecode, including dedicated support artifacts |  46,879 bytes |       25,437 bytes | -21,442 (-45.74%) |

All 16 properties pass at the fixed timestamp and seed. The complete replacement checkpoint now
has 368 tests across 23 suites, zero inherited entries, 344,147 bytes of test-side initcode, and
336,835 bytes of runtime bytecode. A forced canonical AST compile-to-green took 73.69 seconds,
including 72.07 seconds in solc, and peaked at 2,300,612 KiB RSS.

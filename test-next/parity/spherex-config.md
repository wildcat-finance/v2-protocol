# SphereX configuration parity

Status: standalone SphereX administration and the legacy registered-contract configuration cases
are complete.

## Family boundary

This checkpoint covers all 14 entries in `SphereXConfigTest`. It owns the standalone
`SphereXConfig` state machine plus the registered base's controller-only engine update and
engine-disabled guard behavior. Active engine pre/post validation remains part of the protected
factory, hook, market, and wrapper slices.

## Property disposition

Thirteen focused properties replace the family. Small artifact-loaded config, engine, and
registered-contract harnesses keep the compile graph isolated.

| Legacy behavior group                                        | Entries | Replacement entries |
| ------------------------------------------------------------ | ------: | ------------------: |
| Initial config storage, previously only implicit             |       0 |                   1 |
| Two-step admin transfer and authorization                    |       4 |                   3 |
| Operator update, event, and admin authorization              |       2 |                   1 |
| Engine disable/update/interface validation and authorization |       4 |                   3 |
| Allowed-sender propagation and disabled-engine behavior      |       2 |                   3 |
| Registered operator update and disabled guard                |       2 |                   2 |
| **Total**                                                    |  **14** |              **13** |

The replacement retains the exact role-transition and engine events, pending-admin reset,
operator-only engine changes, zero-engine disable path, interface validation, allowed-sender
events on both contracts, and the registered base's controller authority. It strengthens the
legacy suite by checking initial constructor state, both admin and operator access to
`_addAllowedSenderOnChain`, the missing unauthorized-sender rejection, post-revert state, and
authority after an accepted admin transfer.

## Coverage and canonical result

Focused accurate coverage reports 100% lines, statements, branches, and functions for
`SphereXConfig`. The registered base reports 41.67% lines, 33.73% statements, 60% branches, and
94.12% functions because this family intentionally covers only its configuration and disabled
guard paths; active engine communication belongs to later protected-contract slices.

| Measure                                                 | Legacy family | Replacement family |            Delta |
| ------------------------------------------------------- | ------------: | -----------------: | ---------------: |
| Runnable suites                                         |             1 |                  1 |                0 |
| Test entries                                            |            14 |                 13 |               -1 |
| Parameterized entries                                   |            10 |                  0 |              -10 |
| Inherited entries                                       |             0 |                  0 |                0 |
| Initcode, including dedicated support artifacts         |  19,288 bytes |       13,580 bytes | -5,708 (-29.59%) |
| Runtime bytecode, including dedicated support artifacts |  17,619 bytes |       12,473 bytes | -5,146 (-29.21%) |

All 13 properties pass at the fixed timestamp and seed. The complete replacement checkpoint now
has 409 tests across 28 suites, zero inherited entries, 393,396 bytes of test-side initcode, and
384,822 bytes of runtime bytecode. A forced canonical AST compile-to-green took 78.74 seconds,
including 77.02 seconds in solc, and peaked at 2,461,044 KiB RSS.

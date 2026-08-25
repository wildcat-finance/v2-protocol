# ReentrancyGuard parity

Status: state-changing and view reentrancy protection is complete.

## Family boundary

This checkpoint covers all three entries in `ReentrancyGuardView` and its `Reentrant` harness. It
tests the shared transient-storage guard directly; protected factory, market, and wrapper entry
points retain their domain-specific assertions in their own families.

## Property disposition

The replacement keeps three focused properties and uses a small artifact-loaded harness.

| Legacy behavior group                                   | Entries | Replacement entries |
| ------------------------------------------------------- | ------: | ------------------: |
| Ordinary guarded state changes and guarded view reads   |       1 |                   1 |
| State-changing reentrancy rejection                     |       1 |                   1 |
| View reentrancy rejection during a guarded state change |       1 |                   1 |
| **Total**                                               |   **3** |               **3** |

The replacement retains sequential stateful/view behavior and the exact `NoReentrantCalls`
selector. It strengthens both rejection cases by proving the failed nested call leaves state
unchanged and the guard remains usable afterward in the same test transaction.

## Coverage and canonical result

Focused accurate coverage reports 100% branch and function coverage. Forge reports 94.12% lines
and 90.91% statements because it does not credit the modifier's `_clearReentrancyGuard()` source
line, even though it reports `_clearReentrancyGuard` itself as executed four times and the tests
prove repeated guarded calls work in one transaction.

| Measure                                                 | Legacy family | Replacement family |            Delta |
| ------------------------------------------------------- | ------------: | -----------------: | ---------------: |
| Runnable suites                                         |             1 |                  1 |                0 |
| Test entries                                            |             3 |                  3 |                0 |
| Parameterized entries                                   |             0 |                  0 |                0 |
| Inherited entries                                       |             0 |                  0 |                0 |
| Initcode, including dedicated support artifacts         |   5,987 bytes |        3,035 bytes | -2,952 (-49.31%) |
| Runtime bytecode, including dedicated support artifacts |   5,248 bytes |        2,983 bytes | -2,265 (-43.16%) |

All three properties pass at the fixed timestamp and seed. The complete replacement checkpoint
now has 396 tests across 27 suites, zero inherited entries, 379,816 bytes of test-side initcode,
and 372,349 bytes of runtime bytecode. A forced canonical AST compile-to-green took 77.74
seconds, including 76.02 seconds in solc, and peaked at 2,423,068 KiB RSS.

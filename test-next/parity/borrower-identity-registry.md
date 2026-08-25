# Borrower identity registry parity

Status: constructor, factory administration, identity registration, principal transfer,
resolution, and pagination behavior are complete.

## Family boundary

This checkpoint covers all 43 entries in `WildcatBorrowerIdentityRegistryTest`. The separate
borrower-account origination and compatibility suites remain assigned to their integration
family.

## Property disposition

One 32-property suite replaces the direct registry family. It uses the production
`WildcatArchController` and `WildcatBorrowerIdentityRegistry`, plus small account and account
factory identities loaded from canonical artifacts.

| Legacy behavior group                                  | Entries | Replacement entries |
| ------------------------------------------------------ | ------: | ------------------: |
| Construction and low-level ArchController ABI reads    |       4 |                   4 |
| Account-factory administration, lifecycle, and paging  |       9 |                   7 |
| Borrower-account registration and ambiguity guards     |      10 |                   7 |
| Principal-transfer request and target validation       |       6 |                   5 |
| Principal-transfer cancellation                        |       2 |                   2 |
| Transfer acceptance, revalidation, and index movement  |       7 |                   4 |
| Direct/account resolution and stale-identity rejection |       4 |                   2 |
| Principal and factory account pagination               |       1 |                   1 |
| **Total**                                              |  **43** |              **32** |

The replacement retains exact events, caller checks, duplicate and invalid-address guards,
factory removal semantics, original factory provenance, current-principal enumeration,
append-only factory enumeration, pending-transfer replacement/cancellation, acceptance after
factory or old-principal removal, target revalidation, and all slice boundary behavior.

The suite also adds a reachable nested-principal case that was absent from the legacy tests. A
registered principal can first receive an account, later be removed as a direct borrower, and
then become an account of another principal. Resolving the original account correctly rejects
that now-ambiguous identity.

The low-level `owner()` and `isRegisteredBorrower(address)` reads retain short-return, dirty-word,
revert-bubbling, and trailing-data cases. These directly cover the assembly response validation
rather than relying on ordinary Solidity ABI decoding.

## Coverage and canonical result

`WildcatBorrowerIdentityRegistry` has 100% line, statement, branch, and function coverage in this
focused slice.

| Measure                                                 | Legacy family | Replacement family |             Delta |
| ------------------------------------------------------- | ------------: | -----------------: | ----------------: |
| Runnable suites                                         |             1 |                  1 |                 0 |
| Test entries                                            |            43 |                 32 |               -11 |
| Parameterized entries                                   |             1 |                  1 |                 0 |
| Inherited entries                                       |             0 |                  0 |                 0 |
| Initcode, including dedicated support artifacts         |  49,053 bytes |       26,885 bytes | -22,168 (-45.19%) |
| Runtime bytecode, including dedicated support artifacts |  48,848 bytes |       26,701 bytes | -22,147 (-45.34%) |

All 32 properties pass at the fixed timestamp and seed with 1,000 runs for the duplicate-account
property. The complete replacement checkpoint now has 352 tests across 22 suites, zero inherited
entries, 317,826 bytes of test-side initcode, and 311,398 bytes of runtime bytecode. A forced
canonical AST compile-to-green took 71.50 seconds, including 69.92 seconds in solc, and peaked at
2,168,304 KiB RSS.

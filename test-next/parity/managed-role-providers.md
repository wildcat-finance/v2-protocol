# Managed role-provider parity

Status: complete for AccessList and Merkle provider behavior; generic market-to-hook and
FixedTerm hook dispatch remain in their later feature slices.

## Family boundary

This checkpoint covers 44 legacy entries:

- 17 `AccessListRoleProviderTest` entries
- 6 `AccessListRoleProviderIntegrationTest` entries
- 21 `MerkleRoleProviderTest` entries

The seven `AccessListRoleProviderFactoryTest` entries are not counted again. They were already
replaced by the six-factory runtime matrix documented in `role-provider-factories.md`.

## Property disposition

One 24-property suite replaces the provider-specific behavior. Shared two-step administration is
exercised as an AccessList/Merkle runtime matrix; provider-specific list, root, proof, and hook
behavior stays explicit.

| Legacy behavior group                   | Entries | Replacement disposition                                                                                    |
| --------------------------------------- | ------: | ---------------------------------------------------------------------------------------------------------- |
| Managed administration across providers |       7 | Four two-provider properties cover invalid administrators, replace/cancel, invalid transitions, and accept |
| AccessList membership and credentials   |      12 | Seven focused properties cover construction, isolation, mutation, atomic batches, errors, auth, and paging |
| AccessList hook/factory integration     |       6 | Two real-hook properties plus the already-complete hook-constructor/factory matrix                         |
| Merkle root, proof, and parser behavior |       9 | Six focused properties, including generated-proof and malformed-data fuzzing                               |
| Merkle hook/market behavior             |      10 | Five real-hook properties cover admission, TTLs, malformed data, empty proofs, and root changes            |

The generated-proof property combines the legacy valid-account and different-account fuzz
entries without narrowing the proof space. The malformed parser cases retain short data, wrong
and oversized offsets, noncanonical empty proofs, trailing data, oversized lengths, and arbitrary
bytes. Empty proofs remain valid only for the matching single-leaf root.

The integration properties deploy production providers and production `OpenTermHooks`, register
a lightweight market identity through `onCreateMarket`, and invoke `onDeposit` or
`onQueueWithdrawal` as that market. They preserve provider detection, pull/push placement,
credential writes, zero/positive TTL behavior, hook-local blocking, packed proof forwarding,
attachment stability, and `NotApprovedLender` behavior.

The legacy AccessList integration repeated the same base access behavior through mock OpenTerm and
FixedTerm hooks. The shared behavior is already covered once in `BaseAccessControlsTest`; the
production OpenTerm path is covered here, and production FixedTerm dispatch remains mapped to the
FixedTerm hook slice. Likewise, the generic `WildcatMarket.depositUpTo -> onDeposit` call path will
be covered once in the market/access-hook slice rather than once per provider.

## Coverage and canonical result

| Production contract    |  Lines | Statements | Branches | Functions |
| ---------------------- | -----: | ---------: | -------: | --------: |
| ManagedRoleProvider    |   100% |       100% |     100% |      100% |
| AccessListRoleProvider |   100% |       100% |     100% |      100% |
| MerkleRoleProvider     | 96.00% |     96.77% |     100% |      100% |

Forge does not mark one constant-return source line in `MerkleRoleProvider` even though the suite
executes and asserts both `getCredential == 0` and failed proof validation. That single line is the
entire reported gap.

All 24 properties pass at the fixed timestamp and seed with 1,000 runs per fuzz entry. The new
suite emits 25,660 bytes of initcode and 25,634 bytes of runtime bytecode. The three comparable
legacy suites emit 267,476 bytes of initcode and 147,100 bytes of runtime bytecode. This is a
90.41% initcode reduction and an 82.57% runtime-bytecode reduction; the shared factory matrix is
not charged to this family a second time.

The complete replacement checkpoint now has 308 tests across 20 suites, zero inherited entries,
and 275,548 bytes of test-side initcode. A forced canonical AST compile-to-green took 66.66
seconds, including 65.16 seconds in solc, and peaked at 2,036,800 KiB RSS.

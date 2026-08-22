# Test Suite Inventory and Restructuring Baseline

Status: baseline captured; parallel replacement underway under `test-next/`.

## Survey boundary

This inventory is anchored to commit `215f441` (`chore(v2.5): finalize gas review and refresh
deploy ceremony`). The tracked test tree has not changed since that snapshot.

The inventory deliberately excludes the audit-generated Fizz harness and its supporting files:

- `test/fizz/` (22 untracked Solidity files at survey time)
- `PROPERTIES.md`
- `echidna.yaml`
- `medusa.json`
- `fizz_data/`
- the experimental fast-test scripts, profiles, and patch files

The deploy UI is also separate: its seven Vitest files and one fork helper do not contribute to
the Solidity compile described here.

## Current Foundry suite

| Area                           | Suites | Tests / invariants |
| ------------------------------ | -----: | -----------------: |
| Market                         |     12 |                467 |
| Access hooks                   |      3 |                371 |
| Root / admin / factories       |     14 |                258 |
| Role providers                 |     21 |                186 |
| Vault / wrapper                |      6 |                176 |
| Libraries                      |     10 |                122 |
| Integration matrix / scenarios |     18 |                 87 |
| Lens                           |      2 |                 74 |
| Types                          |      4 |                 32 |
| SphereX                        |      1 |                 14 |
| Dedicated invariants           |      3 |                 10 |
| **Total**                      | **94** |          **1,797** |

Underlying source shape:

- 117 tracked Solidity files under `test/`
- 39,445 lines of tracked test-side Solidity
- 75 files containing runnable suites
- 94 runnable test contracts
- 1,766 conventional test entries
- 31 invariant entries across 10 concrete invariant contracts
- 389 parameterized fuzz tests, although only 44 are named `testFuzz*`
- default runs: 1,000 per fuzz test and 2,000 per invariant at depth 30

The 31 invariants are:

- 3 generic ERC-20 invariants
- 18 hook x market matrix invariants
- 8 CAF12 accounting / revolving invariants
- 2 withdrawal-batch identity invariants

## Where the time goes

The recorded clean validation passed all 1,797 tests across 94 suites. It took 20m37s:

- 1,197 seconds compiling
- about 40 seconds executing the entire suite
- about 23.7 GB peak RSS in the recorded canonical validation; a separate monolithic profiling
  run reached roughly 31 GB

The canonical compile input was approximately:

- 108 production sources
- 117 test sources
- 29 Solidity scripts
- 71 reachable library sources
- 325 source units in one compiler job

Reducing fuzz or invariant run counts therefore does not materially improve the cold-build
problem. Compilation accounts for roughly 97% of the recorded wall time.

## Developer-only fast-compile experiment

A disposable-checkout experiment at `6c2cbfb9e951976bd27a6ab67f594c35f85f55a5`, using the
official Solidity 0.8.25 compiler, produced these results:

| Configuration                          | Cold compile |
| -------------------------------------- | -----------: |
| Canonical protocol `src/` only         |        36.1s |
| Cheap-IR, monolithic tests             |       13m58s |
| Canonical tests, 8 shards              |       13m12s |
| Cheap-IR tests, 8 longest-first shards |        5m29s |
| Warm execution of all shards           |        56.8s |

The cheap-IR profile still uses via-IR. It runs a reduced Solidity optimizer sequence once
instead of repeating the canonical fixed-point cycle. Its artifacts are deliberately
noncanonical and must not be used for gas, size, CREATE2 addresses, deployment, verification,
or exact-bytecode checks.

Each shard uses one `.t.sol` root, an empty `FOUNDRY_SRC` discovery directory, and independent
cache/output directories. That limits each compiler process to the root's reachable import
graph and lets eight solc processes use separate cores. Canonical sharding was also checked
against the monolithic canonical `src` build: 3,051 fully qualified protocol artifacts had no
creation-bytecode, runtime-bytecode, metadata, or raw-metadata mismatches. Source-map IDs can
differ between compilation units.

The reported fast run was not yet a complete parity run. It executed 90 suites and 1,769 tests
because the disposable runner selected only `*.t.sol` roots. It omitted the four runnable legacy
`.sol` files, which account for the exact missing 4 suites and 28 entries:

| Omitted file              | Entries |
| ------------------------- | ------: |
| `test/EscrowTest.sol`     |      12 |
| `test/InvariantTests.sol` |       3 |
| `test/LogTest.sol`        |       1 |
| `test/SentinelTest.sol`   |      12 |

Before this becomes tracked tooling, the runner must cover all 94 suites / 1,797 entries and
isolate or disable the shared metrics files written by parallel invariant handlers. The local
fast-profile, runner, and patch files remain untracked experiments.

Sharding and the cheap-IR profile are separate choices:

| Lane                               | What it proves                                                                                                | What it does not prove                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Cheap-IR shards                    | Fast behavioral feedback from the selected tests                                                              | Canonical bytecode, gas, size, CREATE2 addresses, deployment, or verification |
| Canonical-profile shards           | Test behavior under canonical compiler settings; the measured protocol artifacts matched the monolithic build | One unified artifact/build-info tree or stable source-map IDs                 |
| Canonical release/deployment build | Authoritative unified protocol artifacts                                                                      | Test-suite behavior by itself                                                 |
| Canonical monolithic tests         | Current highest-confidence behavioral reference                                                               | A tolerable inner development loop                                            |

The cheap-IR sharder is therefore optional developer scaffolding, not the test-suite redesign,
an audit interface, or a release gate. Auditors and external contributors should not need a
one-off runner or noncanonical optimizer profile. Canonical release artifacts should continue to
come from the existing release/deployment build.

Test contracts dominate code generation:

- 239 test-side artifacts with bytecode
- about 12.5 MB of test creation bytecode
- about 317 KB of production creation bytecode
- test artifacts account for roughly 95% of emitted creation bytecode

The largest test compile families are:

| Family             | Approximate creation bytecode |
| ------------------ | ----------------------------: |
| Integration suites |                        4.0 MB |
| Market suites      |                        2.5 MB |
| Provider suites    |                       1.86 MB |

Together, those three families account for about 67% of test creation bytecode.

## Structural expansion

There are 455 inherited test entries whose repetition is mostly intentional but expensive to
compile and optimize:

- 70 base access-control tests instantiated across three hook types: 210 entries
- five complete market suites rerun under fixed-term hooks: 204 entries
- inherited base ERC-20 suite: 17 entries
- inherited vendored ERC-4626 suite: 24 entries

Notable examples:

- `test/market/FixedTermEquivalenceTests.t.sol` is only 69 source lines but emits about 1.09 MB
  of creation bytecode.
- The six concrete contracts in `test/integration/MatrixInvariant.t.sol` emit about 1.31 MB.
- The two Lens suites emit about 668 KB.

`test/shared/Test.sol` is the other major seam. Its constructor deploys the controller, borrower
identity registry, factories, wrapper factory, hooks, sentinel, role providers, and embedded
market initcode. Every derived test contract inherits that deployment machinery whether it
needs all of it or not.

Four concrete fixture contracts have no runnable tests but still receive standalone code
generation:

- `MarketConfigMatrix`
- `BaseMarketTest`
- `ExpectedStateTracker`
- `Test`

Together they emit roughly 620 KB before their derived contracts are considered.

The clearest accidental outlier is `test/libraries/FeeMath.t.sol`: a math-library suite inherits
the complete protocol fixture and consequently emits about 133 KB.

## Coherence notes

- 43 of the 117 tracked test files, totaling roughly 14,900 lines, were added since June 2026.
  The suite has grown feature by feature rather than from one current architecture.
- The only tracked test command is effectively one monolithic `forge test`. There are no
  committed smoke, feature, shard, or full-release lanes.
- `LogTest.sol` is a logging / data-generation utility presented as a test.
- `InvariantTests.sol` exercises a generic Solmate mock ERC-20 rather than a Wildcat contract
  and appears to be legacy scaffolding.
- Four runnable legacy files do not use the `.t.sol` suffix, while
  `access/BaseAccessControls.t.sol` is an abstract base with no runnable suite.
- Provider factory suites contain substantial repeated structure.
- There are no fork-based Solidity tests. Production-like behavior is simulated locally;
  deployment fork rehearsals and deploy-UI fork tests are separate.
- The last recorded coverage result predates the current suite: 98.35% lines and 96.32%
  branches at 1,298 tests. Current coverage has not been measured because Forge coverage still
  fails on the SphereX / monolithic compiler path. Accurate coverage now works for completed
  replacement slices; see the phase-one checkpoint below.

## Preferred approach: parallel ground-up replacement

Incremental cleanup would reduce some obvious waste, but it would also preserve the inheritance
and fixture architecture that produced the current compile cost. The preferred approach is a
new coherent suite built beside the existing one.

- Keep `test/` unchanged and executable as the behavioral reference during migration.
- Build the replacement under `test-next/` with canonical deploy compiler settings.
- Do not import the broad legacy fixture into the new suite.
- Compare semantic properties and source coverage, not raw test counts.
- Run the old monolith only at family-level parity checkpoints, not after every test-only edit.
- Make the replacement the ordinary audit-facing suite only after parity is demonstrated.

This is a ground-up implementation without a big-bang cutover. No existing test relocation is
required to begin.

## Success criteria

The final acceptance command is the ordinary clean-checkout test command under canonical deploy
settings. It must not require the cheap-IR profile, sharding script, warmed caches, or local
knowledge.

| Measure                   | Acceptance direction                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Behavioral properties     | Every existing property replaced, strengthened, retained with rationale, or explicitly retired with rationale |
| Source coverage           | No per-file line, branch, or function regression; aggregate coverage equal or better                          |
| Invariants                | Existing invariant semantics and target surfaces preserved or strengthened                                    |
| Compiler settings         | Canonical deploy settings using official solc                                                                 |
| Test creation bytecode    | Working target: reduce approximately 12.5 MB to 4 MB or less                                                  |
| Clean canonical test time | Working target: five minutes or less on the current 9950X machine                                             |
| Audit interface           | Plain canonical command; no one-off runner                                                                    |

The bytecode and timing numbers are initial engineering targets, not claims. The first
representative vertical should confirm whether they are realistic before the whole suite is
ported.

## Replacement architecture

### Concrete suites

- Put test and invariant entrypoints only on concrete domain suites.
- Do not inherit `test*` or `invariant*` functions into multiple concrete variants.
- Prefer one concrete suite per behavior domain rather than one per implementation variant.
- Exercise open-term, fixed-term, periodic-term, standard, and revolving variants through
  runtime/data-driven cases where their expected behavior is shared.
- Keep explicit variant-specific tests where behavior genuinely differs.

Execution may become somewhat slower because one test can deploy several runtime cases. That is
the right trade: the current clean run spends about 97% of its time compiling and 3% executing.

### Fixtures and deployment

- Start from a minimal assertion/cheatcode kernel rather than `test/shared/Test.sol`.
- Compose capability-specific fixtures for controller/registry, hooks/providers, markets, Lens,
  and wrappers.
- Keep fixture-only contracts abstract or otherwise prevent unused standalone bytecode.
- Prefer artifact-backed deployment such as `vm.deployCode` for dependencies that are merely
  fixture infrastructure, after verifying constructor and immutable behavior.
- Keep real factory/CREATE2 deployment paths wherever deployment behavior itself is under test.
- Avoid embedding every dependency's creation code into every concrete test contract through
  repeated `new Contract(...)` expressions.

### Shared behavior

- Express shared behavior as internal assertion routines or scenario drivers called by one
  concrete suite.
- Use small adapters when different hook/provider implementations need a common conformance
  interface.
- Isolate runtime matrix cases with fresh deployments or snapshots so one variant cannot affect
  another.
- Keep helpers narrow: large internal helpers can still be inlined into every caller and recreate
  the bytecode problem under a different name.

### Invariants

- Group invariants by semantic risk rather than implementation inheritance.
- Configure multiple runtime handlers/targets from one concrete invariant suite where Foundry's
  target model permits it.
- Preserve the current call surfaces, ghost-state checks, unwind assertions, and variant matrix.
- Keep separate concrete invariant contracts only where target selection or state isolation
  requires them.

## Parity ledger

Every current test entry should map to one of:

- directly replaced
- covered by a stronger data-driven property
- deliberately retained only in the reference suite
- retired with written rationale

The ledger must also record:

- originating suite and inherited declaration
- protocol behavior or invariant protected
- variants exercised
- expected events/reverts/state transitions
- replacement suite/property
- coverage delta when the family is complete

The current count of 1,797 is not a target. A coherent suite should have fewer entrypoints if one
runtime property replaces several compile-time copies without reducing behavior coverage.

## Work plan

### Phase 0: establish measurable parity

- Capture the exact canonical audit command, fixed seed, clean compile time, execution time, peak
  RSS, and emitted test bytecode.
- Apply or replace the documented SphereX coverage workaround and record current per-file line,
  branch, and function coverage.
- Generate the first parity ledger from the existing suite, including inherited origins.
- Keep the 1,797-test fixed-seed run as the reference oracle during migration.

Current checkpoint:

- the canonical artifact/AST inventory is reproducible with `scripts/test-suite-metrics.js`
- the compact legacy ledger records all 1,438 declared properties in
  `test-next/parity/legacy-suite.json`
- the legacy monolith remains blocked by separate non-IR stack-too-deep and minimum-IR Yul
  allocation failures after applying the SphereX workaround
- `yarn coverage:next` applies and reverses that workaround safely; accurate non-IR coverage now
  works for the replacement suite's narrow import graph
- no coverage-only Solidity change is retained

### Phase 1: prove the architecture

- Add the canonical-settings `test-next/` profile and isolated output/cache paths.
- Build the minimal test kernel and artifact-backed fixture deployer.
- Port a small library/type slice to validate the kernel.
- Port the shared access-control behavior as the first representative vertical: its 70 base tests
  currently expand to 210 concrete entries across three hook types.
- Compare coverage, property disposition, emitted bytecode, and clean compile time before
  accepting the architecture.

The first representative checkpoint is implemented:

- the 70 shared `BaseAccessControls` properties compile once instead of becoming 210 inherited
  entries, and one missing wrapper-transfer property was added
- the library/type family retains every meaningful legacy property and adds 11 useful entries;
  its initcode fell from 314,141 to 126,897 bytes including replacement support artifacts
- 236 tests across 16 suites pass the fixed timestamp and seed with zero inherited entries
- the complete checkpoint emits 200,559 bytes of initcode
- a forced canonical compile-to-green took 57.77 seconds and peaked at 1,799,392 KiB RSS
- accurate coverage is 98.16% lines, 97.69% statements, 94.59% branches, and 99.49% functions

See `test-next/parity/access-controls.md` and `test-next/parity/libraries-types.md` for property
disposition and comparison details. Hook-specific OpenTerm, FixedTerm, and PeriodicTerm properties
remain in the migration backlog.

The first Phase 2 family is also complete:

- one runtime matrix replaces the six role-provider factory suites
- all 55 legacy factory properties map to 18 replacement entries, with shared entries exercising
  every applicable factory
- the six factory contracts have 100% line, statement, branch, and function coverage
- dedicated test-side initcode fell from 190,018 to 18,598 bytes, a 90.21% reduction
- the full replacement checkpoint is 254 tests across 17 suites with zero inherited entries and
  219,157 bytes of test-side initcode
- forced canonical compile-to-green is 59.64 seconds with a 1,860,904 KiB RSS peak

See `test-next/parity/role-provider-factories.md` for the property map and exact comparison.

Token-backed provider behavior is the next completed Phase 2 slice:

- 30 focused properties replace 84 legacy constructor, credential, and deposit-hook entries
  across ERC20, ERC721, ERC1155, ERC4626-assets, ERC5192, and ERC5484 providers
- production provider artifacts run through production `OpenTermHooks.onDeposit`; the repeated
  full controller/factory/market fixture is no longer part of the provider matrix
- the four pull providers have 100% line, statement, branch, and function coverage
- ERC5192/ERC5484 have 100% branch/function coverage; Forge misses only their four
  constant-return source lines despite executing and counting both functions
- dedicated initcode for the migrated 84-property slice falls from 1,110,784 to 30,482 bytes, a
  97.26% reduction
- the full replacement checkpoint is 284 tests across 19 suites with zero inherited entries and
  249,888 bytes of test-side initcode
- forced canonical compile-to-green is 63.23 seconds with a 1,960,240 KiB RSS peak

The remaining token-provider work is three debt-token and wrapper integration properties. Generic
market-to-hook dispatch is mapped once to the later market/access-hook slice rather than repeated
for each provider. See `test-next/parity/token-role-providers.md`.

The managed-provider family is also complete:

- 24 focused properties replace 44 AccessList and Merkle provider/integration entries
- shared two-step administration runs once as a two-provider matrix
- production provider artifacts run through production `OpenTermHooks` for TTL, local-block,
  packed-proof, malformed-data, and root/list update behavior
- ManagedRoleProvider and AccessListRoleProvider have 100% line, statement, branch, and function
  coverage; MerkleRoleProvider has 100% branch/function coverage with one constant-return line
  missed by Forge instrumentation
- dedicated initcode falls from 267,476 to 25,660 bytes, a 90.41% reduction
- the full replacement checkpoint is 308 tests across 20 suites with zero inherited entries and
  275,548 bytes of test-side initcode
- forced canonical compile-to-green is 66.66 seconds with a 2,036,800 KiB RSS peak

The earlier factory matrix already owns AccessList/Merkle creation and hook-constructor
attachment. Production FixedTerm and generic market-to-hook dispatch remain assigned to their
later feature slices. See `test-next/parity/managed-role-providers.md`.

The ArchController family is also complete:

- one five-registry runtime matrix replaces the repeated controller-factory, controller, market,
  borrower, and blacklist CRUD suites
- lightweight registered targets preserve the ArchController-owned SphereX propagation,
  allowlisting, null-engine, authorization, missing-entry, event, and revert behavior without
  inheriting the full market fixture
- `WildcatArchController` has 100% line, statement, branch, and function coverage
- 12 properties replace 47 legacy entries
- dedicated initcode falls from 195,663 to 15,393 bytes, a 92.13% reduction
- the full replacement checkpoint is 320 tests across 21 suites with zero inherited entries,
  290,941 bytes of test-side initcode, and 284,697 bytes of runtime bytecode
- forced canonical compile-to-green is 68.10 seconds with a 2,088,680 KiB RSS peak

The disabled CAF-13 pagination and CAF-16 registered-target remediation cases remain documented
known behavior rather than replacement assertions because the deployed ArchController is a
singleton. See `test-next/parity/wildcat-arch-controller.md`.

The borrower identity registry family is complete as well:

- 32 focused properties replace all 43 direct registry entries
- production ArchController/registry artifacts cover account-factory administration, identity
  registration, two-step principal transfers, dynamic revalidation, resolution, and pagination
- the replacement adds a reachable nested-principal ambiguity case missing from the legacy suite
- `WildcatBorrowerIdentityRegistry` has 100% line, statement, branch, and function coverage
- dedicated initcode falls from 49,053 to 26,885 bytes, a 45.19% reduction
- the full replacement checkpoint is 352 tests across 22 suites with zero inherited entries,
  317,826 bytes of test-side initcode, and 311,398 bytes of runtime bytecode
- forced canonical compile-to-green is 71.50 seconds with a 2,168,304 KiB RSS peak

Borrower-account origination and compatibility remain separate integration slices. See
`test-next/parity/borrower-identity-registry.md`.

The testnet ArchController owner helper is complete:

- 16 properties replace all 17 ceremony-helper entries
- executor rotation, permissionless testnet borrower onboarding, generic owner actions, the
  legacy fee call, and ArchController/SphereX ownership transitions retain real cross-contract
  authorization paths
- malformed and reverting bound-target identity responses plus both swap-pop branches strengthen
  the legacy cases
- helper coverage is 100% lines/functions and all executable branches are asserted; Forge still
  misses the explicitly tested `onlyAuthorized` modifier statement/branch
- dedicated initcode falls from 47,776 to 26,321 bytes, a 44.91% reduction
- the full replacement checkpoint is 368 tests across 23 suites with zero inherited entries,
  344,147 bytes of test-side initcode, and 336,835 bytes of runtime bytecode
- forced canonical compile-to-green is 73.69 seconds with a 2,300,612 KiB RSS peak

See `test-next/parity/mock-arch-controller-owner.md`.

The borrower-account origination integration slice is complete:

- one two-factory runtime matrix replaces the separate standard/revolving origination paths
- nine properties replace 11 entries while preserving resolved-principal administration,
  operational account authority, shared hooks/nonces, fees, principal changes/removal, removed
  account factories, and cross-principal rejection
- production factories, hooks, markets, and stored initcode remain on every path under test
- dedicated initcode falls from 137,599 to 13,177 bytes, a 90.42% reduction
- the full replacement checkpoint is 377 tests across 24 suites with zero inherited entries,
  357,324 bytes of test-side initcode, and 349,986 bytes of runtime bytecode
- forced canonical compile-to-green is 75.62 seconds with a 2,353,872 KiB RSS peak

Accurate non-IR coverage for this graph is compiler-blocked in `HooksFactoryRevolving`; no
coverage-only source change is retained. See
`test-next/parity/borrower-account-origination.md`.

The hooks-administrator transfer integration slice is complete:

- five properties preserve the five legacy transfer/association properties while running both
  factory implementations at runtime
- hook and factory events, pending/accepted state, administrator indexes, compatibility aliases,
  callback authentication, swap-pop behavior, and deployment nonces remain explicit
- dedicated initcode falls from 124,577 to 7,627 bytes, a 93.88% reduction
- the full replacement checkpoint is 382 tests across 25 suites with zero inherited entries,
  364,951 bytes of test-side initcode, and 357,587 bytes of runtime bytecode
- forced canonical compile-to-green is 75.79 seconds with a 2,378,532 KiB RSS peak

This slice shares the revolving-factory accurate-coverage compiler block above. See
`test-next/parity/hooks-administrator-transfer.md`.

The sanctions family is complete:

- one concrete suite replaces the separate Sentinel and Escrow fixtures
- 11 properties replace 24 entries while preserving strict Chainalysis ABI validation,
  borrower-scoped overrides, exact CREATE2 addressing, escrow initialization/idempotency, and
  permissionless release behavior
- release assertions now verify both the escrow's full balance drain and the account's received
  balance
- both `WildcatSanctionsSentinel` and `WildcatSanctionsEscrow` have 100% line, statement, branch,
  and function coverage
- dedicated initcode falls from 43,206 to 11,830 bytes, a 72.62% reduction
- the full replacement checkpoint is 393 tests across 26 suites with zero inherited entries,
  376,781 bytes of test-side initcode, and 369,366 bytes of runtime bytecode
- forced canonical compile-to-green is 77.13 seconds with a 2,412,868 KiB RSS peak

See `test-next/parity/sanctions.md`.

The shared reentrancy guard is complete:

- three focused properties preserve the three legacy entries and exact rejection selector
- both state-changing and view reentrancy paths prove the guard remains usable after rejection
- dedicated initcode falls from 5,987 to 3,035 bytes, a 49.31% reduction
- branch and function coverage are 100%; Forge misses only the modifier source line that invokes
  an otherwise covered `_clearReentrancyGuard`
- the full replacement checkpoint is 396 tests across 27 suites with zero inherited entries,
  379,816 bytes of test-side initcode, and 372,349 bytes of runtime bytecode
- forced canonical compile-to-green is 77.74 seconds with a 2,423,068 KiB RSS peak

See `test-next/parity/reentrancy-guard.md`.

The standalone SphereX configuration family is complete:

- 13 properties replace 14 entries while preserving two-step admin transfer, operator and engine
  updates, interface validation, allowed-sender propagation, and registered-base authority
- the replacement adds explicit constructor state, both valid allowed-sender roles, the missing
  unauthorized role case, and post-transition/revert state checks
- `SphereXConfig` has 100% line, statement, branch, and function coverage; active registered-base
  engine communication remains assigned to protected-contract slices
- dedicated initcode falls from 19,288 to 13,580 bytes, a 29.59% reduction
- the full replacement checkpoint is 409 tests across 28 suites with zero inherited entries,
  393,396 bytes of test-side initcode, and 384,822 bytes of runtime bytecode
- forced canonical compile-to-green is 78.74 seconds with a 2,461,044 KiB RSS peak

See `test-next/parity/spherex-config.md`.

The direct standard/revolving hooks-factory family is complete:

- one 25-property runtime matrix replaces all 86 direct factory entries
- construction, registration, template administration, hook deployment, standard/revolving
  market deployment, every rejection path, indexes, pagination, and protocol-fee propagation are
  explicit
- production factories, hooks, markets, ArchController, borrower identity registry, and stored
  market initcode remain on the paths under test
- dedicated test-side initcode falls from 274,238 to 43,398 bytes, an 84.18% reduction; runtime
  bytecode falls from 245,720 to 43,363 bytes, an 82.35% reduction
- the full replacement checkpoint is 434 tests across 29 suites with zero inherited entries,
  436,794 bytes of test-side initcode, and 428,185 bytes of runtime bytecode
- forced canonical compile-to-green is 83.28 seconds with a 2,600,456 KiB RSS peak

Forge's noncanonical accurate-coverage profile is compiler-blocked in
`HooksFactoryRevolving.sol:882`; canonical via-IR validation is green and no coverage-only source
patch is retained. See `test-next/parity/hooks-factory-templates.md`.

The generic market-to-hook dispatch family is complete:

- 12 focused properties replace all 18 entries from `HooksIntegration.t.sol`
- production market code preserves flag gating, exact intermediate state and callback calldata,
  caller identity, arbitrary trailing data, nested/batched empty-data behavior, and APR callback
  return values
- focused LCOV comparison gives an identical executable-line hit set for all 11 dispatch routines
- dedicated initcode falls from 200,778 to 29,892 bytes, an 85.11% reduction; runtime bytecode
  falls from 87,282 to 29,639 bytes, a 66.04% reduction
- the full replacement checkpoint is 446 tests across 30 suites with zero inherited entries,
  466,686 bytes of test-side initcode, and 457,824 bytes of runtime bytecode
- forced canonical compile-to-green is 87.21 seconds with a 2,690,600 KiB RSS peak

See `test-next/parity/hook-dispatch.md`.

The direct OpenTerm-hooks family is complete:

- 13 mapped properties replace all 27 direct entries, plus two strengthened production-policy
  properties
- provider construction, market configuration, administrator transfer, minimum deposits,
  known/unknown lender withdrawal access, and transfer policy use the production hook
- `OpenTermHooks` has 100% line, statement, branch, and function coverage
- the replacement OpenTerm artifact is 26,593 bytes of initcode versus 146,404 bytes for the
  legacy concrete artifact; the legacy number still includes 70 shared inherited properties, so
  the final access-family reduction waits for FixedTerm and PeriodicTerm completion
- the full replacement checkpoint is 461 tests across 31 suites with zero inherited entries,
  493,279 bytes of test-side initcode, and 484,391 bytes of runtime bytecode
- forced canonical compile-to-green is 90.33 seconds with a 2,770,084 KiB RSS peak

See `test-next/parity/open-term-hooks.md`.

The direct FixedTerm-hooks family is complete:

- 13 mapped properties replace all 41 direct entries, plus two strengthened production-policy
  properties
- a seven-input runtime matrix preserves requested access separately from required callback flags,
  minimum deposits, transfer disablement, closure, and term-reduction policy
- term boundaries and administration, post-term withdrawals, lender access, APR gating, early
  closure, exact events, and all callback selectors use the production hook
- `FixedTermHooks` has 100% line, statement, branch, and function coverage
- the replacement FixedTerm artifact is 31,989 bytes of initcode versus 158,407 bytes for the
  legacy concrete artifact; the latter includes 70 inherited base properties, so the complete
  access-family comparison still waits for PeriodicTerm
- the full replacement checkpoint is 476 tests across 32 suites with zero inherited entries,
  525,268 bytes of test-side initcode, and 516,354 bytes of runtime bytecode
- forced canonical compile-to-green is 93.21 seconds with a 2,861,828 KiB RSS peak

See `test-next/parity/fixed-term-hooks.md`.

The direct PeriodicTerm-hooks family and complete access-hooks comparison are complete:

- 23 focused properties replace all 93 direct PeriodicTerm entries
- recurring withdrawal-window math, schedule boundaries, access control, closure, APR proposals,
  response windows, expiry, unpaid-withdrawal gates, and both execution paths use the production
  hook
- actual deposit credentials establish known-lender continuity; no test-only storage setter is
  used
- `PeriodicTermHooks` has 100% line, statement, branch, and function coverage
- across BaseAccessControls, OpenTerm, FixedTerm, and PeriodicTerm, concrete entries fall from 371
  to 124 and inherited entries fall from 210 to zero
- the complete access family falls from 501,473 to 181,342 bytes of test-side initcode, a 63.84%
  reduction; runtime bytecode falls from 486,887 to 178,301 bytes, a 63.38% reduction
- the full replacement checkpoint is 499 tests across 33 suites with zero inherited entries,
  574,340 bytes of test-side initcode, and 565,301 bytes of runtime bytecode
- forced canonical compile-to-green is 97.25 seconds with a 2,748,736 KiB RSS peak

See `test-next/parity/periodic-term-hooks.md`.

The shared market-constraint state machine is complete:

- seven focused properties replace the ten hook-state properties embedded in the legacy
  `WildcatMarketConfigTest`; its remaining 34 market properties stay assigned to the market slice
- parameter constraints, the exact APR reduction formula, integer-rounding boundary, temporary
  reserve activation/update/cancellation/expiry, timer preservation/extension, and storage cleanup
  use the production `OpenTermHooks` delegate
- every advertised deployment constraint now has accepted boundaries and an exact overflow error
- `MarketConstraintHooks` has 100% line, statement, branch, and function coverage
- the focused artifact is 13,389 bytes of initcode and 13,363 bytes of runtime bytecode; no
  reduction is claimed against the mixed 44-property legacy market artifact
- the full replacement checkpoint is 506 tests across 34 suites with zero inherited entries,
  587,729 bytes of test-side initcode, and 578,664 bytes of runtime bytecode
- forced canonical compile-to-green is 98.97 seconds with a 2,784,556 KiB RSS peak

See `test-next/parity/market-constraint-hooks.md`.

The shared standard/fixed-term market-token family is complete:

- seven runtime-matrix properties replace all 40 concrete ERC-20 entries from the standard and
  inherited FixedTerm market-token suites
- production market and hook artifacts preserve metadata, mint/burn accounting, approvals,
  ordinary/self transfers, finite/infinite allowances, exact failure modes, and blocked-recipient
  policy
- `WildcatMarketToken` has 100% line, statement, branch, and function coverage
- dedicated test-side initcode falls from 351,648 to 15,940 bytes, a 95.47% reduction; runtime
  bytecode falls from 111,056 to 15,914 bytes, an 85.67% reduction
- the full replacement checkpoint is 513 tests across 35 suites with zero inherited entries,
  603,669 bytes of test-side initcode, and 594,578 bytes of runtime bytecode
- forced canonical compile-to-green is 101.35 seconds, including 98.79 seconds in solc, with a
  2,828,104 KiB RSS peak

The shared artifact-backed market fixture is now established. Later market-base, configuration,
lifecycle, and withdrawal properties will join the same concrete suite rather than creating new
OpenTerm/FixedTerm artifacts. See `test-next/parity/market-token.md`.

The shared standard/fixed-term market-base family is complete:

- seven runtime-matrix properties replace all 34 direct and inherited base entries
- production market, hooks, ArchController, and borrower registry artifacts preserve constructor
  layout/validation, initial and accrued state reads, scale-factor behavior, fee caps, and guarded
  reentrant reads
- the replacement assertions strengthen several legacy getter-only entries with exact state,
  debt, supply, coverage, borrowable-asset, and protocol-fee values
- the base slice adds 20,697 bytes of dedicated initcode versus 448,386 bytes across the two
  legacy artifacts, a 95.38% reduction; runtime bytecode falls 90.06%
- cumulatively, the token-plus-base family falls from 800,034 to 36,637 bytes of dedicated
  initcode and from 74 entries to 14, with no inheritance
- the full replacement checkpoint is 520 tests across 35 suites with zero inherited entries,
  624,366 bytes of test-side initcode, and 615,229 bytes of runtime bytecode
- forced canonical compile-to-green is 1m43.85s, including 101.24s in solc, with a 2,877,928 KiB
  RSS peak; execution is 1.43s

Focused accurate coverage keeps `WildcatMarketToken` at 100%. `WildcatMarketBase` is 66.57%
lines and 78.00% functions at this boundary because configuration, lifecycle, borrower transfer,
and withdrawal behavior remain assigned to subsequent market slices. See
`test-next/parity/market-base.md`.

The shared standard/fixed-term market-configuration family is complete:

- seven constraint-hook properties and 15 market properties replace all 88 direct and inherited
  configuration entries
- capacity, borrower authority, sanctions withdrawals and escrow, wrapper registration, APR
  updates and liquidity gates, pending APR execution, and protocol-fee updates use production
  market code and runtime OpenTerm/FixedTerm variants where behavior can differ
- `WildcatMarketConfig` has 100% line, statement, branch, and function coverage; the separate
  `MarketConstraintHooks` production boundary remains at 100% across all four measures
- dedicated configuration initcode falls from 456,281 to a conservatively counted 38,042 bytes,
  a 91.66% reduction; runtime bytecode falls 82.35%
- cumulatively, the token/base/configuration family falls from 1,256,315 to 74,679 bytes of
  initcode and from 162 entries to 36, with no inheritance
- the full replacement checkpoint is 535 tests across 35 suites with zero inherited entries,
  648,619 bytes of test-side initcode, and 639,436 bytes of runtime bytecode
- forced canonical compile-to-green is 1m48.26s, including 105.14s in solc, with a 2,966,276 KiB
  RSS peak; execution is 1.83s

Focused accurate coverage leaves `WildcatMarketBase`, `WildcatMarket`, and
`WildcatMarketWithdrawals` intentionally partial until lifecycle, borrower-transfer, and
withdrawal behavior join the shared market artifact. See `test-next/parity/market-config.md`.

The shared standard/fixed-term market-lifecycle family is complete:

- 14 runtime-matrix properties map 120 of the 122 direct and inherited lifecycle entries; the
  remaining two closed-market drain entries belong to the withdrawal family
- state updates, deposits, fees, borrowing, repayment, closure, batch-key safety, and rescue
  behavior run through production market code with both OpenTerm and FixedTerm hooks
- completed token, dispatch, and access-hook suites own the duplicated cross-boundary behavior
  instead of recompiling it into this artifact
- `WildcatMarket` reaches 98.32% lines, 97.90% statements, 86.36% branches, and 100% functions;
  its two uncovered lines require either an unreachable internal state or a dishonest ERC-20 and
  remain assigned to the adversarial/invariant pass
- dedicated lifecycle initcode falls from 518,970 to 40,109 bytes, a 92.27% reduction; runtime
  bytecode falls 85.56%
- the full replacement checkpoint is 549 tests across 35 suites with zero inherited entries,
  688,728 bytes of test-side initcode, and 679,543 bytes of runtime bytecode
- forced canonical compile-to-green is 1m53.83s, including 110.76s in solc, with a 3,044,364 KiB
  RSS peak; execution is 1.80s

See `test-next/parity/market-lifecycle.md`.

The core market borrower-transfer family is complete:

- ten composed properties replace all 29 market-owned legacy entries, and one added adversarial
  property covers malformed registry response words
- direct principals, borrower accounts, same-account principal migration, target replacement,
  factory removal, raw sanctions, acceptance revalidation, authority, and accounting use production
  contracts
- all 64 executable lines and all 12 branches in the `WildcatMarketBase` borrower-transfer region
  are covered
- the two withdrawal-escrow entries are complete in the market suite, and production wrapper
  integration now closes the remaining six handoffs
- the market artifact is now 32,451 bytes of initcode and 32,425 bytes of runtime bytecode; the
  final family comparison is recorded with wrapper integration so shared behavior is not priced
  independently
- the full replacement checkpoint is 560 tests across 36 suites with zero inherited entries,
  718,635 bytes of test-side initcode, and 709,424 bytes of runtime bytecode
- forced canonical compile-to-green is 1m57.16s, including 114.03s in solc, with a 3,121,564 KiB
  RSS peak; execution is 1.84s

See `test-next/parity/market-borrower-transfer.md`.

The standard/fixed-term market-withdrawal family is complete:

- 18 runtime-matrix properties replace all 124 direct and inherited withdrawal entries; completed
  access-hook suites own the repeated credential gates
- the same checkpoint closes the two lifecycle drain and two borrower-principal escrow handoffs,
  for 128 mapped legacy entries in total
- normalized, scaled, and full queueing; execution; sanctions routing; unpaid-batch processing;
  repayment; FIFO limits; closure; and every withdrawal query use production market behavior
- `WildcatMarketWithdrawals` has 100% line, statement, branch, and function coverage
- growth of the shared market and borrower-transfer artifacts is 43,271 bytes of initcode and
  runtime bytecode, versus 463,643 and 223,049 bytes for the two legacy withdrawal artifacts: a
  90.67% initcode and 80.60% runtime reduction
- the full replacement checkpoint is 579 tests across 36 suites with zero inherited entries,
  761,906 bytes of test-side initcode, and 752,695 bytes of runtime bytecode
- forced canonical via-IR compile-to-green is 2m08.40s, including 125.23s in solc, with a
  3,233,724 KiB RSS peak; execution is 1.88s

See `test-next/parity/market-withdrawals.md`.

The Wildcat 4626 wrapper-factory family is complete:

- nine composed properties replace all 16 legacy factory entries
- legacy forwarding, floor-generation isolation, hostile rounding probes, deployment,
  registration, duplication, and transfer-policy validation use the production factory and wrapper
- `Wildcat4626WrapperFactory` has 100% line, statement, branch, and function coverage
- dedicated initcode falls from 43,771 to a conservatively counted 18,532 bytes, a 57.66%
  reduction; runtime bytecode falls 58.32%
- the full replacement checkpoint is 588 tests across 37 suites with zero inherited entries,
  780,438 bytes of test-side initcode, and 770,735 bytes of runtime bytecode
- forced canonical via-IR compile-to-green is 2m08.75s, including 125.56s in solc, with a
  3,284,512 KiB RSS peak; execution is 1.88s

See `test-next/parity/wildcat-4626-wrapper-factory.md`.

The core Wildcat 4626 wrapper family is complete:

- 19 composed properties replace all 160 non-factory vault entries
- conversion and execution fuzzing covers every ERC-4626 entrypoint, rounding direction, allowance
  mode, cap, round trip, donation, and scaled-backing identity
- sanctions, insolvency, malformed low-level reads, quarantine, arbitrary-token sweep, market-token
  surplus sweep, and atomic rollback use the production wrapper
- `Wildcat4626Wrapper` reaches 98.42% lines, 98.52% statements, 94.29% branches, and 95.92%
  functions in the focused mock slice; production integration now executes the live escrow-release
  branch, while the other misses are shadowed helpers or guards unreachable under
  `scaleFactor >= RAY`
- dedicated initcode falls from 304,837 to 81,822 bytes, a 73.16% reduction; runtime bytecode falls
  73.22%
- the full replacement checkpoint is 607 tests across 38 suites with zero inherited entries,
  862,458 bytes of test-side initcode, and 852,256 bytes of runtime bytecode
- forced canonical via-IR compile-to-green is 2m18.95s, including 135.52s in solc, with a
  3,476,168 KiB RSS peak; execution is 2.08s

See `test-next/parity/wildcat-4626-wrapper.md`.

The production Wildcat 4626 wrapper integration family is complete:

- seven composed properties replace ten legacy wrapper-integration entries and the six remaining
  borrower-transfer wrapper handoffs
- production OpenTerm, FixedTerm, and PeriodicTerm hooks prove wrapper readiness before and after
  credentialing; standard and revolving markets share the same quarantine rules
- production ArchController, borrower registry, Sentinel, CREATE2 escrows, market, wrapper factory,
  and wrapper cover coordinated quarantine, unrelated-holder redemption, backing protection,
  principal namespace migration, escrow release, and operational-borrower sweep authority
- the accurate coverage profile compiles the 74-source graph and executes the live escrow-release
  path without a new compiler exception
- conservatively charged integration initcode falls from 432,010 to 32,678 bytes, a 92.44%
  reduction; runtime bytecode falls from 191,416 to 32,417 bytes, an 83.06% reduction
- across borrower transfer plus wrapper integration, 47 legacy entries become 19 replacement
  properties while emitted initcode falls 89.81% and runtime bytecode falls 76.66%
- the full replacement checkpoint is 614 tests across 39 suites with zero inherited entries,
  890,595 bytes of test-side initcode, and 880,367 bytes of runtime bytecode
- forced canonical via-IR AST compile-to-green is 2m26.55s, including 142.83s in solc, with a
  3,814,448 KiB RSS peak; execution is 2.06s

See `test-next/parity/wildcat-4626-wrapper-integration.md`.

### Phase 2: migrate feature families

Suggested order:

1. libraries and types
2. controller, registries, factories, and role providers
3. access hooks
4. market base, token, configuration, and withdrawals
5. fixed/periodic and standard/revolving variant behavior
6. wrappers and Lens
7. integration scenarios and invariants

Each family lands only after its parity ledger and coverage comparison are complete. The
fixed-term equivalence suites and matrix invariants come late because they offer large savings
and carry the greatest semantic risk.

### Phase 3: cut over the audit path

- Point the default/deploy test discovery at the replacement suite.
- Run both suites with the fixed seed under canonical settings.
- Run the ordinary clean-checkout audit command and record final time, memory, bytecode, and
  coverage.
- Keep the old suite excluded but available for one review/audit cycle.
- Remove or archive it only in a separate, explicit follow-up decision.

## Developer sharding

The cheap-IR sharder can still be completed as optional local tooling. It is useful, but it is
not on the critical path and none of its timing counts toward the redesign's acceptance result.

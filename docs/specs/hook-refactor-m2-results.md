# M2 results: shared hook behavior

- Plan: [M2 execution plan](hook-refactor-m2-plan.md).
- Current status: [M2 tracker](hook-refactor-m2-tracker.md).
- Execution starting revision: `1b8e36c76713af709a9326adfceac33b15b5f619`.
- Reference: approved [M1 design](hook-refactor-m1-design.md) and
  [M1 baseline](hook-refactor-m1-baseline.md).
- Raw evidence root: `audits/hook-refactor/m2/2026-09-22/` (ignored).

## M2-01: Execution identity and reusable evidence

The execution checkout is the approved M2 planning commit, with no tracked
working-tree edits. The two reference documents remain untracked. All four
top-level submodules match M1 and have clean working trees. No production or
test source has changed since the behavioral baseline
`4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

Compared the 1,166 materialized input files to M1's manifest. The only different
file is `foundry.toml`, matching M1's documented explicit-settings amendment
exactly. Both effective `forge config --json` objects match M1. Forge 1.8.3
(`cae51ad458f6abb64852b7709eb784352429825d`) and solc 0.8.25 match the recorded
binary hashes; Cancun, via IR, optimizer 44, isolation, and dynamic test linking
are unchanged. Node is v24.21.0 and the existing local Corepack shim supplies
Yarn 1.22.22.

| Evidence | Disposition |
| --- | --- |
| M1 default, fixed-seed, and deploy test receipts | Reusable starting baseline. Each log hash matches its receipt and records 698 passes, zero failures/skips. These were not rerun or claimed as new M2 passes. |
| M1 raw ABIs and metadata | Retained. All three current deploy-artifact ABIs match the exports exactly; compare each implementation checkpoint against these exports. |
| M1 deployment sizes and bytecode identities | Reusable. Current creation/runtime lengths and byte hashes match all three recorded templates. |
| M1 gas receipts and scenario identifiers | Retained intact and hashed with the other raw evidence. Preserve fixture/caller/state/transaction boundaries when scenarios move. |
| M1 storage/interface probes | Retained design evidence; do not treat compiler probes as runtime composition tests. |

### Lint baseline

The first `yarn lint:check` attempt failed because Prettier was not installed.
Ran `yarn install --frozen-lockfile --ignore-scripts`, using the existing
lockfile and Corepack shim. All materialized input hashes, including package
and lockfile, remained unchanged. The installation and initial failure are
recorded as setup receipts, not source regressions.

With dependencies available, `yarn lint:check` exits 1 because Prettier reports
41 existing source/test files. `prettier-baseline-files.json` lists them. The
script uses `&&`, so Solhint did not run through that command. Ran its same
arguments separately:

```sh
node_modules/.bin/solhint --config ./.solhint.json \
  --ignore-path ./.solhintignore 'src/**/*.sol' 'test/**/*.sol'
```

Solhint exits 0: zero errors and 22 existing line-length warnings. Subsequent
checks must have no new formatting failures or lint errors; format changed
files without a repository-wide unrelated cleanup. Preserve the failing full
lint result while the untouched baseline files remain.

### Identity and receipt hashes

Paths in this table are relative to the M2 evidence root. M1 artifacts remain
under their original root and are bound by `m1-evidence.sha256.json`.

| File | SHA-256 |
| --- | --- |
| `identity-start.json` | `6adbc970c050b4de3bed188f69a113b7f787450588ed3948b24bdcdf233dfcd1` |
| `inputs-start.sha256.json` | `6a143be7737722ca63012ce2cd51d9538da7f7bfd0cf7d59bdd99b3abe1c34db` |
| `m1-evidence.sha256.json` | `da948d69633267d456c0620dbe2c43fd9b2501a530a306038db4afe9958e4c26` |
| `lint-baseline-receipt.json` | `d1b841959d52675724922cf747391151311e7c5b7e58eb4eca555463cd12282d` |
| `lint-baseline.log` | `302d2e6df196ccb6521513a4517d6c3a75cd03740c69b7aa528269f171c0c113` |
| `solhint-baseline-receipt.json` | `96c4bc7c9c4f37ef89344601774b3643ebfa9edb2e0d76c25fdd40609af147f5` |
| `solhint-baseline.log` | `d39a3ea9e56e55014406a10998982c1ca66554c3c21447cb7d1a044e2c8e24d2` |

## Test ownership and migration map

The existing concrete access test entrypoints are inventoried in
`tests-start-inventory.json`. This map assigns their properties as each domain
moves; it is not a claim that the new suites already exist. Equivalent
assertions move once into `test/access/BaseHooks.t.sol`, exercising the three
actual production templates through a runtime matrix. Internal helpers may
live in `test/shared/`; they must not declare inherited test entrypoints.

| Existing property / source | Destination and treatment | Task |
| --- | --- | --- |
| All three suites' `test_constructor_*` and provider-constructor helpers | Common runtime matrix: empty/encoded args, existing/new/mixed providers, name, indices/TTLs, missing factory and failed creation. Remove superseded assertions/helpers. Provider machinery remains owned by `BaseAccessControls.t.sol`. | M2-02. |
| Common portions of `test_metadataConfigAndConstraints_AreCanonical` | Common constructor/flags matrix and existing constraint owner. Keep each template's distinct family/revision/constant assertions where appropriate; preserve exact optional/required masks. | M2-02. |
| Open `AuthenticatesFactoryAndAdministrator`; authentication portions of fixed/periodic creation tests | Common creation guard/order matrix; retain required-term length and term validation in their domain suites. Add competing-failure cases where the coordinator/decode boundary changes. | M2-02. |
| Open `ConfiguresFlagsAndMarketPolicies` / `RejectsInvalidAccessAndMinimumData`; fixed/periodic `ConfigMatrix` | Common requested-access/forced-dispatch/invalid-config/minimum/disabled-transfer matrix using template-specific data and public tuple readers. Keep fixed permissions/maturity and periodic schedule/packing assertions distinct. | M2-02. |
| All three `test_setMinimumDeposit_*` | Common authority/registration/dispatch/event matrix. Cover full open/fixed width and periodic checked narrowing, including guard precedence. Preserve untouched term/configuration fields on writes. | M2-02. |
| Batch getters, creation events, fixed maturity/permission data, periodic schedule data | Keep distinct public tuple shapes and event order covered; common helpers may compare shared fields. Raw readers stay in their owners; add targeted partial-word/low-bit/overflow cases where configuration moves. | M2-02. |
| `test_administratorTransfer_*` in template suites plus integration suite | Retain template configuration-preservation checks and real factory authority transfer; constructor/configuration extraction must not change their semantics. | M2-02, then revisit shared assertions only when their domain moves. |
| All three deposit and transfer properties; recipient/disabled queries | Common runtime matrix for minimum rounding, blocks, known-lender/cache state, wrapper exemptions, optional credentials, and query behavior. Keep credential algorithm tests in their existing owner. | M2-03. |
| Open queue access and shared portions of fixed/periodic queue tests | Common known/credential/access behavior; keep distinct maturity/window/closed-state boundaries and error priority in term suites. | M2-04. |
| All three unrestricted/no-op callback properties | Common callback matrix, preserving unknown-caller behavior. Split open's combined no-op/APR test so APR remains with its owning domain. | M2-04/M2-05. |
| Fixed/periodic closure tests | Retain domain properties: early-close OR permission, maturity update, periodic closed flag/proposal cancellation/event order. Common coordinator does not imply common term effects. | M2-04. |
| `MarketConstraintHooks.t.sol`, fixed APR guard, periodic proposal/execution tests | Keep one owner for bounds/reserve mathematics and separate term strategy/proposal properties; exercise both periodic routes and skipped default effects. | M2-05. |
| New extension checks | `test/access/HookExtensions.t.sol`: small transfer/view/rollback probe in M2-03; focused both-route APR validator in M2-05. Larger composition/replacement/state-isolation proof remains M4. | M2-03/M2-05. |
| Factory, dispatch, admin transfer, borrower-account, lens, wrapper, production matrix/economics and invariant suites | Continue using real production artifacts and deployment paths. Run affected checks per checkpoint, then required full qualification in M2-06. | M2-02 through M2-06. |

M1 gas scenarios use direct callbacks in the access/constraint suites and nested
callbacks in production scenarios. Preserve the no-argument fixture inputs,
caller/cache state, fixed timestamp/seed, deployment settings, and isolation
boundary if an owning test is renamed or moved. Do not compare whole test gas
to callback gas or use historical test counts as proof of retained coverage.

## M2-02: Shared construction, registration, and minimums

Status: implemented, verified, and accepted by the user for this signed
checkpoint. Parent checkpoint is `774ca36` (M2-01). The test input manifest,
comment amendment, and review patch below identify the implementation without
attributing it to that parent commit.

### Changes and ownership

- Added [BaseHooks](../../src/access/BaseHooks.sol), retaining the existing
  access and constraint bases as the sole credential/administration and
  bounds/APR owners. Shared constructor initialization, creation coordination,
  access/dispatch configuration, minimum management, and common declarations
  replace the three copied implementations.
- The concrete hooks retain their packed mappings, public structs/getters,
  raw calldata readers, and staged term decoding. Internal adapters expose
  common fields in memory and perform checked periodic minimum narrowing.
  Requested access is captured before forced/required callbacks are merged.
- Creation runs factory authentication, bounds, administrator, template decode/
  term checks and events, common access configuration, packed storage, then
  `_onMarketConfigured`. A test-only derived hook demonstrates observation of
  completed binding before code deployment and atomic rejection of binding
  and feature state.
- Common constructor/configuration/minimum assertions now live in
  [BaseHooksTest](../../test/access/BaseHooks.t.sol), using all three production
  artifacts through [HookTemplateFixture](../../test/shared/HookTemplateFixture.sol).
  The fixture has no test entrypoints. Provider algorithms and bounds retain
  their existing owners; term data, permissions, schedules, and public tuple
  details remain in their distinct suites.
- Removed superseded constructor/configuration/minimum tests and unused helpers.
  Added malformed/partial-word and low-bit decoding, guard/failure ordering,
  full-width writes, immutable dispatch, untouched configuration fields,
  unknown-market tuple, and creation-extension rollback cases. The access
  subtree still has 132 entrypoints: 22 former names removed and 22 new/renamed
  ones added, including the 12-test shared suite. The migration inventory and
  property map, rather than the coincidentally equal count, explain coverage.
- Mechanical error/event qualifications now reference `BaseHooks`, including
  two integration/market test files. Constructors, tuples, errors/events,
  flags, family strings, and periodic ABI revision are unchanged.

Deposit/transfer processing, transfer queries, queue/closure/no-op coordination,
and APR coordination have not been extracted in this checkpoint. Those tasks
remain M2-03 through M2-05; this is not a claim of completed M2 or M4 composition.

### Verification

Both focused final runs use `--fuzz-seed 0x5eed` with the unchanged default
timestamp/settings. The exact contract regex and source-input hash are in
`m2-02-test-receipts.json`.

| Check | Result |
| --- | --- |
| Default profile: access, factory, lens, administrator transfer, dispatch, production matrix suites | 207 passed / 13 suites; zero failures/skips. |
| Deployment profile: same selected suites | 207 passed / 13 suites; zero failures/skips. Real standard/revolving factory paths use the refactored artifacts. |
| M1 gas scenarios, deployment profile, timestamp `1724284800`, seed `0x5eed` | 17 tests / 5 suites plus the one cached-deposit production scenario pass; all 97 previously recorded callback observations match. Includes the wrapper integration scenario. |
| All three complete raw/semantic ABIs | Identical to M1; no callback argument-label exception is needed in this checkpoint. Default/deploy ABI and bytecode also match each other. |
| Compiler storage layouts | Identical mapping slots, member offsets/widths, and storage types after ignoring compiler AST IDs. Each configuration remains one 32-byte slot; no duplicate persisted access configuration. |
| `yarn lint:check` | Still exits 1 for 34 untouched baseline formatting failures, down from 41. No new formatting failure; all changed Solidity files are formatted. |
| Standalone Solhint with repository arguments | Exits 0, zero errors and the same 22 baseline warnings. |
| Input/scope checks | Recorded test inputs match the implementation before the comment amendment below; all 12 staged Solidity files retain identical non-comment tokens. Unrelated source, submodules, package/lockfile, and build settings are unchanged. |

These are checkpoint checks, not the full default/fixed-seed/deploy qualification
required at M2-06. An initial test compile rejected a reserved local variable
name; it was corrected before the final passing runs. Final test ownership
cleanup and import formatting are included in those runs.

During review, comments in six Solidity files were revised to the user's requested
voice. Compared lexer tokens against the preserved tested source: all 12 staged
Solidity files are identical after excluding comments. Prettier passes for the
six edited files; Solhint output is identical to the 22-warning baseline. Tests
and compilation were not rerun for this comment-only amendment. Original test
receipts remain intact; `m2-02-comments-receipt.json` binds the comparison and
current input manifest. NatSpec text and source locations have changed.

### Deployment sizes and cost changes

Default and deployment artifacts have identical bytecode. All runtime,
stored-initcode, and factory constructor-payload boundaries remain satisfied.

| Template | Runtime bytes | Creation bytes | `STOP + creation` | Stored-initcode headroom | Runtime/creation increase from M1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Open | 15,733 | 18,459 | 18,460 | 6,116 | +429 / +429 |
| Fixed | 17,033 | 19,760 | 19,761 | 4,815 | +432 / +432 |
| Periodic | 19,680 | 22,407 | 22,408 | 2,168 | +409 / +409 |

All 97 M1 callback trace measurements are unchanged: deposit, transfer, queue,
closure, ordinary APR, and dedicated periodic APR, including success/revert
paths and the labeled direct versus nested call boundaries. Those callback
bodies have not yet moved; these results do not predict M2-03 through M2-05 costs.

The same retained traces also permit 42 creation/minimum comparisons not in
M1's original 97-entry summary. Direct unit-fixture creation increases by
565–696 gas for open (6 observations), 559–630 for fixed (11), and 432–593 for
periodic (17); the remaining five creation observations are nested production
calls. In the periodic live-minimum production scenario, setting a positive
minimum changes from 31,871 to 32,967 gas (+1,096), clearing it from 31,743 to
32,596 (+853), and an unauthorized update from 24,140 to 24,143 (+3). These
are isolated top-level calls, including transaction overhead, as in M1.

Inspected optimized IR: creation materializes the common access view before
the template's packed configuration; minimum management decodes that view and
uses separate dispatch/write adapters. The extra memory work, helper calls,
and warm configuration reads explain the overhead without an extra persisted
mapping. Relevant compiler sections are preserved as
`m2-02-<Template>-adapter-ir.txt`. Source sharing is not a bytecode saving in
this checkpoint. The size/gas increases are explicit review tradeoffs; later
extractions must continue measuring the periodic stored-initcode budget.

### M2-02 evidence identities

Paths are relative to the M2 evidence root. Receipt files identify their log
hashes and exact commands. `m2-02-inputs.sha256.json` binds tested source/test/
script/build inputs; unchanged dependencies remain bound by M2-01's manifest.

| File | SHA-256 |
| --- | --- |
| `m2-02-inputs.sha256.json` | `96f34142f815a5f9720f50457745f002464637669672e15e99c5c2f30ef6cd8b` |
| `m2-02-test-receipts.json` | `aa0526df3cc2b4131f94707e752241e20590731a919f5d615715752344205929` |
| `m2-02-abi-comparison.json` | `02ec1eccd6a70aec911edb07793eaffcf28bfdfad6728a09fda2d864ad2b0de0` |
| `m2-02-storage-comparison.json` | `bacb5a5ee1ad3ddf694249284db3ad1e3d2ac7ad31b19da8bacfb981cba57943` |
| `m2-02-sizes.json` | `c80cdba369bcbf9f9e4e28da9ae339705c333140ac32bcfea7df4d0b83bfca9e` |
| `m2-02-gas-receipts.json` | `9ba5e380bd4c35747441aa159aa445b3542fb09c3b723093e1b2b424fc205702` |
| `m2-02-gas-comparison.json` | `33f7e8bf6903932269ae718cb432c53c1c8f10c837783e9cb5b15c7160217055` |
| `m2-02-creation-minimum-gas.json` | `1175de033fa026467253929c02ecccaa8cf9573a2e54dc74f4745ccd17fb8dd8` |
| `m2-02-lint-receipts.json` | `f580c678b041c381d49a0561dbbc6e6a02ece329a6f7c6fd1cac876fb82484f9` |
| `m2-02-test-migration.json` | `837105661aaddfebb7e26fb03a782d05f1e7bcf504ace1fcc093ff667165c0f0` |
| `m2-02-comments-receipt.json` | `3d230f7856d1b05da2d3bf2dfa6f9e80faf55398ec9ba43c94832e3036803096` |

The final review receipt records the staged Solidity patch hash and binds
the comment amendment and remaining raw artifacts. The original review receipt
and patch are retained with the `m2-02-before-comments-` prefix. The user approved
this staged checkpoint before its signed commit and the start of M2-03.

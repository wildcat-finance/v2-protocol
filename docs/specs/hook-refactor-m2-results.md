# M2 results: shared hook behavior

- Plan: [M2 execution plan](hook-refactor-m2-plan.md).
- Current status: [M2 tracker](hook-refactor-m2-tracker.md).
- Execution starting revision: `1b8e36c76713af709a9326adfceac33b15b5f619`.
- Reference: approved [M1 design](hook-refactor-m1-design.md) and
  [M1 baseline](hook-refactor-m1-baseline.md).
- Raw evidence root: `audits/hook-refactor/m2/2026-09-22/` (ignored).
- Final qualification: [M2-06](#m2-06-qualification-and-m3-handoff) is complete;
  [M3 handoff](#m3-handoff) awaits the user's M2 review and push.

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

Status: implemented, verified, and committed after user approval as `9d52fe0`,
signed by `kethcode <dave@wildcat.finance>`. Parent checkpoint is `774ca36` (M2-01). The test input manifest,
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

## M2-03: Deposit, transfer, views, and early extension probe

Status: accepted and committed as `6859b70720a7755eef6010d67a3dd55cf2b0638b`,
with a verified kethcode SSH signature. The approved Solidity patch matches the
commit; `m2-03-acceptance.json` records the approval and verification.
Parent checkpoint is `9d52fe09d132c5cb25bdf9235c82d324a7250386` (M2-02), whose
SSH signature was verified. The user reviewed this checkpoint before M2-04.

### Shared lender actions and feature seams

[BaseHooks](../../src/access/BaseHooks.sol) now owns deposit and transfer
coordination and defaults, plus both transfer-policy views. All three concrete
templates use these implementations; their copied bodies have been removed.
Credentials, caches, known-lender state, provider resolution, and wrapper
identification retain their single owner in `BaseAccessControls`.

The coordinators authenticate registration, run `_processDeposit` or
`_processTransfer`, then run the corresponding additional check. The default
transfer processor applies the disabled flag before returning for a known
recipient or exact registered wrapper. Those returns stay inside the processor,
so `_checkTransfer` still runs. Minimum rounding, local blocks, credential
resolution, and entry events retain their existing order.

The recipient view combines `_defaultTransferRecipientAllowed` with
`_featureTransferRecipientAllowed`. Its known-lender and wrapper exemptions
therefore have the same scope as the callback's. The global disabled view keeps
its permanent false promise; this checkpoint adds no global-lock mechanism.

[RecipientRestrictionHooks](../../test/mocks/RecipientRestrictionHooks.sol) is
a small test-only open-term derivative. One owned rule rejects one recipient
on one market through both the transfer check and its no-data view.
[HookExtensionsTest](../../test/access/HookExtensions.t.sol) proves acceptance,
ordinary denial, known-recipient and registered-wrapper denial, market scope,
and rollback of newly cached credentials and known-lender state. These are
observable effects and errors, not internal-call counts. This is the planned
early probe; broader composition and replacement proofs remain M4 work.

### M2-03 test ownership

| Property | Current owner |
| --- | --- |
| Registration before lender actions and transfer views | `BaseHooksTest.test_lenderActionsAndTransferViews_RejectUnregisteredMarkets`, across all three production artifacts. |
| Minimum floor, exact-minimum rounding, block-before-minimum priority, zero-minimum conversion skip | `BaseHooksTest.test_onDeposit_FloorsMinimumAndChecksLocalBlockFirst`. |
| Required/optional deposit credentials, cache writes, ordered grant/first-entry events, repeat entry, market-local known status, known-lender deposit blocks | `BaseHooksTest.test_onDeposit_ResolvesOptionalOrRequiredCredentialsAndRecordsEntry(bool)`. |
| Disabled transfers before known/wrapper exemptions; required/optional credentials, local blocks, known-recipient exemptions, cache/entry effects and query answers | The two shared `test_onTransfer_*` cases, across all three templates. |
| Pull-based recipient queries without cache or known-state writes, followed by actual entry | `BaseHooksTest.test_transferRecipientView_UsesPullCredentialsWithoutCachingThem`. |
| Additional recipient rule, exemption scope, and rollback | Four `HookExtensionsTest` cases. |
| Provider/cache algorithms and malformed/noncanonical wrapper responses | Existing `BaseAccessControlsTest`; unchanged owner. |
| Actual registered-wrapper entry/redemption, factory registration, and dispatch arguments | Existing wrapper integration, factory, and dispatch suites; real production artifacts. |
| Queue/closure caller differences and term behavior | Existing concrete suites; open/fixed caller tests now cover the remaining term endpoints. |

Removed six copied deposit/transfer tests from the concrete suites. Added six
shared cases and four extension cases; two caller-guard cases were narrowed and
renamed. The access subtree changes from 132 to 136 test entrypoints. Shared
fixtures still contain no test entrypoints, and there is no retained legacy
implementation or duplicate action suite.

### M2-03 verification

Both focused runs use `--fuzz-seed 0x5eed` with unchanged default timestamp and
build settings. Exact commands and input hashes are in the test receipts.

| Check | Result |
| --- | --- |
| Default profile: shared/extension/access/term suites, factories, lens, administrator transfer, dispatch, production matrix, wrapper integration | 226 passed / 15 suites; zero failures/skips. |
| Deployment profile: same selected suites | 226 passed / 15 suites; zero failures/skips. Actual factory deployment and wrapper paths pass. |
| ABI comparison against M1/M2-02 | Encoded surface unchanged. Only the four previously unnamed `onTransfer` inputs gain names: `caller`, `from`, `scaledAmount`, `state`, in all three templates. All previously named inputs, public tuple fields, errors/events, selectors, and mutability match exactly. Raw ABIs and allowed differences are retained. |
| Compiler storage layouts | Identical to M1 after ignoring compiler IDs. Each packed market configuration remains one slot; no new production state. |
| Production source and executable identity | Final production files exactly match the gas-measurement source snapshot. Default, deploy, and gas-measurement ABI/creation/runtime bytecode match each other. |
| `yarn lint:check` | Exits 1 for the same 34 untouched baseline formatting paths. No new formatting failure. |
| Standalone Solhint | Exits 0; output is identical to the existing 22-warning baseline. |

These are checkpoint checks. Full default/fixed-seed/deploy milestone
qualification remains M2-06. No build setting, dependency, market implementation,
batching rule, deployment inventory, or tranching policy changed.

### M2-03 size and gas comparisons

| Template | Runtime bytes | Creation bytes | `STOP + creation` | Stored-initcode headroom | Runtime/creation delta from M2-02 | Delta from M1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Open | 15,556 | 18,282 | 18,283 | 6,293 | -177 / -177 | +252 / +252 |
| Fixed | 16,864 | 19,591 | 19,592 | 4,984 | -169 / -169 | +263 / +263 |
| Periodic | 19,521 | 22,248 | 22,249 | 2,327 | -159 / -159 | +250 / +250 |

Runtime, stored-initcode, and factory constructor-payload limits remain satisfied.
The extraction reduces this checkpoint's code size while adding runtime work.

Gas was measured before removing the copied action tests, using the same commands
and unchanged test fixtures from `9d52fe0`. Their inputs and the production source
snapshot are retained separately from the final consolidated-test manifest.
All 97 M1 callback observations have identical arguments and return/revert
results. The 56 deposit/transfer observations changed cost; the other 41 remain
unchanged. The final source/bytecode identity check above qualifies reuse of these
measurements after test consolidation. Reproduction uses the recorded production
snapshot with that checkpoint's tests in a separate checkout.

| Template | Deposit gas delta (all retained observations) | Transfer gas delta (all retained observations) |
| --- | ---: | ---: |
| Open | +396 to +398 | +379 to +425 |
| Fixed | +228 to +230 | +210 to +257 |
| Periodic | +107 to +119 | +99 to +146 |

The measured boundaries retain M1's isolated direct calls versus nested real
market calls. For example, a locally blocked canonical-wrapper entry changes
from 4,348 to 4,757 gas for open, 4,559 to 4,800 for fixed, and 4,846 to 4,976
for periodic. The periodic cached repeat-deposit scenario changes from 11,499
to 11,616 gas. These are callback costs, not whole-transaction fee estimates.

The same traces also contain 37 comparable transfer-policy query calls, which
increase by 756–817 gas versus M2-02. The optimized compiler output shows the
shared registration helper allocating/decoding the six-field memory view,
including two discarded zero-initialized allocations, before checking the
registered flag. It loads the packed configuration once and does not fetch
open/fixed's separate deposit-dispatch mapping. The transfer processor also
retains an internal helper call. These memory/helper costs explain the increase;
the empty feature checks disappear from the three built-in artifacts. Relevant
IR is retained as `m2-03-<Template>-action-ir.txt`. These measured costs are an
explicit review tradeoff; no gas improvement is claimed from source sharing.

### M2-03 evidence identities

Paths are relative to the same ignored M2 evidence root. Receipt files retain
exact commands and log hashes. The gas input manifest/snapshot and final input
manifest are distinct; the review receipt binds both and the staged patch.

| File | SHA-256 |
| --- | --- |
| `m2-03-inputs.sha256.json` | `de59f4c17528500c51fbe221810fef94199cb0f97d3ed000c0e78bab09493abd` |
| `m2-03-test-receipts.json` | `a18f832cb027d11f7a96b05f21bc7f8d026b77564f89bd5e8cbfb685f703d454` |
| `m2-03-abi-comparison.json` | `7c4cb9f4d2b68e60443d7c2683be303871295e9a716014bfb6a4caeaa400fe4d` |
| `m2-03-storage-comparison.json` | `7ac3d03e8187cfa26198d979dabe817c774cc7648983a39296061052194f2b2a` |
| `m2-03-sizes.json` | `ba481ffb17f025daaa52be68b3f76caf388d7213bf568787b438f9efaca13825` |
| `m2-03-gas-receipts.json` | `4b28e68a37b201121cb6409e0bed5b29d42203402b03ab4d5737cf2c6d7418df` |
| `m2-03-gas-comparison.json` | `77d2013dea69567f2657b1d4b982c2fe9bfb8144c2468d96b3e2555b654fbbf6` |
| `m2-03-view-gas-comparison.json` | `f10deced870d0153a826371edc38495c0d9760d890a1f84543ad521ca2e23312` |
| `m2-03-lint-receipts.json` | `cdab75a70438f047548a3e6c552231383e128219e4871a9a1b7d1d570c8531a0` |
| `m2-03-test-migration.json` | `c9324ddf852230131210335578f5c1df6452d24021ac9f3d368712ed57573876` |

The user accepted this staged Solidity diff and authorized M2-04. The voice guide,
reference PDF, and lifecycle sketch remain untracked and excluded.

## M2-04: Queueing, closure coordination, and empty callbacks

Status: accepted and committed as `95a2912e2398c368a929cb016e93abb24dddf408`,
with a verified kethcode SSH signature. The approved Solidity patch matches the
commit; `m2-04-acceptance.json` records approval and verification.
Parent checkpoint is `6859b70720a7755eef6010d67a3dd55cf2b0638b` (M2-03).
The user reviewed this checkpoint and authorized its commit and continuation.
The existing Solidity review rule applies to the next checkpoint.

### Shared coordinators and retained term behavior

[BaseHooks](../../src/access/BaseHooks.sol) now owns queue coordination:
registration, schedule, withdrawal access, then the additional queue check.
The default access processor retains known-lender exemptions and credential
caching without recording market entry. Its early return stays inside that
processor, so an additional check is still reached. Open always requires access
when this callback is invoked; fixed and periodic use their stored requested
access setting. Fixed checks maturity before access, including when the supplied
market state is closed. Periodic checks its existing windows unless either the
market state or hook configuration is closed; access still applies afterward.

Closure runs separate validation and effects. Open inherits empty, unguarded
defaults. Fixed retains its registered-market check and the OR between its two
early-close permissions, then updates the same maturity and emits the same
event. Periodic retains registration, sets its closed flag, cancels any pending
APR proposal, then emits closure. These term bodies remain in their concrete
owners, exposed through named validation/effect helpers for later composition.

The six empty callbacks now each have one shared external entry and an empty
virtual internal check. They retain their existing lack of authentication and
policy effects, including ungated execution of already queued withdrawals.
The protocol-fee callback keeps its memory state argument; the others retain
calldata. No callback flag changes. Markets still select batches and expiry,
perform accounting, and reset APR/reserves on closure. Closure invokes no new
APR callback and does not clear hook-owned temporary reserve state.

### M2-04 test ownership

| Property | Current owner |
| --- | --- |
| Registration before queue scheduling/access | Existing shared unregistered-market case, extended to queueing. |
| Credential resolution/cache, deposit blocks, no known-state write, revoked credentials | `BaseHooksTest.test_onQueueWithdrawal_ValidatesCredentialsWithoutMarkingKnown`, across all three production artifacts. |
| Market-local known-lender exemption, provider removal, requested gating, open direct-call behavior | `BaseHooksTest.test_onQueueWithdrawal_PreservesKnownAccessAndRequestedGating(bool)`. |
| Six empty callbacks, unknown/registered callers, no writes/events, open closure | `BaseHooksTest.test_emptyCallbacks_StayUnguardedAndHaveNoEffects(bool,bytes)`, before fixed maturity/periodic windows with a blocked lender. |
| Active temporary reserve state survives open/fixed closure callbacks | `BaseHooksTest.test_onCloseMarket_DoesNotClearTemporaryReserves`. |
| Fixed maturity priority, boundary, permissions, maturity update/event | Concrete fixed queue and closure cases; credential mechanics moved to the shared owner. |
| Periodic window priority/boundaries, both closed flags, access after closure, proposal cancellation/event order | Concrete periodic queue/window/closure cases. |
| Market-owned APR/reserve reset, funded closure, pending/unpaid batch settlement, withdrawal dispatch | Existing `WildcatMarketTest`, production matrix, and dispatch suites; no market/test implementation changes. |

Four shared cases replace the copied queue/no-op assertions. Concrete cases
retain the distinct term checks, and the open APR case retains its unregistered
caller behavior. The access subtree remains at 136 test entrypoints, including
the existing overloaded access-control test. Shared fixtures have no test
entrypoints. The migration inventory records removed, added, and renamed cases.

### M2-04 verification

| Check | Result |
| --- | --- |
| Default profile: M2-03's focused suites plus `WildcatMarketTest`, seed `0x5eed` | 308 passed / 16 suites; zero failures/skips. |
| Deployment profile: same selection and seed | 308 passed / 16 suites; zero failures/skips. Real standard/revolving lifecycle, factory deployment, wrapper, batching, and closure paths pass. |
| ABI comparison against M2-03, retaining M1's compatibility contract | Encoded surface unchanged. Only previously unnamed top-level queue/closure/empty-callback inputs gain labels: 20 each for open/fixed, 24 for periodic. Existing names, tuple fields, errors/events, selectors, and mutability match. Raw exports and allowed differences are retained. |
| Compiler storage layouts | Identical to M1/M2-03 after ignoring compiler IDs. No new production state; each packed market configuration remains one slot. |
| Measurement identity | Final production source matches the gas snapshot; default, deploy, and gas-measurement ABI/creation/runtime bytes match. Final inputs, all 897 baseline dependency files, submodules, effective settings, and tool hashes verified. |
| `yarn lint:check` | Exits 1 for the same 34 untouched formatting paths; no new failure. |
| Standalone Solhint | Exits 0 with the same 22 warnings. Both lint logs are byte-identical to M2-03. |

These are checkpoint checks. Full milestone qualification remains M2-06.
Build settings, dependencies, market accounting/batching, and tranching policy
remain unchanged.

### M2-04 size and gas comparisons

| Template | Runtime bytes | Creation bytes | `STOP + creation` | Stored-initcode headroom | Runtime/creation delta from M2-03 | Delta from M1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Open | 15,587 | 18,313 | 18,314 | 6,262 | +31 / +31 | +283 / +283 |
| Fixed | 16,933 | 19,660 | 19,661 | 4,915 | +69 / +69 | +332 / +332 |
| Periodic | 19,751 | 22,478 | 22,479 | 2,097 | +230 / +230 | +480 / +480 |

Runtime, stored-initcode, and factory constructor-payload limits remain satisfied.
Periodic remains the tightest deployment limit.

Measured before consolidating this task's tests, with unchanged fixtures from
`6859b70`, M1's timestamp/seed, and the same direct/nested call boundaries.
The recorded commands pass 11 selected tests plus the cached-deposit scenario.
There are 61 comparable M1 callback observations, including all 19 queue/closure
observations; their arguments and return/revert results match. The other 36 M1
observations came from action tests removed in M2-03 and are not claimed as new
M2-04 measurements. Their prior evidence remains intact. The 42 retained calls
outside queue/closure have unchanged costs from M2-03.

| Template | Queue observations / gas delta | Closure observations / gas delta |
| --- | --- | --- |
| Open | 3 / +421 to +517 | No M1 closure observation; empty behavior checked in the shared suite. |
| Fixed | 5 / -2,073 for ungated queueing; +305 to +400 otherwise | 4 / -70 to +166 |
| Periodic | 4 / +761 to +862 | 3 / -85 to -8 |

These deltas are the same against M1 and M2-03 because those callbacks had not
yet moved. They describe measured callback costs, not whole-transaction fees.
Fixed's ungated case drops from 29,731 to 27,658 gas: the shared processor checks
the access flag before loading lender status, avoiding the old unconditional
read. For comparison, the periodic known-lender case rises from 32,529 to 33,332.

The optimized IR shows the shared access adapter's memory allocation/decoding
and helper calls. Fixed/periodic scheduling rereads the packed slot after
registration, making that second read warm. Periodic also decodes its full
schedule struct. These costs explain the queue increases; no new storage slot
or deposit-dispatch read is introduced. Fixed closure keeps separate validation
and effect phases, with a warm maturity reread; periodic retains its flag and
proposal writes. Relevant IR is retained as `m2-04-<Template>-queue-close-ir.txt`.
Empty feature checks compile away in the built-in templates. These measured
costs and size increases are explicit review tradeoffs of the shared seams.

The gas input manifest/snapshot is separate from the final consolidated-test
manifest. Reproduction uses the retained production snapshot with `6859b70`'s
tests in a separate checkout. Final source and executable identity qualify the
gas measurements after test consolidation.

### M2-04 evidence identities

Paths are relative to the ignored M2 evidence root above. The run directory's
date identifies the milestone run; this task's final checks ran on 2026-09-23.
Receipts retain exact commands and log hashes. The review receipt binds the
staged patch/files, manifests, compatibility comparisons, and raw evidence.

| File | SHA-256 |
| --- | --- |
| `m2-04-inputs.sha256.json` | `b6265c6447705c716d40984f249c7812146901ae5295c67e1a9119a939fab024` |
| `m2-04-test-receipts.json` | `dacd0cd6c009f922b06190066800572fc4eb5cb9fc121c104f4067fab29a21f7` |
| `m2-04-abi-comparison.json` | `0160721b96c17a6f2cb96604b1a45e12c411219051e7991c9638477b9ce393ea` |
| `m2-04-storage-comparison.json` | `dab0315457663c8c1b885ad0f53e8ec4a0e70445b72526842da559c1f22bcf9c` |
| `m2-04-sizes.json` | `5250eb5f39a7ebefdd09e4a09f600f6e5df43c232c5a4581bc074e8d5b10611f` |
| `m2-04-gas-receipts.json` | `0bdf7d2f6a27fda5d31ddaae17db271dc7fe95db3602cecbc905ca12b84352d5` |
| `m2-04-gas-comparison.json` | `a024490b543d7695da079d9b230c5d270d5dd4ba7f6e898fef3d1f6e6f339ff7` |
| `m2-04-lint-receipts.json` | `d158e3a704a62d33229ff3deb9ae77131c8628466e6557510bae5caad8f15011` |
| `m2-04-test-migration.json` | `4dcb6bc10e30616a495d3ef6f825247276ff0049342cdde6ca3d594126578eaf` |
| `m2-04-qualification.json` | `4b7f0b931267af7d187eb0447c482db7099c6611ea28f673d9eb173eb4daa4f7` |
| `m2-03-acceptance.json` | `9c562f6dfc2c0f2b437f9cdd247f21f33e5b49550e537c6ba8988a898e837fc5` |

The user accepted M2-04 and authorized M2-05. M2-05 and M2-06 have not started
at this checkpoint. The voice guide, reference PDF, and lifecycle sketch stay
untracked and excluded.

## M2-05: APR strategy and both periodic execution routes

Status: accepted and committed as `549bfaa8d01e27f30dca97b5858f5e8f22d75937`,
with a verified kethcode SSH signature. The approved Solidity patch and file
hashes, including the revised comments, match the commit; `m2-05-acceptance.json`
records the verification. Parent checkpoint is
`95a2912e2398c368a929cb016e93abb24dddf408` (M2-04). The user authorized the
commit and continuation to M2-06.

### APR ownership and validation

[MarketConstraintHooks](../../src/access/MarketConstraintHooks.sol) owns the
existing calculation as `_applyDefaultAprUpdate`, a virtual internal strategy.
Its calculation, temporary state, and event logic have not been duplicated or
rewritten: the moved function body has identical non-comment tokens.
[BaseHooks](../../src/access/BaseHooks.sol) owns the external coordinator. It
runs `_applyAprUpdate`, constructs `AprChange` with requested and effective
values, runs `_checkAprChange`, and returns the selected pair. The check is an
empty non-view extension point; a rejection rolls back the selected strategy's
state and events.

Open uses the default strategy. Fixed calls its named `_validateFixedAprUpdate`
primitive before that same default. These callbacks retain their existing
unguarded caller behavior. A feature can replace the default calculation while
retaining fixed's guard; replacing the outer strategy owns that integration.

Periodic retains explicit strategy selection. It authenticates the market,
cancels a pending proposal only on an increase, and invokes the default for
increases/equality. A reduction invokes `_executePeriodicReduction`, preserves
the current reserve ratio, and skips the default entirely. The renamed proposal
helper's body also has identical non-comment tokens, preserving check order,
deletion, and the execution event. Proposal management and closure are unchanged.

Both periodic reduction routes share that helper and `_checkAprChange`. The
dedicated route keeps its APR-only ABI and passes `AprRoute.PendingReduction`,
the proposal APR, and current reserves as both requested/effective reserves.
Its callback data is an empty calldata slice even if extra bytes follow the
encoded state. Ordinary calls pass `AprRoute.Ordinary` and the original data.
The validator cannot return a replacement pair. Competing calculations still
require explicit integration; this adds no automatic composition rule.

### M2-05 test ownership

The existing constraint suite remains the owner of bounds, rounding, reserve
calculation, expiry, and cancellation mathematics. Fixed and periodic suites
retain maturity/proposal timing, failure order, and term-specific effects.
Open's unregistered APR callback case moved to `BaseHooksTest` and now covers
fixed as well. No parallel calculator or legacy implementation was retained.

[AprValidationTest](../../test/access/AprValidation.t.sol) adds five focused
cases using [AprValidationHooks](../../test/mocks/AprValidationHooks.sol), a
test-only periodic derivative that overrides only the additional validator.
Its APR floor/reserve ceiling and accepted-change record prove:

- Both reduction routes supply the applied values, original state, market,
  route, and appropriate callback data; ordinary requested reserves may differ.
- Rejection by either constraint restores the proposal, which can then be
  executed successfully after relaxing the constraint.
- Periodic reductions leave both empty and seeded temporary-reserve state
  untouched and emit only the proposal execution event.
- A rejected increase restores its cancelled proposal. Accepted increases
  validate effective reserves even when requested reserves exceed the ceiling.
- Equality can expire temporary reserves and validate the restored ratio;
  rejection restores temporary state, and equality retains the proposal.
- The dedicated route supplies empty data even with trailing calldata.

The probe seeds temporary state through a test-only helper to make an accidental
default calculation observable. It does not replace either production strategy.
Broader replacement/composition proofs remain M4 work. The access subtree grows
from 136 to 141 test entrypoints; shared fixtures still have none.

### M2-05 verification

| Check | Result |
| --- | --- |
| Initial focused default run: shared, APR probe, constraint, and term suites, seed `0x5eed` | 65 passed / 6 suites; zero failures/skips. |
| Broader default run: M2-04's selection plus APR probe and borrower-account compatibility, same seed | 317 passed / 18 suites; zero failures/skips. Includes actual market APR/liquidity rollback, both standard/revolving periodic execution, factory, dispatch, and delegated borrower paths. |
| Deployment profile: same broader selection and seed | 317 passed / 18 suites; zero failures/skips. |
| Raw ABI comparison | All three concrete ABIs exactly match M2-04. No additional label changes; M1's previously documented naming allowance still applies. |
| Compiler storage layouts | Identical to M1/M2-04 after ignoring compiler IDs. No new production state; packed market/proposal layouts are unchanged. |
| Moved calculation and proposal execution | Bodies have identical non-comment tokens to M2-04. |
| Measurement identity before comment review | Default, deploy, and gas artifacts have identical ABI/creation/runtime bytes. All 279 tested inputs and 897 baseline dependency files verified; submodules, tools, and effective settings match M2 start. The later review amendment below preserves all non-comment tokens and retains these original receipts. |
| `yarn lint:check` | Exits 1 for the same 34 untouched formatting paths; no new failure. |
| Standalone Solhint | Exits 0 with the same 22 warnings. Both lint logs are byte-identical to M2-04. |

These are checkpoint checks; full milestone qualification remains M2-06.
Build settings, dependencies, market accounting, deployment inventories, and
tranching policy are unchanged.

### M2-05 size and gas comparisons

| Template | Runtime bytes | Creation bytes | `STOP + creation` | Stored-initcode headroom | Runtime/creation delta from M2-04 | Delta from M1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Open | 15,653 | 18,379 | 18,380 | 6,196 | +66 / +66 | +349 / +349 |
| Fixed | 17,014 | 19,741 | 19,742 | 4,834 | +81 / +81 | +413 / +413 |
| Periodic | 19,949 | 22,676 | 22,677 | 1,899 | +198 / +198 | +678 / +678 |

Runtime, stored-initcode, and factory constructor-payload limits remain satisfied.
Periodic remains the tightest limit.

Measured before changing tests, with unchanged `95a2912` fixtures and M1's
timestamp, seed, and call boundaries. The commands pass eight selected tests
plus the cached-deposit scenario. All 22 M1 APR observations remain comparable:
17 ordinary calls and five dedicated periodic calls. Their arguments and
return/revert results match. There are 47 comparable callbacks overall; the
other 50 M1 observations came from previously consolidated tests and are not
claimed as new measurements. Earlier evidence remains intact.

| Template / route | Successful-call delta from M2-04 | Rejected-call delta from M2-04 |
| --- | ---: | ---: |
| Open ordinary | +260 to +263 | No rejection in the retained gas scenarios. |
| Fixed ordinary | +278 to +281 | +6 |
| Periodic ordinary | +288 | +6 |
| Periodic dedicated | +702 | +111 to +126 |

These APR deltas are also relative to M1 because those callbacks had not moved
before this task. Periodic dedicated success rises from 34,616 to 35,318 gas;
ordinary reduction rises from 36,078 to 36,366. These are callback costs with
their recorded boundaries, not whole-transaction fees.

Optimized IR retains allocation/population of the six-field `AprChange` even
when the built-in validator is empty. Dedicated execution also reads reserves
and constructs the empty calldata slice; these values were unnecessary on its
old APR-only path. The compiler additionally factors the 192-byte memory
allocation into a shared helper in open/periodic. That adds 81 gas to 15 retained
deposit/transfer/queue observations despite those source bodies being untouched.
The remaining ten non-APR observations have unchanged costs. Before/after IR is
retained as `m2-05-<Template>-apr-ir-04.txt` and `...-05.txt`.

Gas and final test inputs have separate manifests. A single production comment
was wrapped after the gas run to avoid adding a line-length warning; the exact
comment-only amendment is recorded. The compiled default/deploy ABI and executable
bytes match the gas artifacts. These measurements precede the review comment
revision below; its source equivalence is recorded separately.
Reproduction uses the retained production snapshot with `95a2912`'s tests in
a separate checkout. These cost/size increases are explicit review tradeoffs.

### M2-05 evidence identities

Paths are relative to the ignored M2 evidence root above. Receipts retain exact
commands and log hashes; the review receipt binds staged files and the Solidity
patch to the final inputs, gas inputs, and raw comparisons. Earlier evidence
has not been overwritten.

| File | SHA-256 |
| --- | --- |
| `m2-05-inputs.sha256.json` | `e96e3d9d5effcf474f7232fbad0e04b4338265e8b7c29d26dd9286c24dcbe572` |
| `m2-05-test-receipts.json` | `5586ad27c158a946d30bfe2bb24857250ccfe41e223a49ea320df68720b74be8` |
| `m2-05-abi-comparison.json` | `3bb15b9941a4e6378035268b9f41c86da714aee8f3ffe0604d49063358ab0e3c` |
| `m2-05-storage-comparison.json` | `3b6834c5015b944e5023b7df811d4fa6ed25536f5e2e361ee83311d3945dad69` |
| `m2-05-sizes.json` | `d14f03e1cfc3bc7941469d966f373630b4e50b7a66d407663ba7f4a8b50573dc` |
| `m2-05-gas-receipts.json` | `43bff6f977ef9241a0a6228ef9b3b5e3caec4edb83abb1b33dcdbfd19bd8b75c` |
| `m2-05-gas-comparison.json` | `d2e092511ce35513313504cf39d1c6d9a99c8b241bc9a7219ec3e21a2990af8c` |
| `m2-05-gas-source-qualification.json` | `f46b70a297ec82ddcd1a883a7dfc7deb76838bed9e1862cc2dd245a2489d3cfb` |
| `m2-05-moved-body-comparison.json` | `82bb891dbb6f90b2d63186d205a60d0ed9338492fe997a10473127fd114439aa` |
| `m2-05-lint-receipts.json` | `fbbd741be087f5252977fe87a72d7f68479a648ad173c6e0a0d2813c59bbc58f` |
| `m2-05-test-migration.json` | `1964e89097667543b3c531940a246dee4344241346cad74a76115af145ccdc42` |
| `m2-05-qualification.json` | `63b8c0b9b0df3e65817533c025fa25709f598ae7334ab831f07bde3aced31269` |
| `m2-04-acceptance.json` | `b90dca7c1765b4ff08fc8698688ad959d726d66450fc7f97e8aa8a34030e457f` |

### M2-05 comment review

The user clarified that applying the voice guide must preserve technical terms,
function/variable names, and existing branch explanations. Restored the inline
fixed-term revert comment and revised APR comments in `BaseHooks`,
`FixedTermHooks`, `MarketConstraintHooks`, and `PeriodicTermHooks` accordingly.
The comments now name the override points, proposal/reserve state, and expiry
conditions instead of replacing them with phrases such as "selected default."

All nine staged Solidity files have identical non-comment lexer tokens to the
tested versions. Formatting passes; Solhint output is identical to the existing
22-warning baseline. Tests and compilation were not repeated for comment edits.
The original test/build/gas receipts and input manifests remain intact; the
previous review sources, patch, and receipt are retained separately. The current
review receipt binds the revised source hashes through this amendment.

| File | SHA-256 |
| --- | --- |
| `m2-05-comments-inputs.sha256.json` | `7c7bb28ef762e072f2f93df56df37683eff0ae43e311569b4bec948a2af5f8a7` |
| `m2-05-comments-receipt.json` | `a213907c73fb18447f746151962f229fe096f7adf150faec4cb79f98fc1a64e6` |

The user accepted M2-05 and authorized its signed commit and M2-06 qualification.
The voice guide, reference PDF, and lifecycle sketch remain untracked and
excluded from the checkpoint.

## M2-06: Qualification and M3 handoff

Status: complete against `549bfaa8d01e27f30dca97b5858f5e8f22d75937`.
This checkpoint changes documentation only. No further Solidity changes or
additional canonical tests were needed. M2 is ready for the user's milestone
review and push; M3 planning has not started.

### Final verification

Ran the required commands on the completed M2 source, including the accepted
comment revisions. The 279 source/test/script/settings inputs and 897 dependency
files match their manifests. Forge/solc binary hashes, submodules, and effective
default/deploy settings match the M1 qualification. Compiler source metadata
matches the current files; default, deploy, and final gas artifacts have
identical concrete-template ABIs and executable bytes.

| Command | Result |
| --- | --- |
| `forge test` | 707 passed / 51 suites; zero failures or skips. |
| `yarn test:fixed` | 707 passed / 51 suites; zero failures or skips. |
| `FOUNDRY_PROFILE=deploy forge test` | 707 passed / 51 suites; zero failures or skips. |
| `yarn lint:check` | Exit 1: the same 34 untouched formatting failures; no new failures. |
| Standalone Solhint, using the package script's arguments | Exit 0: zero errors, the same 22 warnings; output identical to M2-01. |
| Prettier on all 17 Solidity paths changed during M2 | Pass. |

The invariant campaign retains all nine properties, 2,000 runs and 60,000
handler calls per full run. Foundry reports that campaign as one test. Source
entrypoints therefore number 706 at M1 and 715 at M2, while reported suite totals
are 698 and 707. The net increase of nine is four transfer-extension cases and
five APR-validation cases. Construction/action consolidation and new boundary
checks otherwise balance; the access subtree changes from 132 to 141 entrypoints.
Three new concrete owning suites account for the increase from 48 to 51 suites.

### Final implementation and test ownership

The shared function inventory confirms one production implementation of each
moved coordinator/default, with no old concrete copy retained. Credential
resolution still has its existing `BaseAccessControls` owner. APR/reserve
mathematics and temporary-reserve state still have their existing
`MarketConstraintHooks` owner. Packed configuration remains owned by each
template; adapters expose it without a second stored representation.

| Behavior | Final owner and protecting tests |
| --- | --- |
| Construction, creation ordering, access/dispatch flags, minimum management | `BaseHooks`; the first twelve `BaseHooksTest` cases exercise all three production templates, plus the configuration probe. Concrete suites retain distinct term decoding, widths, permissions, schedules, and public tuples. |
| Deposits, transfers, and transfer-policy queries | `BaseHooks` coordinators/defaults; six common lender-action/view cases cover registration, rounding, blocks, credential effects, exemptions, and read-only queries. `BaseAccessControlsTest` remains the provider/cache/wrapper-resolution owner. |
| Withdrawal access and empty callbacks | `BaseHooks`; common queue cases preserve known-lender access and credential effects without marking lenders known. The no-op matrix preserves unguarded caller behavior. Fixed/periodic suites retain maturity/window/closed-state ordering. |
| Closure | Shared validation/effect coordination in `BaseHooks`; fixed/periodic suites own their different permissions, maturity/closed-state writes, proposal cancellation, and events. The common closure case preserves temporary-reserve state. |
| APR selection and effective-value validation | `BaseHooks` coordinator/check; `MarketConstraintHooksTest` owns the default calculation. Fixed/periodic suites retain their guard/proposal state machines. The shared unregistered-caller case covers open/fixed; five `AprValidationTest` cases cover both periodic routes, unchanged reserves, data, skipped default effects, and rollback. |
| Additional transfer rule | Four `HookExtensionsTest` cases cover acceptance/rejection, credential and known-state rollback, known/wrapper exemptions, and market scope. These remain test-only features. |

`test/shared/` and `test/mocks/` declare no test or invariant entrypoints.
Moved assertions have concrete owning suites, rather than inherited copies.
The per-task migration maps and `m2-06-test-migration.json` retain the removed
and replacement entrypoints; historical test counts alone are not the coverage
argument.

The full runs also exercise the existing integrations. `ProductionMatrixFixture`
stores the current templates' actual initcode and deploys them through both
production factories. Matrix scenarios, economics, borrower-account tests,
and invariants use that fixture across standard/revolving markets. Factory and
administrator-transfer suites exercise real deployment/authority paths; the
latter uses open hooks, complemented by configuration/authority cases in all
three template suites. Lens core/facade/aggregator tests retain real tuple and
dispatch consumers. Wrapper integration uses the current hook artifacts and
production markets; the production matrix supplies the full factory path.
`HookDispatchTest` separately keeps its argument-recording hook mock to verify
market callback boundaries. These checks remain in their existing suites.

### Final compatibility, deployment size, and gas

The three raw ABIs equal M2-05. Against M1, the only differences are names for
previously unnamed top-level callback inputs: 24 open, 24 fixed, and 28 periodic
input positions. Raw diffs are retained. Existing names, selectors, tuple
fields/widths, errors/events, constructors, and mutability are unchanged.
Canonical metadata/configuration tests preserve callback masks, family strings,
and periodic `templateVersion() == 2`. Fresh storage-layout exports equal M1
after removing compiler-generated IDs.

| Template | Runtime bytes | Creation bytes | `STOP + creation` | Stored-initcode headroom | Runtime/creation delta from M1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Open | 15,653 | 18,379 | 18,380 | 6,196 | +349 / +349 |
| Fixed | 17,014 | 19,741 | 19,742 | 4,834 | +413 / +413 |
| Periodic | 19,949 | 22,676 | 22,677 | 1,899 | +678 / +678 |

Runtime and stored-initcode remain below 24,576 bytes. Factory creation with
empty constructor `args` occupies 18,475 / 19,837 / 22,772 bytes respectively,
below the 49,152-byte initcode limit. These measurements accompany passing
real-factory deployment tests. New bytecode hashes are recorded in
`m2-06-sizes.json`; deployment inventories are unchanged.

Replayed the original gas commands in a separate temporary checkout with the
final production tree and the three archived concrete access fixtures from
`9d52fe0`. Other test files use the final tree. The archived fixtures remain
outside the canonical suite. Source manifests, commands, settings, and artifact
identity checks bind the replay to the final contracts. All 97 original M1
callback observations retain the same arguments, return/revert results, and
direct/nested boundaries. All 47 measurements retained at M2-05 reproduce
exactly; this replay also restores the observations lost from later traces
when tests were consolidated.

| Template | Deposit delta | Transfer delta | Queue delta | Closure delta | Ordinary APR delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| Open | +477 to +479 | +460 to +506 | +502 to +598 | No M1 observation; behavior tested | +260 to +263 |
| Fixed | +228 to +230 | +210 to +257 | -2,073 to +400 | -70 to +166 | +6 to +281 |
| Periodic | +188 to +200 | +180 to +227 | +842 to +943 | -85 to -8 | +6 to +288 |

Ranges include the recorded success/revert paths and preserve each observation's
measurement boundary; they are not whole-transaction fee estimates. Dedicated
periodic APR execution adds 702 gas on success and 111–126 on rejection. Fixed's
ungated queue saves the old unconditional lender-status read. Other deltas
reflect the access-view allocation/decoding, explicit helper calls and warm
schedule rereads, and the retained `AprChange` allocation described in M2-02
through M2-05. The compiler's shared allocation helper accounts for the final
81-gas increase on affected open/periodic lender actions. These are the reviewed
cost tradeoffs of the shared extension points.

The same traces provide 70 additional comparisons: 30 creation calls, three
live-minimum updates, and 37 transfer-policy queries. Creation adds 607–738 gas
for open, 559–630 for fixed, and 486–647 for periodic. Setting/clearing the
periodic live minimum adds 1,156/956 gas; its unauthorized path is unchanged.
Queries add 777–898 gas. These include the adapter/allocation work discussed
above, without another persisted configuration mapping. For creation comparisons,
changed hook-instance address bits are recorded separately; all 96 configuration
bits match, as do address zero-byte counts. Nine additional periodic creation
calls with changed mock-market addresses are excluded from the comparison.
None of those exclusions affects the original 97 callback observations.

### M3 handoff

M2 establishes shared behavior and the first extension checks. It does not yet
prove general multi-policy composition or future tranching compatibility.
After the user reviews and pushes M2, prepare M3's plan/tracker around the
existing [M1 design](hook-refactor-m1-design.md) and these remaining changes:

| Component | Remaining M3 work and protection |
| --- | --- |
| `FixedTermPolicy` | Move fixed packed configuration/dispatch ownership and its single initialization, maturity, queue, APR-guard, closure, and setter implementations out of the concrete hook. Add empty `_validateFixedTermChange` and `_afterFixedTermChange` defaults at the specified setter boundaries, preserving authority, equal-time/reduction rules, write/event order, and rollback. Fixed tests, shared matrices, production queue/APR/closure scenarios, and the final size/gas measurements protect the move. |
| `PeriodicTermPolicy` | Move periodic configuration, pending proposals, schedule/window helpers, closure, proposal management, APR strategy, and dedicated execution API into one reusable owner. Add `_checkPeriodicProposal` after existing validation/window calculation and before cancellation/write/proposal events. Both execution routes must still reach `_checkAprChange`; reductions must still skip `_applyDefaultAprUpdate`. Periodic state-machine/boundary tests, `AprValidationTest`, and real-market scenarios protect those paths. |
| Concrete templates and public types | Keep concrete constructors, family/revision identity, and public tuple adapters. Move/re-export types only as needed to avoid policy/concrete import cycles; preserve current named imports and ABI `internalType`/tuple layouts. Adjust qualified error/event references to their declaration owner without changing selectors. Open's packed adapters stay in `OpenTermHooks`; no separate open schedule component is required. |
| Explicit integration choices | Retain named fixed/periodic validation/effect helpers and comments that name functions, variables, skipped defaults, and state/events. Resolve overlapping overrides deliberately in the final composition. No runtime policy stack or capability-ownership flag scheme is introduced. |

Keep the same creation/authentication order, access versus dispatch distinction,
credential exemptions, queue schedule/access order, and closure semantics.
Closure still uses the market's direct APR/reserve reset and does not invent
an APR-validation callback. Recheck actual template deployment and periodic's
1,899-byte stored-initcode headroom as term code moves. Keep the staged Solidity
review requirement for every implementation checkpoint.

M4 still owes three-/four-policy compositions, overlapping checks, independent
feature state/APIs across markets, deliberate default replacement and absence
of skipped effects, unused-callback activation, exemptions, lifecycle paths,
and rollback. M5 still owes final compatibility/performance/deployment
qualification and contributor guidance. Tranching economics, repayment/default
policy, and market batching/accounting changes remain outside this refactor.

### M2-06 evidence identities

Paths are relative to the same ignored evidence root. The command receipts bind
all full-run log hashes; gas receipts bind both replay logs. `m2-06-qualification.json`
records their reconciliation, with detailed environment, compiler-source,
integration-suite, and implementation-ownership records alongside it. Raw M1
and earlier checkpoint evidence remains intact.

| File | SHA-256 |
| --- | --- |
| `m2-06-inputs.sha256.json` | `7c7bb28ef762e072f2f93df56df37683eff0ae43e311569b4bec948a2af5f8a7` |
| `m2-06-command-receipts.json` | `5c8ae0161a311321f9248ba0221abb3f37417877b50d29bd29367cb4e78f3378` |
| `m2-06-verification.json` | `6883c2dc57f0ee4b34f2d7c0bf71fb2e29368abc8610adccb5fcd1de78ea0713` |
| `m2-06-test-migration.json` | `a92d8e760e34903af5de7743f8706cee36131153ff8cc3f7bbbfc83e4ddb58fd` |
| `m2-06-implementation-ownership.json` | `3dab868fb48cdd41715437f12e0836cacd2d757df767904e63c79e33ca8299ca` |
| `m2-06-abi-comparison.json` | `bdaa6a571e58d3436b88792cbbcb9d5e153d574601bcaf35c49565e299260819` |
| `m2-06-storage-comparison.json` | `184850bb94b2170fe1b614e8dbbd67afd066fd8e06f85fabfa8210ecaaeff1fe` |
| `m2-06-sizes.json` | `dcee308f64dbb56f047f9e409327c8edfd91af65d85bb581e6e89a3ea493daba` |
| `m2-06-gas-identity.json` | `e2a3f06980f648c4fd7bae846ea7d19f0b035beb47926ece1b095b0d01393e5a` |
| `m2-06-gas-receipts.json` | `f23fdae2490021267b54584493a82c49ed58a91926e35de6100b80e4d66eb0c7` |
| `m2-06-gas-comparison.json` | `c29a39d9da67bb27eaa840eda5371f2e5265d71de5094e8febc2ca4d75351a52` |
| `m2-06-creation-minimum-view-gas.json` | `617467cd14038dd3956718cb341837fcb0e43d39b82f8c55b8ef5671951eed69` |
| `m2-06-qualification.json` | `f18a4e58013de18984c7c656bf6133254293e22028dd680d0637a9ea290d125d` |
| `m2-05-acceptance.json` | `db4d235362b1e76e2167a2a0efcd0349861cf23c186d776181b6105380398289` |

The voice guide, reference PDF, and lifecycle sketch remain untracked. Nothing
has been pushed; milestone acceptance and push remain with the user.

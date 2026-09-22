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

## Remaining implementation evidence

M2-02 through M2-06 are pending. No shared implementation, new runtime test,
post-refactor ABI/size/gas result, or M3 handoff is claimed by M2-01. The lint
baseline is characterized; no source, toolchain, or design blocker prevents
the first implementation checkpoint.

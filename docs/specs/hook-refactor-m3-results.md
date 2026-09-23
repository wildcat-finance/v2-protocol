# M3 results: reusable term policies

- Plan: [M3 execution plan](hook-refactor-m3-plan.md).
- Current status: [M3 tracker](hook-refactor-m3-tracker.md).
- Execution starting revision: `25d38d016f8884d24dced6a9e1c320e5bed5cc34`.
- Approved M2 handoff: `c54e57312e63ceadee88492d8c47ae632b876b0b`.
- References: [M1 design](hook-refactor-m1-design.md),
  [M1 baseline](hook-refactor-m1-baseline.md), and [M2 results](hook-refactor-m2-results.md).
- Raw evidence root: `audits/hook-refactor/m3/2026-09-23/` (ignored).

## M3-01: Handoff identity and move inventory

The user approved the plan and authorized execution. The starting tree has no
tracked edits. All 279 source/test/script/settings inputs and 897 dependency
files match the qualified M2 tree. The four submodules are clean and unchanged.
Default/deploy effective settings match M2, as do the Forge 1.8.3 and solc 0.8.25
binary hashes. The repository identity is `kethcode <dave@wildcat.finance>` with
SSH signing enabled; the M2 handoff and M3 planning signatures verify.

Verified the 42 raw artifact hashes bound by M2's qualification checkpoint and
its command/log receipts. Current default/deploy ABIs and executable bytes for
all three templates match the retained M2 gas artifacts. M1 remains the original
behavior/compatibility reference; M2 is the immediate implementation/cost
reference. No Solidity has changed at this checkpoint.

| Prior evidence | Disposition |
| --- | --- |
| M2 default, fixed-seed, deploy runs | Reuse the qualified 707-test / 51-suite results as the starting baseline; not rerun or claimed as new M3 passes. |
| M2 lint | Retain the 34 untouched formatting failures and 22 Solhint warnings. Same inputs/settings/dependencies; no new lint run needed before source changes. |
| Raw ABIs, metadata, packed layouts, sizes | Retain M2 exports and record current artifact snapshots. Periodic stored-initcode headroom is 1,899 bytes. |
| M1/M2 callback, creation, minimum, and query gas | Retain the reconciled 97 original callbacks and 70 additional comparisons with their original fixture identities and exclusions. Reuse only where subsequent executable identity or matching measurements support it. |
| Fixed setter and periodic proposal/replacement costs | Supplemented below using existing canonical tests before source changes. |

### Move and consumer map

| Area | Implementation / consumer treatment |
| --- | --- |
| Fixed policy | Move `_hookedMarkets`, `_depositHookEnabled`, `MaximumLoanTerm`, seven fixed errors, `FixedTermUpdated`, decoding/initialization, adapters, setter, schedule restriction, APR guard/strategy, and closure helpers to `FixedTermPolicy`. Leave one implementation. |
| Fixed concrete and type | Keep constructor/flags, `version()`, and `getHookedMarket(s)` in `FixedTermHooks`. Move the global `HookedMarket` to `types/FixedTermHookTypes.sol` and re-export from the existing concrete file, avoiding a policy/concrete cycle. |
| Periodic policy | Move configuration and proposal state together with schedule validation/queries, management, both execution routes, cancellation, closure, constants/errors/events, and packed adapters. Reuse shared base behavior. |
| Periodic concrete and types | Keep constructor/flags, family/revision, and configuration tuple adapters. Preserve proposal query shapes and one owner for their validation/logic. Move/re-export global configuration/proposal types as needed; account for `IMarketApr`. |
| Fixed error/event qualifications | Four test files need the new declaration owner: `test/access/FixedTermHooks.t.sol`, `test/access/BaseHooks.t.sol`, `test/integration/ProductionMatrixScenarios.t.sol`, and `test/market/WildcatMarket.t.sol`. Only qualifications/imports change in M3-02. |
| Public source imports | Lens `HooksConfigData`/`HooksInstanceData`, concrete suites, and shared fixtures import structs through the existing concrete files. Preserve these imports as compilation checks of re-exports. |
| Deployment consumers | Production fixtures, invariants, wrappers, and `script/deploy/v2-5/05-owner-actions.s.sol` identify concrete artifacts by their existing paths. Keep those paths and external constructors intact. |
| Periodic derivatives and static references | `MarketConfigurationHooks` and `AprValidationHooks` continue inheriting the concrete periodic hook. Periodic test/integration error/event references and `MarketMatrixHandler`'s `abi.encodeCall` target must resolve to their actual owner after M3-04. Preserve the external call encoding. |

The shared access/constraint owners and open template need no separate term
implementation. M3-02/M3-04 relocate existing behavior; M3-03/M3-05 add the
management extension calls. Existing comments move with their code, retaining
technical names, branch explanations, and the fixed APR revert comment.

### Test ownership and identified gaps

| Property | Owner / next action |
| --- | --- |
| Shared construction, registration/access flags, minimums, lender actions/views, withdrawal access, no-ops | Keep `BaseHooksTest` and existing access/constraint owners; all three production templates remain in the runtime matrix. |
| Fixed creation/decode/packing, authority, queue priority, APR restriction, closure permissions/events | Keep the ten cases in `FixedTermHooksTest`, with common/integration coverage in its existing owners. M3-02 changes owner references only. |
| Fixed setter | Existing case covers reduction, extension rejection, disabled reduction, unknown market, and wrong administrator. Equal-time and allowed past-time updates lack dedicated assertions in that case; cover them alongside management extension order/rollback in M3-03. |
| Periodic creation/windows, proposal timing/overwrite/expiry, closure, ordinary and dedicated APR | Keep the seventeen cases in `PeriodicTermHooksTest`, plus the five `AprValidationTest` cases for effective values, skipped defaults, both routes, data, and rollback. |
| New fixed management behavior | Add a small test-only rule/effect to the existing fixed owner in M3-03; demonstrate guard priority, before-write rejection, observing the new maturity, and after-write rollback without copying the setter. |
| New periodic proposal behavior | Add focused proposal-rule cases to the existing periodic owner in M3-05; acceptance/replacement, rejection preserving an existing proposal, exact computed context, and native guard priority. Retain execution checks separately. |
| Production consumers | Continue using existing real factories, lens suites, administrator/borrower-account, wrapper, standard/revolving matrix/economics, and invariants. No parallel integration suite or inherited test entrypoints. |

### Management measurement supplement

Ran three existing tests under the deploy profile at timestamp `1724284800`,
seed `0x5eed`: the fixed setter authority/policy case, periodic proposal rejection
case, and proposal timing/overwrite case. The latter uses one fuzz iteration
solely for a recorded cost scenario; its exact arguments are retained. This is
not a replacement for normal fuzz verification. All three tests passed.

Captured five fixed setter calls and nine periodic proposal calls, with exact
arguments, return/revert results, and isolated top-level boundaries. Fixed term
reduction costs 31,405 gas; its four rejection cases cost 23,820–26,213. Valid
periodic creation/replacement costs 58,661/43,021; seven rejection observations
cost 24,803–33,076. These supplement M2's callback measurements and must retain
their fixture/state/input identity when compared after extraction or extension.

An initial exact-name selector matched no tests because Forge matches signatures;
its zero exit status was rejected as measurement evidence. The corrected selector
and successful discovery/execution are recorded separately. The no-match log and
receipt are retained rather than counted as a pass.

### M3-01 evidence identities

Paths below are relative to the ignored M3 evidence root. The retained M2
qualification receipts remain under their original root.

| File | SHA-256 |
| --- | --- |
| `identity-start.json` | `bb9f5cf6b7961fb9d40e94644593bb480bed9ccb4445b7ae228015ae85664afc` |
| `inputs-start.sha256.json` | `a1f61ef4b85cc0575be25c4d03e3d756b0396dc463bd16d7a848914f85e9700c` |
| `management-gas-baseline-receipt.json` | `4eeb1c88f0aab501d78a34a52296047997e29d9c3c2c8f259fe9ea808bc84981` |
| `management-gas-baseline-calls.json` | `632520b620d3e2784d49b4b4e6f4e95af4dbc8abdf3d753924a4483af3a6ada0` |
| `consumers-start.txt` | `6450afed161649cf8f2ae68d15bdc3e4c16aeaf9736e2f38c544ed127a3ba35e` |

The voice guide, reference PDF, and lifecycle sketch remain untracked and
excluded. This checkpoint is documentation/evidence only under the user's
existing signed-commit authorization; M3-02 retains staged Solidity review.

## M3-02: Fixed policy extraction

Implemented against signed M3-01 checkpoint
`c68f1d9ec5245efbe72d36efc684be0754ad7705`. This checkpoint relocates fixed-term
behavior into `FixedTermPolicy`; it does not add the M3-03 setter extension
calls. Implementation and verification are complete; the user reviewed the
staged checkpoint and authorized its signed commit and continuation.

### Ownership and compatibility

`FixedTermPolicy` now owns the fixed configuration and dispatch mappings,
constant, seven errors, event, decoding/initialization, packed access adapters,
setter, withdrawal schedule, APR restriction, and closure behavior. It inherits
the existing `BaseHooks` implementation without duplicating shared behavior.
`FixedTermHooks` supplies the unchanged constructor and flags, family string,
and public `getHookedMarket(s)` adapters over the policy's authoritative state.

The unchanged global `HookedMarket` struct lives in
`src/access/types/FixedTermHookTypes.sol` and is re-exported through
`FixedTermHooks.sol`. Existing lens, fixture, and test type imports compile
through that original path. The concrete deployment artifact path is unchanged.
The four consumer files identified in M3-01 change only their import and
qualified references to the fixed errors/event now declared by `FixedTermPolicy`.

Token comparison accounts for every original declaration exactly once: all
18 functions, the constructor, seven errors, event, constant, and two mappings.
Their signatures/bodies and the struct fields are unchanged; existing comments
are preserved, including the APR revert explanation. Fifteen functions move
into the policy; the family string and two configuration getters remain in the
concrete hook. The four test files compare as exact text after reversing only
their import/qualification changes. No tests or assertions were added or removed.

This preserves the setter's authorization and guard order, queue registration
before maturity before access, fixed APR validation before the selected default,
the APR callback's existing unknown-caller behavior, and the early-closure
permission OR rule and maturity update. Setter equal-time/past-time coverage
and additional management validation/effects remain M3-03 work.

### Verification

| Check | Result |
| --- | --- |
| Default and deploy focused runs, seed `0x5eed` | 317 tests across 18 suites pass in each profile; zero failures/skips, 1,000 iterations per fuzz test. Identical test discovery. |
| Shared and concrete behavior | Fixed, open, periodic, `BaseHooks`, access controls, constraints, extension, and effective APR validation suites pass. |
| Production consumers | Factory, three lens suites, administrator transfer, borrower-account compatibility, wrapper, hook dispatch, standard/revolving scenarios, and market suites pass. |
| Raw ABI and selectors | All three concrete ABIs match M2 exactly in both profiles, including names and tuple `internalType` fields. M1 comparison retains only the input-name changes already approved in M2. |
| Packed storage | All three normalized layouts match M1 and M2: 11 top-level entries each. Only compiler AST identifiers are normalized; slots, offsets, field widths, names, and type structure remain unchanged. |
| Executable artifacts | Creation/runtime bytecode, link references, and immutable patch positions match qualified M2 in both profiles. All artifact metadata source hashes match the final working tree. |
| Formatting/lint | All seven changed Solidity files pass Prettier. Full lint retains the same 34 untouched formatting failures. Final standalone Solhint matches M2 exactly: zero errors, 22 warnings. |

Both test runs use the same explicit contract selector, recorded in
`m3-02-tests-{default,deploy}-receipt.json`, with Forge 1.8.3 and solc 0.8.25.
The final input manifest contains 281 source/test/script/settings files and
897 dependency files; tool hashes and effective default/deploy settings still
match the qualified handoff. These focused checks do not replace M3-06's full
qualification runs.

The default tests and raw storage export preceded one line wrap in the new
policy's NatSpec comment. The first Solhint run identified that 101-character
line; its log is retained. Reversing only that wrap reproduces the tested source
hash. The final default rebuild and deploy tests compile the wrapped source,
with identical executable bytes and ABI. Final touched formatting and standalone
Solhint pass against their stated baselines; no behavior changed after testing.

### Deployment size and gas

| Template | Runtime bytes | Creation bytes | `STOP || initcode` bytes | Stored-initcode headroom |
| --- | ---: | ---: | ---: | ---: |
| Open | 15,653 | 18,379 | 18,380 | 6,196 |
| Fixed | 17,014 | 19,741 | 19,742 | 4,834 |
| Periodic | 19,949 | 22,676 | 22,677 | 1,899 |

These are unchanged from M2; the accepted runtime/creation increases over M1
remain 349/413/678 bytes respectively. Empty-argument factory creation payloads
are 18,475/19,837/22,772 bytes, below the 49,152-byte limit. Runtime and stored
initcode remain below their 24,576-byte limits.

Byte-for-byte creation/runtime identity, unchanged immutable patch positions,
and unchanged link references justify reusing the qualified M2 gas observations
for the same call inputs, state, and transaction boundaries. This includes fixed
creation, queueing, APR, and closure, plus M3-01's five fixed-setter measurements.
The retained M1-to-M2 comparisons and explicit measurement exclusions still
apply. The move adds no execution or deployment cost; no fresh gas trace is
claimed for this checkpoint.

### M3-02 evidence identities

Paths below are relative to the ignored M3 evidence root. Command receipts bind
input manifests and log hashes. The artifact comparisons bind complete compiler
exports and current source hashes; `m3-02-review-receipt.json` binds the staged
checkpoint and supporting raw files.

| File | SHA-256 |
| --- | --- |
| `m3-02-qualification.json` | `07526ea764b31d617cb7549a5c15e7ead817f1b1350feab936dbd36769341c24` |
| `m3-02-final-inputs.sha256.json` | `8027710fa24d4b241fc6f9d819e64c38e16cc944b9bef50fc92f3e4f93ee743f` |
| `m3-02-final-relocation-comparison.json` | `94464dc3129e0c14d4eec33cff98e66882fc683776f4e78e36ed1ce70494fc06` |
| `m3-02-tests-default-receipt.json` | `5908877330c066655dc62b11ecb32f76aa435c5aad16c6b95e1596c3adfbe363` |
| `m3-02-tests-deploy-receipt.json` | `8023f8ff282238d46d35c05ece88ee03df6cf14bf1c92fed81b2715486acae30` |
| `m3-02-artifact-comparison-default.json` | `34b67a3e397c8135d41397a8c65ea16c6eb15ddd80bd26be826bd44792a488e5` |
| `m3-02-artifact-comparison-deploy.json` | `11b720f30aab0b0ee204db04519034f4e47b3b91fd48cf8749355e1e41f7ef71` |
| `m3-02-storage-comparison.json` | `0c1d0cc999970edd5d4416247576400e0c60ff49e42ac140437a658f3fc00dbd` |
| `m3-02-lint-comparison.json` | `6a6e6b72e2197f86b552bba0c767d457750c283e279db32cf4e650f90118a166` |

The user approved M3-02 and authorized its signed checkpoint. The reviewed
source and staged patch hashes were verified before updating these completion
notes. M3-03 follows with its own staged review. The reference files remain
untracked and excluded; no push has been performed.

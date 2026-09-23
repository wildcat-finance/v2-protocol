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

## M3-03: Fixed setter extension points

Implemented against M3-02 commit `2227aa2c6976bb7898ca3868fa202538f1868320`,
signed as kethcode after user approval. Its signature and the reviewed Solidity
hashes were verified before starting this task. M3-03 is implemented and
verified; the user reviewed the staged checkpoint and authorized its signed
commit and continuation.

### Setter boundaries and test ownership

`setFixedTermEndTime` now calls `_validateFixedTermChange` after the existing
administrator, registration, term-reduction permission, and no-extension checks.
At that point `_hookedMarkets[market].fixedTermEndTime` still contains
`previousTime`. The setter then writes `newTime`, emits `FixedTermUpdated`, and
calls `_afterFixedTermChange` before returning. Either extension can reject the
operation; an after-change rejection rolls back the maturity, event, and any
feature state written during the call.

Both functions have empty internal virtual defaults; validation is `view`.
They apply only to the administrator's setter. Creation retains
`_onMarketConfigured`, and early closure retains `_validateCloseMarket` and
`_applyCloseMarket`. There is no new date or configuration copy. A token
comparison confirms that the only changes to existing policy declarations are
the two setter calls; all other bodies and existing comments are retained.

`test/mocks/FixedTermManagementHooks.sol` supplies a test-only notice floor and
cumulative reduction budget using these extension points. It inherits the
production setter without copying or overriding it. Validation checks the
notice floor while observing the old maturity; the after-change extension
charges the actual stored reduction and emits its own event. A budget violation
deliberately rejects after the feature write, exercising rollback of both the
term configuration and feature state. These rules are test fixtures, not new
production policy decisions.

The existing ten tests in `FixedTermHooksTest` and all its original helper/state
declarations are unchanged. Six cases were added to that owner, with no new test
suite or inherited test entrypoints:

| Case | Evidence |
| --- | --- |
| Production equal/current/past timestamps | An enabled equal-time update succeeds and emits the existing event; disabled equality rejects. Attempts to extend maturity still fail, and updates to now or the past succeed. Queueing and APR then read the shortened maturity. |
| Accepted extension, fuzzed | Two successive reductions preserve exact old/new context, emit `FixedTermUpdated` before the feature event, and accumulate the reduction from the updated stored maturity. The second update reaches the notice/budget boundary. |
| Before-write rejection | A notice-floor failure preserves the full packed configuration and prior nonzero feature state; a retry at the permitted boundary succeeds. |
| Native error priority | Wrong administrator, unknown market, disabled reduction/equality, and attempted extension retain their original errors even when the added rule would also reject. An otherwise valid equal-time update reaches that rule. |
| After-write rejection | Exceeding the cumulative budget restores both maturity and the prior nonzero reduction total. A valid retry consumes the remaining budget once. |
| Separate lifecycle operations | Creation and early closure succeed under their existing rules even when the setter's notice floor and budget would reject. Closure updates maturity without charging the setter's budget. |

### Verification, compatibility, and cost

Default and deploy runs each pass **323 tests across 18 suites**, including
16 fixed-suite cases. Both use seed `0x5eed` and 1,000 iterations per fuzz test;
discovery is identical, with all 317 prior cases retained and exactly six added.
The selected suites include shared access/constraints, all concrete hooks,
extension/APR validation, factories, lenses, administrator and borrower-account
flows, wrappers, dispatch, and standard/revolving market integrations. Command
receipts retain the full selector and log hashes. M3-06 still owns the full
milestone qualification runs.

The input manifest binds 282 source/test/script/settings files and 897 dependency
files. Forge/solc hashes and effective settings match the qualified handoff.
All three production ABIs, method identifiers, creation/runtime bytecode, link
references, and immutable patch positions match M3-02 and M2 in both profiles.
Metadata source hashes match the checked tree. Normalized storage layouts remain
identical to M3-02/M2/M1, with 11 top-level entries per template.

The empty production extension points compile away. All three template sizes
remain at the [M3-02 values](#deployment-size-and-gas); fixed runtime/creation are
17,014/19,741 bytes, with 4,834 bytes of stored-initcode headroom. Executable
identity permits reusing the qualified gas evidence under matching call inputs,
state, and transaction boundaries. In particular, the original setter measurement
test is unchanged: its successful reduction remains 31,405 gas, with four rejection
observations at 23,820–26,213. No fresh gas trace is claimed, and the prior
measurement exclusions still apply.

All three changed Solidity paths pass Prettier. Full lint reports the same
34 untouched formatting failures; standalone Solhint matches M3-02/M2 exactly,
with zero errors and 22 warnings. No source changed after these checks.

### M3-03 evidence identities

Paths below are relative to the ignored M3 evidence root. The review receipt
binds the staged files and supporting artifacts; command receipts bind the
input manifest and their logs.

| File | SHA-256 |
| --- | --- |
| `m3-03-qualification.json` | `e4bd25fee04228181874b99e6e83e58a332d89cc839cd6bb868542780e51f670` |
| `m3-03-inputs.sha256.json` | `91f13aedf4b85f9141b20aec7b39b9c399497e1558b18011e71e6829e87f380f` |
| `m3-03-source-comparison.json` | `4e9567318c860223453f5769fb0519a088f9c55967de260f65d98c41e509928f` |
| `m3-03-tests-default-receipt.json` | `c47716316876a8aabcdb17ac9b3ead6854125e86f41623290e0228bbde2c94fd` |
| `m3-03-tests-deploy-receipt.json` | `479c48b869eade3b5454e8e2e4839c81de57592e0ce48765ce5c34691c16d6d7` |
| `m3-03-artifact-comparison-default.json` | `e46abbffbb10fd46aff85ce6747fc4d85a2201af957302ea04c760aed3ac94cb` |
| `m3-03-artifact-comparison-deploy.json` | `3023c06b6a95b696008f3270eee13f704b6433b8a3003314183bc68626f7f879` |
| `m3-03-storage-comparison.json` | `e5c4b34f78c2bbb50a1aeae66ccdd39acec168d608d5808803b0fcac09524a7c` |
| `m3-03-lint-comparison.json` | `8b5b6dd3874afc2c838e6ee2aec4ad28e840ece217849fb537c40b81ca51e8ed` |

The user approved M3-03 and authorized its signed checkpoint. The reviewed
source and staged patch hashes were verified before updating these completion
notes. M3-04 follows with its own staged review. The voice guide, reference PDF,
and lifecycle sketch remain untracked and excluded; no push has been performed.

## M3-04: Periodic policy extraction

Implemented against M3-03 commit `24d9b8ed7a64028a855fe5b2237b24599b269093`,
signed as kethcode after user approval. Its signature and the reviewed Solidity
hashes were verified before starting. M3-04 is implemented and verified; the user
reviewed the staged checkpoint and approved its signed commit.

### One owner for the periodic lifecycle

`PeriodicTermPolicy` owns the schedule and proposal mappings, five constants,
thirteen errors, five events, decoding/initialization, access adapters, window
queries, proposal management/queries, both APR execution routes, and closure.
It uses the existing `BaseHooks` behavior. `PeriodicTermHooks` retains the exact
constructor and flags, `version()`, `templateVersion() == 2`, and the two public
configuration getters over that same state.

The three global structs and narrow `IMarketApr` query interface move unchanged
to `src/access/types/PeriodicTermHookTypes.sol`. The original concrete source
explicitly re-exports all four declarations. Existing lens/fixture/type imports
and the concrete deployment artifact path continue to work. The legacy
`pendingAprChanges` getter and response-window-aware `getPendingAprChange` now
live with the policy, preserving their different registration/return behavior.

Token comparison accounts for all 52 original members exactly once: 26 functions
plus the constructor, five events, thirteen errors, five constants, and two
mappings. Twenty-two functions move; four functions and the constructor remain
in the concrete hook. All signatures, bodies, global declarations, and original
comments are preserved, including the schedule-bound TODOs and APR branch
explanations. No proposal extension call is added here.

| Lifecycle boundary | Preserved behavior |
| --- | --- |
| Creation and queueing | The same packed schedule/access configuration, width checks, window bounds, and registration/schedule/access error priority. Either closed flag opens the schedule without bypassing withdrawal access. |
| Proposal creation/replacement/query | The original native checks and fixed response-window calculation, cancellation-before-replacement event order, stored bounds, legacy getter, and expired-proposal visibility. One `_pendingAprChanges` mapping serves the entire lifecycle. |
| Ordinary APR callback | A strict reduction uses `_executePeriodicReduction`, preserves current reserves, and skips `_applyDefaultAprUpdate`. Equality retains the proposal; increases cancel it before selecting the default. |
| Dedicated APR execution | The same shared reduction helper, registration/timing/unpaid-withdrawal checks, APR-only return, current-reserve validation, and empty calldata passed to `_checkAprChange`. Both routes retain effective-value validation and rollback. |
| Closure | Registration validation, closed-flag write, pending-proposal deletion/cancellation, then `PeriodicTermClosed`. Temporary-reserve state and the market-owned APR/reserve reset retain their existing behavior. |

Five consumer files update imports and declaration-owner references:
`PeriodicTermHooks.t.sol`, `BaseHooks.t.sol`, `AprValidation.t.sol`,
`ProductionMatrixScenarios.t.sol`, and `MarketMatrixHandler.sol`. The handler's
`abi.encodeCall` target is now `PeriodicTermPolicy.proposeAnnualInterestBips`;
its selector remains `9b87b818`. Reversing those mechanical changes restores
the original tokens in every file. Only the handler also has a whitespace
change: Prettier joins one existing `_expectedDrawnAfterRepay` call onto a
single line. No tests, assertions, or handler behavior were added or removed.

### Verification and costs

Default and deploy runs each pass **323 tests across 18 suites**, with unchanged
discovery, seed `0x5eed`, and 1,000 iterations per fuzz test. This includes the
17 periodic cases, all five effective-APR validation cases, the shared
configuration probe, and the existing factory/lens/authority/borrower-account,
wrapper, dispatch, and standard/revolving market integrations.

Because the invariant handler's static call target changed, its canonical
campaign was also run under the default profile: all **nine invariant properties**
pass over 2,000 runs at depth 30, totaling 60,000 calls and zero handler reverts.
`proposeAprReduction` was invoked 3,535 times. Forge reports those nine properties
as one campaign/test. The handler's own ABI and creation/runtime bytecode also
match its qualified pre-extraction snapshot exactly. This targeted campaign
does not replace M3-06's full qualification runs.

The manifest binds 284 source/test/script/settings files and 897 dependency
files. Tool hashes and effective settings match the qualified handoff. All three
production ABIs, method identifiers, creation/runtime bytecode, link references,
and immutable patch positions match M3-03/M2 in both profiles; all metadata
source hashes match the checked tree. Normalized layouts match M3-03/M2/M1,
with 11 top-level entries per template.

All three sizes remain at the [M3-02 values](#deployment-size-and-gas). Periodic
runtime/creation remain 19,949/22,676 bytes, with 1,899 bytes of stored-initcode
headroom. Executable identity justifies reusing the qualified creation, window,
queue, proposal, both-APR-route, and closure gas evidence under the same inputs,
state, and transaction boundaries. M3-01's periodic proposal creation/replacement
observations remain 58,661/43,021 gas. No fresh gas trace is claimed; the prior
measurement exclusions remain in force.

All eight changed Solidity paths pass Prettier. Formatting the touched handler
resolves one pre-existing failure, leaving **33 untouched formatting failures**
instead of 34. Standalone Solhint matches M3-03/M2 exactly: zero errors and
22 warnings. No Solidity changed after verification.

### M3-04 evidence identities

Paths below are relative to the ignored M3 evidence root. The review receipt
binds the staged checkpoint and supporting artifacts; command receipts bind
input manifests and log hashes.

| File | SHA-256 |
| --- | --- |
| `m3-04-qualification.json` | `9e61f1a62467459dfe03b74c70cb99ebd64d22247ac1a674826d07f108020843` |
| `m3-04-inputs.sha256.json` | `44cb7142cca5d24e07f40897b82a2b9368b8a2ab620342c3b04c6d059374b48d` |
| `m3-04-relocation-comparison.json` | `12f13e94ce5f56dd426a40fa6c668c743d3be5511eafb363f6ef2b51f8aaa22c` |
| `m3-04-tests-default-receipt.json` | `d61593b2734f1c56a6759808f9901ab9a73fe802ab3d223be0b82305b27f2bd5` |
| `m3-04-tests-deploy-receipt.json` | `a61027110401ae5c82a60f2e0f0d7df8c95fb326acb08bf1470df91ba7bd30cd` |
| `m3-04-invariants-default-receipt.json` | `c9375d5485b7d9908674ebfe601d3230aad30012b1f09083975a4eb824698f14` |
| `m3-04-artifact-comparison-default.json` | `fb1fe18b14121f19633c0bc4c19b1fc06e48ee9eeae6988c2e771ec7d57f235e` |
| `m3-04-artifact-comparison-deploy.json` | `04f1ded757f67c78bad3706d759285633719f4d560aad5d28a26defa6c73794d` |
| `m3-04-storage-comparison.json` | `e052100b05993dbd81041b400540483f78791f4bb2d7c345c38a6df303a9bbb8` |
| `m3-04-handler-comparison.json` | `4b9367265bbf505d07eb85ea0bfdaf855e1405a65462a1ec4837fd55aaa37ead` |
| `m3-04-lint-comparison.json` | `99f7200ce3f3228f94ace2a998ceeadf6790f8e96ccccebe32c296367cdb704c` |

The user approved M3-04 and authorized its signed checkpoint. The reviewed
source and staged patch hashes were verified before updating these completion
notes. M3-05 follows with its own staged review. The voice guide, reference PDF,
and lifecycle sketch remain untracked and excluded; no push has been performed.

## M3-05: Periodic proposal extension point

Implemented against M3-04 commit `2eed0412b461cf2f2a25aba1600abea215a8eb1d`,
signed as kethcode after user approval. Its signature and the reviewed Solidity
hashes were verified before starting. M3-05 is implemented and verified; the user
reviewed the staged checkpoint and approved its signed commit.

### Proposal validation before replacement effects

`PeriodicTermPolicy.proposeAnnualInterestBips` now calls the empty internal
`view virtual` `_checkPeriodicProposal(address market, uint16 proposedApr,
uint32 responseStart, uint32 responseEnd)`. The call follows the existing
administrator, registration, closed-market, withdrawal-window, APR-bounds, and
strict-reduction checks, plus all response-window calculations. It receives the
exact computed `uint32` bounds, after narrowing and overflow checks. It precedes
any cancellation event, proposal replacement, or new proposal event.

The old proposal remains in `_pendingAprChanges[market]` during validation. A
feature can reject the proposed APR or response window without copying the
proposal entrypoint. The default adds no restriction. Both APR execution routes
still reach `_checkAprChange`; proposal acceptance does not bypass execution
validation. No execution, cancellation, closure, or query implementation changed.

Source comparison preserves every original policy and periodic-test member,
with only the proposal call inserted into an existing body. The new empty
function is the only added production declaration. Existing comments and branch
explanations remain intact.

### Test-only rule and verification

`test/mocks/PeriodicProposalHooks.sol` derives from the existing
`AprValidationHooks`, reusing its APR floor and adding per-market earliest-start /
latest-end bounds for the response window. It overrides only the new proposal
check and inherits proposal management. Its limits are test-only; no new
production policy or tranching behavior is selected.

Six cases were added to the existing `PeriodicTermHooksTest` owner:

| Case | Evidence |
| --- | --- |
| Accepted creation and replacement | A proposal at the APR floor succeeds with the exact allowed window; replacement uses the next scheduled window and retains cancellation-before-proposal event order. |
| Rejected creation | An APR one basis point below the floor fails with the exact APR in the error, leaving no proposal or proposal events. |
| Rejected replacement | The existing APR, timestamp, and response bounds remain visible through both query APIs; no cancellation or replacement event is recorded. |
| Exact response-window context | Fuzzed later periods and offsets reject a start one second too early or an end one second too late, then accept the exact market/window context. The existing schedule helper supplies the expected bounds. |
| Native guard priority | Administrator, registration, closed-market, withdrawal-window, bounds, and strict-reduction errors still win when the additional APR rule would also reject. |
| Width/error priority | Overflow of `responseWindowEnd`, narrowing of `responseWindowStart`, and narrowing of `proposalTimestamp` each retain the arithmetic panic before the feature can reject. |

Default and deploy runs each pass **329 tests across 18 suites**, with seed
`0x5eed` and 1,000 iterations per fuzz test. Discovery retains all 323 previous
cases and adds only these six; the periodic owner now has 23 cases. All five
existing `AprValidationTest` cases remain unchanged and pass, covering both
execution routes, effective values, proposal rollback, temporary-reserve
behavior, and empty dedicated-route calldata. Shared behavior, configuration,
factory/lens/authority/borrower-account, wrapper, dispatch, and standard/revolving
market integrations pass in the same runs.

The initial default run passed 328 cases and exposed a wrong expectation in the
new width test: this policy uses the local `SafeCastLib` arithmetic panic, not
Solady's `Overflow()` error. Only those expectations were corrected; the initial
receipt/source snapshot is retained, and both final profile runs pass. The new
comment also fits the existing line-length rule.

### Compatibility and costs

The final manifest binds 285 source/test/script/settings files and 897 dependency
files. Tool hashes and effective settings match the qualified handoff. All three
production raw ABIs, method identifiers, creation/runtime bytecode, link
references, and immutable patch positions match M3-04/M2 in both profiles.
Metadata source hashes match the checked tree. Normalized layouts retain all
11 top-level entries per template, including periodic configuration/proposal
packing, and match the qualified M3-04/M2/M1 layouts.

The empty production extension compiles away. All three sizes remain at the
[M3-02 values](#deployment-size-and-gas); periodic runtime/creation remain
19,949/22,676 bytes, with 1,899 bytes of stored-initcode headroom. Qualified
M1/M2 gas comparisons and M3-01 management measurements remain applicable under
their original inputs, state, and transaction boundaries. Periodic proposal
creation/replacement observations remain 58,661/43,021 gas. No fresh gas trace
is claimed, and the original measurement exclusions remain in force.

All three changed Solidity files pass Prettier. Full lint retains the same
33 untouched formatting failures; standalone Solhint retains zero errors and
22 warnings. No Solidity changed after final verification. The M3-04 invariant
campaign is retained evidence, not a new run; M3-06 still owns the full required
qualification runs.

### M3-05 evidence identities

Paths below are relative to the ignored M3 evidence root. The review receipt
binds the staged checkpoint and supporting artifacts; command receipts bind
the final input manifest and log hashes.

| File | SHA-256 |
| --- | --- |
| `m3-05-qualification.json` | `a8a972efacadaae17ccedbf2f09b95a1a67c967b12f8a3cdca649fc65b09713f` |
| `m3-05-inputs.sha256.json` | `5f97d472a8d3ddb9ee0b39ee83cb788e4e25065ba21fee866ec2ff323c4c3ee5` |
| `m3-05-source-comparison.json` | `52e457e929b2bc6b405e63645f489ffdd2009752446a918c23d001720e7101e8` |
| `m3-05-tests-default-receipt.json` | `82bc8b85b4f2a366f44675b90f96f0b8938941a0cec0d940d39c28a12d7a1ddc` |
| `m3-05-tests-deploy-receipt.json` | `259d469ee7b2554348d8ce95727d8367796f45222e398c02aef961a5080d6681` |
| `m3-05-artifact-comparison-default.json` | `9229bc638e33afe64a5d3678c0d60229f6d866ff9d7c4f31dea2eaa416b62bd6` |
| `m3-05-artifact-comparison-deploy.json` | `79dc15edebe1706d02687068ecf3fdea30812b707f6cd67c81529dcc89689d8f` |
| `m3-05-storage-comparison.json` | `793a5c140fca8582aa402aaa4e4215b40ab1aa9c70cefa4494bd93e1653f1bd9` |
| `m3-05-lint-comparison.json` | `7f551a7348c4fe671aa76337fc2388210f7f460f567430a75eeb080567d3dfe2` |
| `m3-05-initial-tests-default-receipt.json` | `3bea0e83747d92873d466ca11b4a8522ad85277f03e62b78b899667babdb204b` |

The user approved M3-05 and authorized its signed checkpoint. The reviewed
source and staged patch hashes were verified before updating these completion
notes. M3-06 follows with final qualification. The voice guide, reference PDF,
and lifecycle sketch remain untracked and excluded; no push has been performed.

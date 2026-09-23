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

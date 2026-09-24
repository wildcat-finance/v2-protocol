# M5 results: integration compatibility and final documentation

- Plan: [M5 execution plan](hook-refactor-m5-plan.md).
- Status: [M5 tracker](hook-refactor-m5-tracker.md).
- Execution starting revision: `f3d5e7834f84c583ee9d4d261e106947197db3db`.
- Completed M4 handoff: `add362d22ab28b6d63f7e5627517f5f2e7e56121`.
- Original compatibility reference: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.
- Raw evidence root: `audits/hook-refactor/m5/2026-09-24/` (ignored).

## M5-01: Handoff and compatibility inventory

The user returned from maintenance and instructed M5 execution on 2026-09-24.
The tracked tree is clean at the planning commit. The three excluded user
references remain untracked. The explicit instruction authorizes continuation;
no milestone push or remote update is inferred or performed.

All **1,190 qualified M4 inputs** match: 293 source/test/script/settings files
and 897 dependency files. All 88 artifacts/helper scripts bound by the M4-06
review receipt and its commit receipt verify. The M4 and planning commits have
verified kethcode author/committer identities and SSH signatures.

Forge 1.8.3 and solc 0.8.25 binary hashes, effective default/deploy configurations,
Node 24.21.0, Yarn 1.22.22, and four clean submodule revisions match M4. Seven
pinned M1 identity/config/ABI references verify, and all 1,166 original
materialized inputs match the baseline Git revision or unchanged dependency
files. No suite was rerun for this unchanged handoff.

Source comparison to M1 finds exactly 11 changed/added paths, all under
`src/access/`. Fifty consumer and deployment-script files under the lens,
market, vault, factory, identity-registry, callback-config, and deployment paths
are byte-identical to M1. This supports reviewing their unchanged expectations;
source identity alone is not a new end-to-end integration pass.

### Consumer assumptions and proof boundaries

| Consumer / assumption | Inspected evidence and remaining work |
| --- | --- |
| Constructor encodings and providers | `BaseHooksTest.test_constructor_*` covers empty/encoded-empty arguments, existing/new/mixed providers, names, TTLs, indices, malformed input, and provider creation failure across all terms. The factory owner separately exercises nonempty provider initialization and instance provenance. M5-02 compares the raw constructor/data types and consumers. |
| Creation decoding, order, and flags | `BaseHooksTest.test_onCreateMarket_ConfigMatrix` independently constructs expected flags and checks stored access choices. Its partial/low-bit, width-before-access, and schedule-before-minimum properties retain the raw decoding contract. Fixed/periodic owners retain mandatory length, narrowing, term/schedule bounds, permission, and failure-priority cases. M5-02 checks the original readers and encodings, including partial words and even/odd boolean values. |
| Public tuples and source types | The three term owners exercise single/batch configurations, unknown values, order, and canonical metadata. Periodic proposal getters/routes have dedicated state-machine properties. `HooksConfigData.sol` imports all three original concrete type paths and decodes each family strictly. M5-02 must compare inherited raw ABI entries, tuple fields/`internalType`, public imports, and decoder assumptions. |
| Hook family and revision | Original production-matrix deployment checks each actual `version()` string; term metadata tests retain periodic revision 2. Lens facade tests classify synthetic strings and reject malformed return data. M5-03 must connect actual factory-deployed families/configurations to the real lens. |
| Market calls and accounting | `HookDispatchTest` verifies exact calldata, suffixes, state, returned APR/reserves, and disabled dispatch using a recording hook/factory fixture. Original `ProductionMatrixScenariosTest` properties provide real standard/revolving factories, all three terms, deposit/borrow/repay/queue/close, exact withdrawal boundaries, periodic execution, minimums, and rounding. M4 replacement cases add both APR routes and rollback/closure coverage. These complementary boundaries remain separate in the evidence. |
| Lens market/configuration reads | `MarketLensCoreTest` uses real open and periodic hooks and real market bytecode through `HookDispatchFactoryMock`. It covers selected fields and periodic closure, but has no fixed-family configuration property and no production-factory binding. This is an identified connection to add in M5-03, with non-default fields and requested-access versus forced-dispatch distinctions. |
| Lens instance/discovery reads | `MarketLensAggregatorTest` uses `LensFactoryMock`/`LensHooksMock` for template/provider/administrator/index aggregation. `HooksInstanceDataLib` casts every known family through the shared open ABI for name, providers, and constraints. M5-03 will connect this decoder to real factory instances and administrator-index changes across all terms and both factories. |
| Wrapper permissions and transfers | `Wildcat4626WrapperIntegrationTest` uses real wrappers, all built-in hooks, and real market bytecode, but a mock market factory. All-term readiness/deposit/redeem checks currently run on standard markets; separate open cases cover both market types. M5-03 will add the real factory-created six-cell connection, retaining these existing distinct assertions. |
| Administrator transfer | `HooksAdministratorTransferTest` verifies real standard/revolving factory indexes, events, authentication, and deployment nonces with open hooks. Fixed/periodic owners retain configuration/authority tests; M4 feature assemblies exercise real transfers and market isolation. The planned real lens-discovery property will also observe original fixed/periodic factory associations before, during, and after transfer. |
| Borrower accounts/origination | `BorrowerAccountCompatibilityTest.test_accountExecutionComposesAcrossTheProductionSixCellMatrix` uses real factories/registry/hooks/markets with an executing account mock. It distinguishes account market authority from principal hook administration and tests rejected credentials. Other account/origination properties own salts, fees, identity migration, and lifecycle. Account mocks represent the delegated caller interface; this does not qualify a future V2.6 account implementation. |
| Deployment, event consumers, and costs | The production factory matrix deploys every original template on both market types and checks provenance. M4 separately records actual deployment limits per feature assembly. ABI comparisons include event indexing/payload shapes; creation, proposal, closure, and administrator event order remains with its canonical owners. M5-02/M5-03 reconcile changed code identity and consumer expectations without rewriting historical inventories. |

The matrix identifies **coverage gaps**, not observed protocol regressions.
The required new connections belong in the existing production integration
owner using `ProductionMatrixFixture`; narrow unit/mock properties retain their
own suites. Initial additions planned for M5-03 are real lens configuration
decoding, lens/factory discovery through administrator transfer, and wrapper
operations on factory-created markets. Each uses a runtime term/market matrix
and explicit original-behavior expectations. No existing test is weakened to
obtain a passing comparison.

### Accepted differences and limits

- Public callback inputs gained names during M2: 24 open, 24 fixed, and 28
  periodic. The unchanged selectors do not erase this raw-ABI difference.
  New tuple field, event/error, encoding, or metadata differences are not
  covered by that allowance.
- The [M1 source-type decision](hook-refactor-m1-design.md#public-types-and-source-consumers)
  explicitly permits mechanical moved error/event references to use their
  declaring owner. `ConcreteHook.SomeError.selector` cannot name a newly
  inherited declaration. Original configuration types remain available from
  the concrete-file imports. M5-02 must record both aspects rather than claim
  unchanged source qualification for every historical reference.
- Production code remains identical to M3/M2, with earlier runtime/creation
  increases from M1 of 349 / 413 / 678 bytes. New initcode/runtime hashes
  describe new deployments. Existing deployed inventory remains historical.
- Original open/fixed APR callbacks and no-ops keep their prior caller behavior.
  New stateful examples authenticate before recording effects. Dedicated
  periodic execution remains APR-only with current reserves and empty data;
  closure resets are a separate boundary.
- Retained full runs each report 746 tests / 51 suites and the nine-property,
  2,000-run invariant campaign. Lint retains 33 untouched formatting failures,
  zero Solhint errors, and 22 warnings. These are qualified M4 receipts, not
  new M5 test runs or proof that every consumer connection was already tested.
- No SDK/app/subgraph repository, protocol deployment, or future tranche/account
  implementation is included in the compatibility claim.

### Documentation disposition and next task

`cleanup-inventory.json` enumerates 18 tracked refactor documents at handoff and
this planned results file: 19 working documents to remove in M5-06, after a
verified export. It excludes unrelated maintained docs and all three untracked
user references. The reserved external handoff destination is
`/home/kethcode/wildcat/hook-refactor-handoff/2026-09-24/`; no export or deletion
has occurred. The final spec will be `hook-composition.md` there, accompanied by
the qualification record, referenced evidence, and hashes.

Maintained documentation stays under the existing integration/protocol guides;
the contributor guide will be `docs/integrations/hook-development.md`. Their
final links and content must stand without the removed working records. M5-02
now owns the public-format, metadata, import, and compiled-artifact comparison.

### M5-01 evidence identities

Paths are relative to the M5 raw evidence root above.

| File | SHA-256 |
| --- | --- |
| `identity-start.json` | `307de527711efb9fcf831e3eeb547ab95b8445b4310cec290176cf04fd9fd4b7` |
| `inputs-start.sha256.json` | `07c348cf1f0e8149d84a681ee0e1ca2da77e54b75e4fcb04a1fb2ad3531b055d` |
| `cleanup-inventory.json` | `d37596538cd87033dce3c07b5e8d68dbad8d727dd65f3aa6c7ef5db8109c59ce` |
| `qualify_handoff.py` | `91ac5a1fa1822294500a4dfd69a8e405e989dddae5e8e51ad06a176ce0e38b36` |

M5-01 is a documentation/evidence-only checkpoint under the existing signing
authorization. No Solidity, build configuration, or canonical test changed.

## M5-02: Public formats, identity, and source compatibility

M5-01 was committed as `118dab2`, signed kethcode and verified. Complete M1
and current production snapshots were compiled with the pinned solc binary,
unchanged dependencies, and canonical Cancun/viaIR/44-run/no-CBOR settings.
Both snapshots were also compiled with the deploy profile's extra IR outputs.
The original M1 creation/runtime hashes for all three hooks were reproduced.
The comparison covers **115 original production declarations**, including
37 concrete contracts and 61 nonempty runtimes; the four new abstract policy/
base declarations have no original counterparts.

### Compiled formats and consumer identity

| Surface | Result |
| --- | --- |
| Complete ABI arrays | 111 original declarations match exactly in standalone compiler output. The three concrete hooks retain only the accepted 24 / 24 / 28 callback-input labels. The fourth difference is the abstract APR declaration described below. |
| Wire formats | All 115 method-selector maps match. Complete ABI comparison includes constructors, events and indexing, errors, mutability, tuples, field names, and `internalType`; it does not reduce entries to selectors. |
| Storage and links | All 115 normalized layouts and link references match M1. The three hooks retain their 11-entry layouts. Immutable patch positions match, apart from the already recorded hook-code movement. |
| Consumer code | All 112 original declarations other than the three hook templates retain creation/runtime bytecode under matched production compilations. This includes markets, factories, lenses, wrappers, registry, and the relocated `IMarketApr` interface. |
| Concrete hook code | Open / fixed / periodic creation bytes are 18,379 / 19,741 / 22,676; runtime bytes are 15,653 / 17,014 / 19,949. Code matches qualified M4/M3/M2. Accepted increases over M1 remain 349 / 413 / 678 bytes. |
| Both cached Foundry profiles | Every original declaration matches full ABI entry content, selectors, links, immutable patch positions, and metadata source hashes. Standalone solc and Foundry order ABI entries differently; entry content is compared without dropping fields. All default and 114 deploy code outputs match the production compilation. The remaining cached lens artifact is explained below. |
| Source declarations and consumers | 26 original public declarations/readers preserve signature and body tokens: public structs, getters, metadata, raw creation-data readers, and constraint access. All original concrete-file type re-exports remain. The complete production graphs compile the unchanged consumers, including family-specific lens imports. |

Every metadata source hash was checked against its selected source revision or
the pinned dependency. A successful compile cannot substitute a mixed-revision
source for the baseline. Constructor/provider and creation-format compatibility
also retain their original canonical runtime cases from M4: empty/nonempty
arguments, defaults, partial words, low-bit booleans, checked narrowing, flag
merging, registration, and event ordering. Real factory-to-lens behavior is the
next task's separate proof boundary.

### Abstract APR declaration labels

Moving the APR callback implementation to `BaseHooks` leaves abstract
`MarketConstraintHooks` inheriting the declaration from `IHooks`. Its ABI now
uses these four inherited labels:

| Position | M1 label | Current label |
| --- | --- | --- |
| Input 1 | Empty | `reserveRatioBips` |
| Input 3 | Empty | `extraData` |
| Output 0 | `newAnnualInterestBips` | `updatedAnnualInterestBips` |
| Output 1 | `newReserveRatioBips` | `updatedReserveRatioBips` |

This is an additional **abstract developer ABI** difference, separate from the
approved concrete callback-input labels. Its types and selector are unchanged;
the abstract contract has no creation/runtime code. All three concrete templates
retain their original output labels. Bindings generated specifically from this
abstract ABI see the renamed fields. Repository runtime consumers retain their
ABI and code. Developer guidance must identify `BaseHooks` as the callback owner
and the designated helper as the default strategy; duplicating a declaration
just to preserve the abstract labels is not part of this refactor.

The existing M1 source decision also applies: moved error/event references use
their declaring base/policy, while original configuration types remain available
through their concrete-file imports. No claim of universal source qualification
compatibility is made.

### Compilation source set and the cached lens artifact

The cached deploy `MarketLensAggregator` has **21,120 creation / 20,852 runtime
bytes**, versus **21,062 / 20,794** in the matched production compilations.
Source metadata and code-generation settings match. Recompiling its recorded
138-source build graph reproduces the cached code exactly. A controlled run
changes **only the compilation source set**, keeping settings/output selection
identical, and reproduces the production-only code instead. Both M1 and current
complete-production builds match, with and without the extra deploy IR outputs.

This is reproducible compilation-source-set sensitivity, not evidence of a
refactor behavior change. Source hashes and optimizer settings alone do not
identify the complete build graph. Cached artifacts were preserved; none was
overwritten to obtain a match. Do not treat the two cached profile hashes as
interchangeable. Final deployment evidence must bind the actual artifact, and
bytecode comparisons require matched compilation inputs. This qualification
does not claim bytecode equality across arbitrary source sets.

### M5-02 evidence and disposition

All 1,190 input hashes remain unchanged. This task adds compiler/source evidence;
the prior qualified test runs remain prior runs. No Solidity, configuration,
deployment inventory, or test expectation changed. No repository integration
requires a public-format change. External SDK/app/subgraph execution is still
outside the evidence; actual factory/lens/admin/wrapper connections proceed in
M5-03.

The qualification receipt binds the compiler requests, outputs, source/artifact
comparisons, controlled reproduction, and helper scripts by hash. Paths below
are relative to the M5 evidence root.

| File | SHA-256 |
| --- | --- |
| `m5-02-qualification.json` | `25be43d5302801baab1a2adcbd2d46d6bcc18bae8119ef83733844951fce1e09` |
| `m5-02-all-contract-comparison.json` | `6ade73d88e65a91f24d69dd087873b10b534759b3b33d6c9a4c1a07950b1d87d` |
| `m5-02-profile-comparison.json` | `61efbb479470984de8fbca36632e5146c517eaa23bf9cc62c3ad0c076620ebee` |
| `m5-02-source-comparison.json` | `2a44ca827c8c15603cea5ad2099242b930bfe1caf32ea92f13098ac2b9e50816` |
| `m5-02-abstract-ABI-difference.json` | `163e035667e3fcc37111489c2f332b417c7fa84083a9ee821eb973ff4b56ec69` |
| `m5-02-source-set-difference.json` | `b7d3d43efb427736c1d2c92ed816a7dd004d0b975721126c5f11bd26ced49861` |

## M5-03: Real integration behavior and deployment

M5-02 was committed as `ce44e8e`, signed kethcode and verified. The three missing
consumer connections now live in `ProductionMatrixScenariosTest`, using the
unchanged production fixture and actual standard/revolving factories. The only
Solidity edit adds three properties and one assertion helper to that existing
owner. No production contract, mock, shared fixture, or existing expectation
changed.

### New real-consumer evidence

| Property | Explicit expectations and actual path |
| --- | --- |
| `test_lensDecodesFactoryMarketConfigurationAcrossProductionMatrix` | Twelve factory-created markets: every term/market combination with requested access enabled or omitted. Real `MarketLensCore` reads the complete hook tuple against independently constructed expected fields/flags. A positive minimum and disabled transfers force callbacks without forcing credentials; fixed/periodic queue dispatch remains distinct from withdrawal access. Asymmetric fixed permissions, non-default schedules/minimums, periodic revision 2 and closure, actual factory/template identity, principal/registry fields, and standard-versus-revolving optional values are checked. Reverse-order batch reads must preserve request order and the full expected tuple. |
| `test_lensTracksFactoryInstancesThroughAdministratorTransfer` | Six factory-created markets, with real core/aggregation lenses. Full instance tuples include name, family, factory template/index/counts, original constraints and deployment flags, and distinct pull/push provider TTLs/indices. Pending transfer keeps the old index; acceptance removes it and populates the new index. The market lens discovers the new administrator independently while preserving market borrower/principal/factory. Active-factory aggregation returns all six expected instances. |
| `test_wrappersKeepAccessAndBackingAcrossProductionMatrix` | Six factory-created markets and real factory-created wrappers. Both registration mappings and the market-token asset are checked. A locally blocked, uncredentialed registered wrapper can receive the lender's tokens without becoming a known lender. Wrapping retains scaled backing and share supply. Redemption to an unknown uncredentialed recipient fails and restores balances/supply/backing; redemption to a known recipient succeeds despite a later local deposit block. |

These are **24 actual market deployments**, not direct callbacks or replacement
lens/factory mocks. ERC20, provider, and sanctions mocks still represent their
external interfaces. Expected lens fields come from the original public
contract and explicit creation inputs, not a comparison against the same
refactored getter. Existing narrower unit/mock tests retain their distinct
malformed-return, authentication, boundary, and event assertions.

All **754 prior test entrypoints** retain identical tokens, including setup and
assertions. All **37 prior functions** in the edited matrix owner also retain
identical tokens. Three additions yield 757 source entrypoints across the same
51 owners, with no inherited test entrypoints or fixtures owning tests. The
existing fixture and all 146 production/mock files are unchanged.

### Verification and retained boundaries

| Check | Result |
| --- | --- |
| New properties, initial default run | Three pass. |
| Focused compatibility suites, default | 370 tests / 20 suites pass; zero failures/skips. |
| Same selection, deploy | The same 370 tests / 20 suites pass; zero failures/skips. |
| Run conditions | Timestamp `1724284800`, seed `0x5eed`, 1,000 fuzz iterations, unchanged Foundry/solc/settings and transaction isolation. |
| Existing behavior rerun | Common access/constraints, all term owners, extensions/APR validation, factories, all lenses, administrator transfer, exact market callback dispatch, production matrix/economics, wrappers, markets, and borrower-account compatibility/origination. Every prior entrypoint in the selected owners remains discovered. |
| Production artifacts | All 115 original declarations retain complete ABI entries, selectors, links, immutable patch positions, and qualified code in both profiles. The separately reproduced cached aggregator variant remains explicitly classified by compilation source set. |
| Feature artifacts | All nine test assemblies retain M4 raw ABIs, executable bytes, links, immutable patch positions, and verified metadata source hashes in both profiles. |
| Lint | Same 33 untouched Prettier failures; complete standalone Solhint output matches M4: zero errors, 22 warnings. The edited Solidity file passes Prettier. |

Original callback dispatch, APR routes/rollback, closure, continued withdrawal
batching, authority, and event order are owned by the unchanged cases rerun
above. Full-suite invariant results remain the qualified M4 results; this task
does not relabel a focused run as a complete suite or rerun invariants. Final
default/fixed-seed/deploy qualification remains M5-05.

### Deployment limits and costs

All three original templates deploy through both real factories in this task.
The rerun production-matrix cases also retain both-factory deployment for the
three borrow and three APR replacement assemblies. Each transfer-only assembly
retains its qualified direct runtime and actual `STOP || initcode` storage
deployment evidence; its individual factory path is not inferred from a larger
assembly using the same features.

Both profiles retain the [M4 size table](hook-refactor-m4-results.md#compatibility-deployment-sizes-and-costs).
Production stored-initcode headroom remains 6,196 / 4,834 / 1,899 bytes for
open / fixed / periodic. The smallest test-composition margin remains 653 bytes
for periodic borrow; periodic APR replacement retains 1,260 bytes. Runtime and
stored-initcode limits remain 24,576 bytes. Empty-argument constructor payloads
add 96 bytes to creation code and stay below 49,152 bytes. No limit or compiler
setting was changed.

Unchanged production code retains the qualified 97 callback, 70 creation/
minimum/query, and 14 management observations, with their original state,
calldata, call isolation, direct/nested boundaries, address qualifications, and
exclusions. The qualified composition observations remain attributable to their
unchanged artifacts. No fresh gas replay, whole-transaction estimate, or erased
M1-to-M2 cost delta is claimed.

No protocol compatibility fix was required. The initial run-wrapper command
omitted its profile argument and exited before invoking Forge; the separately
labeled command-error log/receipt is retained. The corrected focused command
and both qualifying compatibility runs passed.

The user approved continuation on 2026-09-24 and directed maintained docs to
follow the existing README structure and link format. The exact reviewed index,
bound evidence, and all 1,190 inputs verified before updating only completion
status. M5-03 is committed under the established signing workflow; M5-04 follows.
Final qualification, external export, and working-document removal remain
pending. No push, external-consumer execution, or V2.6 implementation occurred.

### M5-03 evidence identities

Paths are relative to the M5 evidence root. The qualification binds run logs,
receipts, source ownership, artifact identities/limits, lint, and helper scripts.
The review receipt separately binds the final index and staged patch.

| File | SHA-256 |
| --- | --- |
| `m5-03-qualification.json` | `04f7c6c92c6ffed2ef21dc9df3f433245a6f53f81629c1bc643f1002655dbb9a` |
| `m5-03-inputs.sha256.json` | `352f127ba1f33d4605ed0b66322cf616a5aa9a4b631b89a06d3af2e5e7a621e5` |
| `m5-03-tests-default-receipt.json` | `8c1a9a320377dbc0ea34624af96fdddf463010c16b779d08518686231737317e` |
| `m5-03-tests-deploy-receipt.json` | `dd0dc3014dcdc00f96486512f1d4d16e198725c2f970875d8c97540e1d927533` |
| `m5-03-ownership-comparison.json` | `c9c5f233e6cbd8c48c9c0f63196c9e2c42311837d2cdc05f9b87edb01dbe2a11` |
| `m5-03-runtime-artifacts.json` | `8f21e2e7bad39b9da7dccca82a962ec87cb400d61e05820afcb983bda2a6ff26` |
| `m5-03-lint-comparison.json` | `6bc1eb634b7a52c77414ad38ceef3974e9fe9a36635d40e4b4e41dac98202a7a` |

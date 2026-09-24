# M5 plan: integration compatibility and final documentation

- Milestone: [M5 — Qualify compatibility and document the result](hook-refactor-milestones.md#m5--qualify-compatibility-and-document-the-result).
- Execution status and checkpoints: [M5 tracker](hook-refactor-m5-tracker.md).
- Completed M4 checkpoint: `add362d22ab28b6d63f7e5627517f5f2e7e56121`.
- Original compatibility reference: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`,
  recorded in the [M1 baseline](hook-refactor-m1-baseline.md).
- Final implementation boundaries: [M4 handoff](hook-refactor-m4-results.md#m5-handoff).
- Status: proposed execution plan; M5 execution has not started.

The user identified existing integration compatibility as M5's highest priority
on 2026-09-24. Documentation, deployment/cost checks, and final qualification
remain required. The user also directed removal of the refactor's working
documents and spec from the final release tree, after saving the updated spec
for transfer to the knowledge base.

## Outcome and boundaries

Confirm that the hook refactor preserves the contracts existing consumers rely
on: encodings, metadata, callback dispatch, authority, observed behavior, and
deployment paths. Every compatibility claim needs a specific consumer and
attributable evidence. A passing suite total or matching function selectors
alone does not establish that contract.

Use M1 for original public behavior and formats; use completed M4 as the
immediate source/evidence reference. Preserve the accepted M2 callback-input
names and explain the existing size/gas changes from M1. Do not normalize away
new differences or derive expected behavior only from the refactored code.

The work ends with maintained integration/contributor guides, a self-contained
updated spec saved outside the repository, and a release tree without these
working specs, plans, trackers, or results. Final evidence and the cleanup receipt
must remain available after their tracked indexes are removed.

This qualifies hook extensibility as preparation for later V2.6 work. Tranching
economics, repayment/default policy, and whether V2.5 core interfaces satisfy a
future tranche implementation are subsequent work. New product templates,
runtime feature installation, protocol deployment, inventory publication, and
external SDK/app/subgraph changes are outside this milestone.

## Compatibility priorities and proof owners

M5-01 refines this map to exact properties, source locations, and evidence
identities. Distinguish real production integrations from mocks and direct
callback tests. Where a mock replaces the behavior being claimed, close that
specific evidence gap through the actual consumer path.

| Consumer / boundary | Required compatibility | Existing owners to inspect |
| --- | --- | --- |
| Callers and ABI consumers | Constructors, inherited functions/events/errors, selectors, mutability, return tuples, indexed event fields, and tuple `internalType`. Retain original artifact/import paths and type re-exports. | M1 ABI/source inventory; `BaseHooksTest`, common/term owners, deployment scripts and canonical fixtures. |
| Factories and template discovery | Constructor/provider arguments, creation-data lengths/defaults/boolean decoding, required/optional flags, instance ownership/indexes, exact family names, and periodic revision metadata. | `HooksFactoriesTest`, `HooksConfigTest`, `BaseHooksTest`, `ProductionMatrixScenariosTest`. |
| Standard/revolving markets | Final market binding, callback ABI/data suffixes, intermediate state, authentication/error order, effective APR/reserves, closure, withdrawal batching, and rollback after a callback. | `HookDispatchTest`, `ProductionMatrixScenariosTest`, original market/term owners, `ProductionEconomicsTest`, matrix invariants. |
| Lenses and off-chain decoding | Decode real template getters and market bindings; preserve family detection, tuple fields/order, optional revision handling, batch ordering, and borrower/factory scoping. | `MarketLensCoreTest`, `MarketLensFacadeTest`, `MarketLensAggregatorTest`; connect mock-level proofs to real template evidence. |
| Lenders, credentials, and wrappers | Deposit/transfer/exit permissions, exact wrapper and known-lender exemptions, access queries, scaled/normalized units, and continued withdrawal rights. | Shared access/credential owners, `HookExtensionsTest`, `Wildcat4626WrapperIntegrationTest`, production lifecycle owners. |
| Administrators and borrower accounts | Registered principal/account resolution, deployment salt/nonce rules, authority before/pending/after transfer, registration, and instance/market association. | `HooksAdministratorTransferTest`, `BorrowerAccountCompatibilityTest`, `BorrowerAccountOriginationTest`, factory/common owners. |
| Deployment and indexing consumers | Real template-storage/instance/market deployment, creation/runtime identity, event provenance, and the distinction between unchanged public formats and new code identity. | Factory/production matrix owners, deployment scripts, event/integration documentation. |

External repositories are not implicitly qualified by this map. Record any
consumer-facing consequence of an observed difference and what must be checked
externally; do not claim SDK/app/subgraph execution from repository tests.

## Deliverables and review workflow

Start a temporary `hook-refactor-m5-results.md` during execution. Store raw
manifests, comparisons, logs, and receipts under ignored
`audits/hook-refactor/m5/<run-id>/`. Retained evidence must preserve its original
inputs, settings, measurement boundaries, and exclusions.

Every task is a checkpoint. Complete verification and stage any checkpoint
containing **Solidity, including tests**, for user review before commit or the
next implementation task. A demonstrated compatibility gap warrants the
smallest correction and a regression that fails before the fix. Preserve
original expectations; explain any mechanical test adaptations.

Documentation-only checkpoints may be committed under the existing
authorization. Commit as `kethcode <dave@wildcat.finance>` with the configured
SSH key and verify the signature. The user reviews and pushes milestones.
Prepare this plan now; begin execution after the M4 handoff and instruction to
start M5. No push or follow-on tranching work is authorized by this plan.

The user has authorized final removal of the working documents. Execute that
cleanup only after exporting and verifying the handoff described in M5-06.
The voice guide, reference PDF, and lifecycle sketch remain untracked and
untouched. New code comments retain technical names and meaningful branch
explanations under the user's voice guideline.

## Task sequence

| Task | Deliverable | Depends on |
| --- | --- | --- |
| M5-01 | Qualify the M4 handoff and map compatibility consumers and evidence gaps. | Reviewed plan and instruction to start M5. |
| M5-02 | Resolve every public-format, metadata, and source-import compatibility difference. | M5-01. |
| M5-03 | Qualify real consumer behavior and factory deployment across term/market combinations. | M5-02. |
| M5-04 | Update maintained integration and contributor documentation from the qualified behavior. | M5-02 and M5-03. |
| M5-05 | Final source qualification, acceptance reconciliation, and updated spec. | M5-01 through M5-04. |
| M5-06 | Export the handoff, remove working documents, and verify the final release tree. | M5-05. |

## M5-01: Handoff and compatibility inventory

**Work**

- Record the reviewed M4 commit, clean tracked state, signing identity, input
  manifests, tool hashes, effective profiles, and dependency revisions. Qualify
  retained M1/M4 references without relabeling prior tests as fresh runs.
- Map each consumer above to its source assumptions, original expectation,
  owning test, and actual proof boundary. Include external-call encodings and
  decoders, not only Solidity inheritance or public signatures.
- Inspect what existing tests really assert. Identify missing real-consumer
  connections, weak expectations, and untested boundaries; add cases later
  only when they establish a missing property. Keep canonical suite ownership.
- Record the approved differences from M1 separately from newly found issues.
  Resolve unexplained compatibility differences before qualification can pass.
- Inventory maintained documentation and the exact working-document removal
  set. Prepare the outside-repository export destination; retain the documents
  in the repository until M5-06.

**Complete when:** every compatibility surface has an owner and evidence plan,
the baseline is attributable, and no unexamined difference is labeled harmless.

## M5-02: Public formats, identity, and source compatibility

**Work**

- Compare complete raw compiler ABIs in both profiles against M4 and M1,
  including inherited entries, event indexing, errors, tuple shapes/names,
  constructors, and mutability. Only the already-approved M1 callback-input
  labels are an existing allowance: 24 open, 24 fixed, and 28 periodic.
- Check constructor/provider and per-market creation encodings against their
  consumers. Preserve length checks, defaults, flag packing/merging, low-bit
  boolean behavior, registration ordering, and configuration getters.
- Confirm exact `version()` family strings, the existing periodic
  `templateVersion()`, and real lens interpretation. Feature examples with
  different identities must not change original-template discovery behavior.
- Verify original public imports/type re-exports and deployment artifact paths.
  Compile consumer paths where needed. Do not silently shift generated-binding
  or source-import requirements just because runtime selectors match.
- Explain compiler metadata and creation/runtime identity differences. Check
  normalized storage and immutable/link references without treating a matching
  layout as permission to upgrade existing immutable deployments. Retain
  earlier accepted code changes and their deployment/address consequences.

**Verification:** artifact/source comparisons plus narrowly targeted canonical
properties for any uncovered format or decoder behavior. Test expectations come
from the original public contract and consuming code. No new production APIs
or metadata revisions are planned.

**Complete when:** each public-format/identity difference has an explicit
disposition and existing consumers can encode, identify, import, and decode
the three original templates as before.

## M5-03: Real integration behavior and deployment

**Work**

- Follow factory-created open/fixed/periodic hooks through both standard and
  revolving markets. Qualify real configuration/lens reads and deployment
  provenance; distinguish them from mock-only decoder tests.
- Review callback dispatch and action ordering, including effective APR values
  on both periodic routes, dedicated-route empty data/current reserves,
  closure's separate reset, and shared withdrawal batches before/after closure.
- Confirm credential/default exemptions, wrapper behavior, and query promises.
  Added feature checks must retain their intended enforcement. Preserve legacy
  no-op/unknown-caller behavior in original templates while authenticating new
  stateful extensions before their writes.
- Confirm administrator transfer and borrower-account/origination paths through
  the real authority and factory relationships. Exercise success, rejection,
  and rollback where each consumer depends on those outcomes.
- Inspect event topics, indexed fields, payloads, and ordering where indexers
  rely on them. Keep factory/template/instance/market provenance explicit.
- Verify actual runtime, `STOP || initcode` storage, and full constructor
  payload limits under unchanged settings. Original production templates must
  deploy through both real factories. List the actual deployment proof for
  every retained test assembly; do not generalize a larger assembly's factory
  run into a claim about a different concrete artifact.

**Verification:** reuse qualifying existing runs, then close specific gaps in
their owning suites. New failure fixes require before/after regression evidence
and affected compatibility checks. No permanent duplicate legacy suite or
inherited test entrypoints. Record representative gas under matching state,
calldata, isolation, and direct/nested call boundaries.

**Complete when:** existing consumer behavior and deployments are qualified,
every identified compatibility issue is resolved, and any evidence limit is
stated without substituting an assumption for required coverage.

## M5-04: Maintained integration and contributor guides

**Work**

- Update `docs/integrations/hooks.md` and the relevant access, fixed/periodic,
  event, wrapper, and borrower-identity guides where final behavior needs
  explanation. Give each behavior one documentation owner and cross-link it.
- Put extension instructions in `docs/integrations/hook-development.md`, linked
  from the maintained index. Describe `BaseHooks`, reusable term/feature
  components, concrete constructor/configuration choices, and state ownership.
- Use existing transfer/borrow components to explain adding independent rules
  and the APR assemblies to explain selecting a different default. Reference
  compiling canonical examples rather than introducing parallel implementations.
- Explain explicit ordering/conflict decisions, required dispatch versus access,
  initialization before deployed market code, authentication, rollback,
  effective-value validation, alternate APR routes, and distinct management/
  creation/closure boundaries. Document precise query/data/accounting limits
  and the observed deployment headroom.
- Keep maintained docs about supported behavior and developer obligations.
  Remove milestone narration, scratch paths, and dependencies on working docs.
  Preserve historical release/audit/deployment facts; update verification
  references only with evidence for the actual qualified source.

**Complete when:** a contributor can add a rule or replace a default using the
maintained guides, and integrators can determine what the original templates
still guarantee without reading the working spec or progress records.

## M5-05: Final qualification and updated spec

**Work**

- Reconcile all spec criteria against M5-02/M5-03 consumer evidence, source
  ownership, and the M4 extension proofs. Explain every changed/added/removed
  case and preserve the original expected behavior.
- Qualify the final source under `forge test`, `yarn test:fixed`,
  `FOUNDRY_PROFILE=deploy forge test`, and applicable lint. Retain an existing
  full run only if source/tool/settings/dependency identity justifies it. After
  material changes, rerun affected checks and the required final suites. Do
  not rerun an unchanged suite solely for a new evidence filename.
- Compare ABI/layout/code/size against the original M1 boundary and immediate
  M4 reference. Reuse gas only when executable identity and original call
  conditions justify it; otherwise measure the affected paths. Explain the
  already-accepted M1 deltas and remaining size limits.
- Update `hook-composition.md` to the implemented design, final acceptance
  evidence, and remaining limits. Replace stale implementation descriptions
  and provisional language. Make its knowledge-base version self-contained;
  resolve references to soon-to-be-removed plans and trackers into substantive
  text or links to surviving sources/guides and the qualified revision.
- Finalize the export manifest and removal list. Maintain the distinction
  between demonstrated hook extensibility and future V2.6 tranching design.

**Complete when:** final compatibility is attributable to an exact source and
toolchain, all required criteria have evidence, and the updated spec and
maintained guides are ready for the final handoff.

## M5-06: Handoff export and release-tree cleanup

**Work**

- Create a dated handoff under `../hook-refactor-handoff/<run-id>/`, outside
  `v2-protocol`. Save the final updated spec as `hook-composition.md` for the
  user's knowledge base, with its qualified source revision and SHA-256.
  Preserve the final qualification record and referenced evidence there too,
  so deleting tracked evidence indexes does not strand the proof.
- Read back and verify the exported files and manifest before removing their
  repository copies. Resolve spec links for the handoff context. The user
  performs the knowledge-base transfer; do not publish it elsewhere.
- Remove only the enumerated refactor working documents: `hook-composition.md`,
  `hook-behavior-map.md`, and the `hook-refactor-*` baseline/design/milestone/
  plan/tracker/results files under `docs/specs/`, including M5's own records.
  Do not delete unrelated documentation or the untracked user references.
- Check all tracked references for broken links or dependencies on removed
  working documents. Keep maintained guides, source, canonical tests, release
  records, and deployment inventories intact except for justified guide/link
  updates already in scope. A checkout of the final tree must stand on its own.
- Verify cleanup changed no qualified compiler/test inputs. Retain the matching
  test results for documentation-only removal; rerun affected checks if inputs
  changed. Record final task status and the signed cleanup commit in the
  external handoff receipt, without recreating a deleted tracker in the repo.

**Complete when:** the user has a verified updated spec and qualification
handoff outside the repository, the release tree contains maintained docs
without the working records, and the final signed checkpoint is ready for user
review and push. V2.6 tranching assessment begins only as subsequent work.

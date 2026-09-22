# M2 plan: shared hook behavior

- Milestone: [M2 — Shared behavior](hook-refactor-milestones.md#m2--consolidate-common-behavior-across-the-existing-hooks).
- Task status and evidence: [M2 tracker](hook-refactor-m2-tracker.md).
- Approved M1 handoff: `d454f26fcf54db847657ef08c355e75e72d4356a`.
- Behavioral source baseline: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`, with
  the explicit Foundry settings amendment recorded in the M1 baseline.

M2 makes the three existing V2.5 hook templates use one implementation of
their shared behavior. The [spec](hook-composition.md) defines the scope;
the approved [M1 design](hook-refactor-m1-design.md) defines the internal
interfaces, ordering, storage adapters, and compatibility requirements.
This plan defines the work. The tracker owns execution status and evidence.

M1 has been reviewed and pushed by the user. This plan and tracker are planning
deliverables; M2 implementation begins after the user's instruction to start.

## Outcome and boundaries

Add `src/access/BaseHooks.sol` for common coordination and defaults, reusing
`BaseAccessControls` for credentials/administration and `MarketConstraintHooks`
for bounds and the default APR/reserve calculation. All three templates adopt
each extracted behavior in the same task, removing their superseded bodies.
Behaviors not yet extracted keep their current implementation until their
own task; there is no retained old/new production implementation or test oracle.

Retain packed, template-specific state, constructor and creation encodings,
public tuple adapters, callback flags, family strings, and periodic ABI revision
2. Preserve existing caller-check differences and error/event ordering. A
feature rule runs through an explicit extension point; inheritance does not
resolve competing strategies automatically.

Fixed and periodic schedule, proposal, and management logic may remain in the
concrete contracts. M2 connects them to the common coordinators, including both
periodic APR routes. M3 extracts reusable term policies and their management
extension points. M4 supplies the larger composition/default-replacement proof;
M5 qualifies the final refactor and integration documentation. Public type-file
moves can wait until M3 unless an actual import dependency requires them sooner.

Tranche economics, repayment/default changes, market accounting or batching
changes, new market interfaces, runtime modules, compatibility bitflags, and
unrelated tooling are outside this milestone. The early extension test is an
independent rule, not a proposed production feature.

## Deliverables and review workflow

Deliver the shared implementation, adopted templates, consolidated canonical
tests, a small extension probe, and `hook-refactor-m2-results.md`. The results
record is created during execution; it will identify source/settings, coverage
ownership, commands, compatibility/size/gas comparisons, and the M3 handoff.
Raw exports and receipts belong in ignored `audits/hook-refactor/m2/<run-id>/`,
with relative paths and hashes recorded in the maintained results. Preserve
M1's evidence as the reference, rather than overwriting it.

Each task is a checkpoint. The user's explicit review instruction applies to
**any checkpoint containing Solidity edits, including test Solidity**:

1. Complete the task and its relevant verification; update the tracker and
   evidence, then stage the intended files.
2. Present the staged scope, behavior/compatibility changes, checks and results,
   and any unresolved tradeoff. Mark the task `Ready for review` and stop before
   committing or stacking the next implementation task on that diff.
3. After approval of that staged diff, commit with the repository-selected SSH
   key as `kethcode <dave@wildcat.finance>` and verify the signature. Substantive
   changes after review require renewed review of the updated staged diff.

Documentation-only checkpoints can be signed and committed under the existing
authorization. Record the completed task and evidence in its checkpoint; a
later tracker update can add its hash without a self-referential commit. The
user reviews and pushes at milestone end, and may give feedback at any staged
checkpoint. Do not push or begin M3 as part of M2. Exclude the user's untracked
reference PDF and lifecycle sketch from every checkpoint.

## Task sequence

| Task | Deliverable | Depends on |
| --- | --- | --- |
| M2-01 | Execution identity, reusable evidence, and test-ownership map. | Approved M1 and instruction to start M2. |
| M2-02 | Shared construction, registration/access configuration, and minimum management. | M2-01. |
| M2-03 | Shared deposit/transfer behavior and views, with the early extension probe. | M2-02. |
| M2-04 | Shared queue, closure coordination, and currently empty callbacks. | M2-03. |
| M2-05 | Shared APR coordination and effective-value checks on both periodic routes. | M2-04. |
| M2-06 | Milestone qualification, evidence reconciliation, and M3 handoff. | M2-01 through M2-05. |

Every implementation checkpoint must compile with all three concrete templates.
Consolidate a domain's equivalent test assertions when its production behavior
moves, retaining distinct term cases in their owning suites. Do not postpone
test ownership or source deduplication to a final cleanup task.

## M2-01: Execution identity and coverage ownership

**Work**

- Record the execution starting revision, relevant working-tree inputs,
  submodules, and effective default/deploy settings. Relate them to the approved
  M1 handoff and its Foundry settings amendment; do not silently reset the
  behavioral baseline to a later revision.
- Inspect M1's [baseline receipts](hook-refactor-m1-baseline.md). Reuse matching
  test/build evidence; regenerate only missing or mismatched comparisons. M1's
  698-test result is historical evidence, not M2's required final test count.
- Assign the existing properties to their post-extraction owner. Plan a concrete
  `test/access/BaseHooks.t.sol` suite with runtime matrices for common behavior,
  and `test/access/HookExtensions.t.sol` for the small extension probe. These
  names can be adjusted to fit the implementation without creating competing
  owners. Shared helpers under `test/shared/` have no test entrypoints.
- Keep provider/cache properties in `BaseAccessControls.t.sol`, bounds and
  reserve mathematics in `MarketConstraintHooks.t.sol`, and distinct term and
  proposal properties in the fixed/periodic suites. Identify any moved gas
  scenario by its equivalent setup and call boundary, not only its test name.
- Establish or qualify a matching `yarn lint:check` receipt before source edits;
  M1 did not claim a lint pass. Record any existing failures without expanding
  this refactor into unrelated formatting work. Start the M2 results record.

**Complete when:** the execution identity and evidence disposition are recorded,
each affected behavior has a planned test owner, and baseline check failures
or missing comparisons have an explicit disposition. This task does not redo
M1's architecture work or add speculative tests.

## M2-02: Shared construction, registration, and minimums

**Work**

- Add `BaseHooks`, inheriting the existing access and constraint owners once.
  Move common instance initialization and the deployment-config immutable into
  it; keep each public constructor `(address,bytes)` and its exact flags.
- Implement the [packed adapters](hook-refactor-m1-design.md#access-adapters-and-authentication)
  and [creation contract](hook-refactor-m1-design.md#creation).
  Store each market configuration once in its existing owner. Preserve open/
  fixed's separate deposit-dispatch mapping and periodic's inline flag; common
  hot-path reads must not fetch the separate dispatch mapping unnecessarily.
- Share creation coordination, access-bit capture/validation, supporting flags,
  minimum events, and final flag merge. Keep staged decoding in the concrete
  templates: factory guard, bounds, administrator, term validation/event,
  minimum/optional fields, packed write, then `_onMarketConfigured` in the
  order specified by M1. The future market has no deployed code at this point.
- Share minimum updates with the current authority/registration/dispatch checks.
  Periodic's `uint96` narrowing stays after those checks; open/fixed retain
  `uint128`. Keep the public tuple getters and unknown-market results unchanged.
- Move common error/event declarations to their owner and update affected source
  qualifications mechanically. An inherited error's Solidity qualification may
  change even though its selector and presence in the concrete ABI do not.

**Verification:** consolidate equivalent constructor, registration, flags, and
minimum properties into the common suite. Retain template-specific formats;
add targeted partial-word/width and competing-failure cases where decoding
moves. Run affected access suites, real factory deployment/configuration,
administrator-transfer, and lens checks. Compare all three raw/semantic ABIs,
packed layouts, and deployment sizes; inspect creation storage work.

**Complete when:** all templates use the common initialization/minimum rules,
the existing public formats and guard/event order have evidence, and each
configuration still has one authoritative packed owner. Other callbacks may
remain concrete until their subsequent tasks.

## M2-03: Deposit, transfer, views, and early extension probe

**Work**

- Move deposit and transfer coordinators/defaults into `BaseHooks`, with
  registration before default processing and the additional rule afterward.
  Preserve minimum scaling/rounding, local blocks, disabled-transfer priority,
  credential/cache writes, known-lender events, and exact-wrapper exemptions.
- Share transfer-policy queries through the same access adapters. Combine the
  default recipient decision with `_featureTransferRecipientAllowed`; retain
  the global transfer-disable view's existing permanent promise.
- Keep exemption returns inside the default transfer processor so known lenders
  and wrappers still reach `_checkTransfer`. Reuse the existing access helpers
  once; do not duplicate credential machinery in the coordinator or feature.
- Add one small test-only recipient restriction through `_checkTransfer` and
  the corresponding view extension. Check acceptance and rejection, including
  a credential-exempt recipient, plus rollback of credential/known-lender
  changes when the added rule rejects. Use observable state/results, not an
  internal-call counter. Keep this probe small; multiple features, state/API
  isolation, and replacement strategies remain M4 work.

**Verification:** use the common runtime matrix for the three production
templates, keeping the provider suite as the credential implementation's
owner. Run the extension probe and affected wrapper/dispatch integrations.
Compare ABIs, deployment sizes, and M1's deposit/transfer gas scenarios, with
the same caller, cache state, isolation setting, and measurement boundary.

**Complete when:** shared processing and views replace the copied bodies in all
three hooks, existing exemptions retain their intended scope, and the small
feature proves an additional rule can run and reject through the new seam.

## M2-04: Queueing, closure coordination, and empty callbacks

**Work**

- Share queue coordination in the order registration, schedule, withdrawal
  access, additional check. Open's adapter always requires access when the
  callback is invoked; fixed/periodic preserve their stored requested access.
  Queueing does not mark a previously unknown lender known.
- Connect existing fixed/periodic schedule bodies through their deliberate
  internal overrides, retaining maturity/window/closed-state behavior. The
  underlying market continues to choose batches, expiry, and accounting.
- Share closure coordination with separate validation and effects. Open stays
  an unguarded no-op; fixed retains registration and its existing OR permission
  before the maturity update; periodic retains registration, the closed flag,
  proposal cancellation, and event order. Keep these term bodies concrete.
- Consolidate the six currently empty callbacks into shared external entries
  with empty virtual internal defaults. Preserve existing caller behavior,
  flags, and calldata/memory distinctions. Do not activate new callbacks or
  add credential checks to executing an already queued withdrawal.
- Retain the market-owned closure reset of APR/reserves and existing temporary
  reserve state. Closure does not synthesize an APR callback.

**Verification:** consolidate shared queue-access/no-op properties and retain
distinct fixed/periodic schedule and closure properties. Cover permission,
boundary, proposal cancellation, and unknown-caller differences. Run affected
dispatch and standard/revolving lifecycle cases, then compare ABI, sizes, and
M1's queue/closure gas scenarios.

**Complete when:** all three hooks share these coordinators/defaults, term
differences remain explicit single implementations, and batching, schedule,
closure, and empty-callback behavior match the approved reference.

## M2-05: APR strategy and both periodic execution routes

**Work**

- Extract the existing `MarketConstraintHooks` APR body into the virtual
  `_applyDefaultAprUpdate`, retaining its one calculation/state/event owner.
  Move external coordination to `BaseHooks`: select `_applyAprUpdate`, construct
  the requested/effective `AprChange`, run `_checkAprChange`, return that pair.
- Keep fixed's maturity guard ahead of the selected default. Periodic authenticates,
  cancels proposals on increases only, delegates equal/increased APRs, and
  deliberately skips the default for proposal-backed reductions. Document
  these choices near their overrides rather than relying on `super` order.
- Route ordinary and dedicated periodic reductions through one proposal
  execution helper and the same effective-value check. Keep the dedicated
  APR-only ABI, unchanged reserves, explicit route, and empty calldata slice.
  Preserve proposal checks, deletion/events, and rollback if validation fails.
- Keep open/fixed's existing unguarded APR callback behavior. Do not add a
  second calculator, clear temporary-reserve state on a periodic reduction,
  or change proposal creation/expiry semantics to simplify the refactor.

**Verification:** keep bounds/temporary-reserve mathematics in their existing
suite and term-specific APR/proposal cases in theirs. Add a focused validator
probe showing both periodic routes check the values actually applied and roll
back proposal effects on rejection; this is path coverage, not M4's full
replacement proof. Run relevant real-market APR/borrower-account/dispatch cases.
Compare ABI, sizes, and the ordinary/dedicated M1 gas scenarios; explicitly
check the absence of skipped default state/events on periodic reductions.

**Complete when:** one default APR implementation and one shared effective
validation seam serve all intended paths, with both periodic routes covered
and their distinct reserve semantics preserved.

## M2-06: Qualification and M3 handoff

**Work**

- Reconcile the behavior-to-test map against the implemented suites. Every
  moved common property has one owner and exercises all applicable templates;
  distinct properties remain. Explain test-count changes from consolidation.
  Check that no copied extracted bodies or inherited test entrypoints remain.
- Confirm the real factory, dispatch, administrator transfer, borrower-account,
  lens, wrapper, and standard/revolving matrix paths use the refactored artifacts.
  Fill demonstrated coverage gaps rather than adding a parallel integration suite.
- Run the required qualification commands on the completed M2 tree:

  ```sh
  forge test
  yarn test:fixed
  FOUNDRY_PROFILE=deploy forge test
  yarn lint:check
  ```

  Compare any lint failures to the identified M2-01 baseline. Do not claim a
  failed command passed or leave a refactor regression unexplained. Repeat
  affected checks after fixes; otherwise do not rerun completed checks without
  a source/settings change or an unresolved concern.
- Complete the [ABI comparison](hook-refactor-m1-design.md#metadata-and-expected-abi-comparison):
  retain raw diffs and allow only the specified empty-to-named top-level callback
  inputs. Existing nonempty names, tuple fields/widths, selectors, errors/events,
  mutability, constructors, flags, family identity, and periodic revision stay
  compatible. Record new bytecode identities without rewriting deployment inventories.
- Record final runtime, creation, `STOP || initcode`, and constructor-payload
  size boundaries; confirm actual factory deployment. Periodic starts with
  only 2,577 bytes of stored-initcode headroom, so do not infer safety from
  runtime size or source deduplication. Reconcile packed storage layouts and
  M1's representative gas cases against the final M2 source/settings identity.
  Reuse matching interim measurements; record deltas and investigate material
  increases, including adapter reads, creation writes, and code growth. Surface
  unresolved tradeoffs in staged review rather than silently accepting them.
- Finish the results/tracker and record M3's remaining term-policy extraction,
  fixed setter and periodic proposal extension points, any type moves, and
  the existing tests/measurements that protect those changes. Keep M4/M5
  obligations explicit; an M2 pass does not establish full composability or
  future tranching compatibility.

**Complete when:** all M2 tasks have reviewed signed checkpoints where required,
shared behavior is adopted by all three templates without parallel copies,
the early probe and required test runs pass, lint has no new failures, and all
results have attributable evidence. Compatibility has no unresolved regression,
cost changes are explained, and the user has a complete milestone to review
and push before M3 planning.

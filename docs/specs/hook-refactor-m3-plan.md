# M3 plan: reusable term policies

- Milestone: [M3 — Extract term behavior](hook-refactor-milestones.md#m3--extract-term-behavior-and-make-overrides-explicit).
- Task status and evidence: [M3 tracker](hook-refactor-m3-tracker.md).
- Approved M2 handoff: `c54e57312e63ceadee88492d8c47ae632b876b0b`, reviewed
  and pushed by the user on 2026-09-23.
- M2 implementation and qualification source: `549bfaa8d01e27f30dca97b5858f5e8f22d75937`.
- Original behavioral reference: [M1 baseline](hook-refactor-m1-baseline.md),
  including its explicit Foundry settings amendment.

M2 put shared behavior in `BaseHooks`. M3 makes the remaining fixed and periodic
behavior reusable, then adds the management extension points specified in the
[M1 design](hook-refactor-m1-design.md#closure-term-management-and-proposals).
The [M2 handoff](hook-refactor-m2-results.md#m3-handoff) supplies the starting
implementation and measurements. The [spec](hook-composition.md) still defines
the overall scope. This plan owns the work; the tracker owns execution status.

The user accepted M2, reviewed this plan, and authorized M3 execution. The
tracker records implementation progress and each staged Solidity review.

## Outcome and boundaries

Separate relocation from adding extension points so each has its own reviewable
checkpoint. The existing V2.5 templates retain their behavior and public APIs.

| Component | M3 result |
| --- | --- |
| `BaseHooks`, `BaseAccessControls`, `MarketConstraintHooks` | Continue owning the shared coordinators, access machinery, and default APR/reserve calculation. Reuse their M2 implementations. |
| `FixedTermPolicy` | Abstract reusable owner of fixed packed configuration, dispatch state, term validation/management, withdrawal schedule restriction, APR guard, and closure behavior. |
| `PeriodicTermPolicy` | Abstract reusable owner of periodic packed configuration, proposals, schedule/window queries, proposal management, both APR execution routes, and closure behavior. |
| `FixedTermHooks`, `PeriodicTermHooks` | Thin concrete assemblies with the existing constructors, flags, family/revision identity, and public type adapters. Each adopts its policy in the same checkpoint that moves the implementation. |
| `OpenTermHooks` | Keeps its existing packed adapters and public formats over `BaseHooks`; no separate open schedule policy is needed. |

Use `src/access/FixedTermPolicy.sol` and `src/access/PeriodicTermPolicy.sol` unless
an actual import constraint warrants a mechanical path adjustment. Both policies
inherit `BaseHooks` abstractly. The final concrete composition supplies the
`BaseHooks` constructor arguments and deployment flags once. There is one shared
base state instance and one owner for each term's configuration/proposal state.

Fixed and periodic schedules remain alternative term choices. Other features
can participate through the shared action interfaces, with the concrete
composition explicitly resolving overlapping overrides. M3 does not add a
policy-count limit or make inheritance order decide competing calculations.
This is reuse when developing a new hook deployment, not an upgrade mechanism
for already deployed hooks.

The three new internal extension points have empty defaults:

```solidity
function _validateFixedTermChange(address market, uint32 previousTime, uint32 newTime)
  internal view virtual;
function _afterFixedTermChange(address market, uint32 previousTime, uint32 newTime)
  internal virtual;
function _checkPeriodicProposal(
  address market, uint16 proposedApr, uint32 responseStart, uint32 responseEnd
) internal view virtual;
```

These extend management operations. Existing shared callback checks, including
`_checkAprChange`, continue to apply at their M2 boundaries. The fixed setter
checks do not automatically cover creation or early closure; those actions keep
their existing initialization/closure extension points. Periodic proposal
validation does not replace validation when the APR is actually applied.

No tranching economics, repayment/default policy, core accounting/batching,
new market/factory interfaces, runtime hook stack, capability-ownership flags,
deployment publication, or unrelated tooling changes belong in M3. M4 retains
the larger composition/default-replacement proof; M5 retains final refactor
qualification and contributor documentation. Do not add another implementation
of existing behavior to support those later milestones.

## Deliverables and review workflow

Deliver the two adopted term policies, necessary public type moves, management
extension points with focused behavioral probes, and `hook-refactor-m3-results.md`.
Create the results record during execution. Keep raw manifests, compiler exports,
logs, and comparison receipts under ignored `audits/hook-refactor/m3/<run-id>/`;
record their relative paths and hashes in the maintained results. Preserve M1
and M2 evidence intact.

Each task is a checkpoint. The existing user instruction applies to **every
checkpoint containing Solidity edits, including tests**:

1. Complete the task, relevant verification, and evidence; update the tracker
   and stage the intended diff.
2. Explain the staged scope, behavior, checks, and cost/compatibility findings.
   Mark it `Ready for review` and stop before committing or beginning the next
   implementation task on top of it.
3. After approval, commit as `kethcode <dave@wildcat.finance>` with the
   repository-selected SSH signing key and verify the signature. Substantive
   changes after review require review of the revised staged diff.

Documentation-only checkpoints may be signed and committed under the existing
authorization. Record completion in its checkpoint and add the commit hash in
the next tracker update. The user reviews and pushes at milestone end. Do not
push or begin M4 under M3's execution authorization.

Keep `DAVE_VOICE_SKILL_V5_1.md`, the reference PDF, and the lifecycle sketch out
of all commits. For code comments, retain technical terms, function/variable
names, and useful branch explanations while following the user's voice guide.

## Task sequence

| Task | Deliverable | Depends on |
| --- | --- | --- |
| M3-01 | Qualify the M2 handoff and map moves, consumers, tests, and measurements. | Approved M2 and instruction to start M3. |
| M3-02 | Extract and adopt `FixedTermPolicy`, preserving existing behavior. | M3-01. |
| M3-03 | Add fixed-term setter validation/effect extension points and probes. | M3-02. |
| M3-04 | Extract and adopt `PeriodicTermPolicy`, preserving its complete lifecycle. | M3-03. |
| M3-05 | Add periodic proposal validation and focused rejection/rollback coverage. | M3-04. |
| M3-06 | Qualify M3, reconcile explicit integration choices, and hand off to M4. | M3-01 through M3-05. |

Every implementation checkpoint must compile all three concrete templates and
their existing consumers. Remove moved implementations/declarations as their
policies are adopted. Keep distinct properties in their current owning suites;
do not create a parallel policy test suite containing copies of existing tests.

## M3-01: Handoff identity and move inventory

**Work**

- Record the execution revision, working-tree inputs, submodules, tool hashes,
  effective default/deploy settings, and signing identity. Qualify M2's retained
  evidence against those inputs; M2's 707-test result is prior evidence, not a
  new M3 pass. Reuse matching receipts rather than rerunning an unchanged suite.
- Inventory declarations and state moving to each policy, concrete adapters
  that remain, type re-exports, and source consumers. Include lens imports,
  test-only derivatives, qualified errors/events, and static function references
  such as `abi.encodeCall` targets that may need their declaration owner.
- Map fixed setter, queue, APR, closure, and periodic proposal/window/execution
  properties to their existing tests. Identify the small new management probes
  and any demonstrated coverage gap without duplicating M2's common matrices.
- Qualify M2's ABI/layout/size/gas and lint records. Preserve M1 as the original
  compatibility reference and M2 as the immediate cost comparison. Check for
  comparable fixed-setter and periodic-proposal measurements; capture missing
  cases against the accepted M2 implementation before changing those paths,
  using existing fixtures and consistent transaction/state boundaries.
- Start the M3 results record, including evidence disposition and move map.

**Complete when:** inputs and prior evidence are attributable, moved behavior
and consumers have named owners, and measurement gaps have a disposition.
This does not redo the architecture decisions or start Solidity extraction.

## M3-02: Fixed policy extraction

**Work**

- Move fixed configuration/dispatch mappings, term constants/errors/events,
  decoding/initialization, access adapters, setter, schedule restriction, APR
  strategy/guard, and closure helpers into `FixedTermPolicy`. Preserve the
  setter body at this checkpoint; its new extension calls belong in M3-03.
- Make `FixedTermHooks` adopt the policy immediately. Keep its `(address,bytes)`
  constructor, exact flags, `version()`, artifact path, and concrete
  `getHookedMarket(s)` tuple adapters over the same authoritative mapping.
- Move `HookedMarket` to `src/access/types/FixedTermHookTypes.sol` if needed to
  avoid a policy/concrete import cycle. Re-export it from `FixedTermHooks.sol`,
  keeping the existing name, field order/widths, and ABI `internalType`.
  Adjust declaration-owner qualifications mechanically where Solidity requires
  it; do not keep duplicate errors/events to preserve old qualifications.
- Preserve the named `_validateFixedAprUpdate`, `_validateFixedCloseMarket`,
  and `_applyFixedCloseMarket` helpers and their deliberate ordering. APR still
  checks `fixedTermEndTime` before `_applyDefaultAprUpdate`, with no new caller
  guard. Queueing still checks registration, then maturity, then access.
  Closure still uses the existing early-permission OR rule and maturity update.

**Verification:** run the fixed suite, shared `BaseHooksTest` matrix, affected
access/constraint tests, and real factory, lens, administrator/borrower-account,
wrapper, and standard/revolving term integrations. Check consumers still import
the concrete public type and artifacts. Compare ABI, packed layout, all three
template sizes, and affected fixed creation/setter/queue/APR/closure costs with
M2 and M1. Reuse gas measurements only when executable identity and measurement
conditions justify doing so.

**Complete when:** fixed behavior has one reusable policy owner, the existing
template uses it, and public formats, ordering, behavior, and measured costs
have evidence. No new management extension behavior is mixed into the move.

## M3-03: Fixed setter extension points

**Work**

- In the policy's `setFixedTermEndTime`, preserve administrator, registration,
  term-reduction permission, and no-extension checks in their current order.
  Preserve equal-time behavior and acceptance of earlier timestamps, including
  past ones. Call `_validateFixedTermChange` after those checks and before the
  write; write maturity, emit `FixedTermUpdated`, then call `_afterFixedTermChange`.
- Add the empty virtual defaults with the M1 signatures. Keep the new time in
  the same packed configuration read by queueing, APR, closure, and queries.
  Do not route early closure through the administrator-only setter to reach
  these checks; document the distinct lifecycle boundaries.
- Add a small test-only derivative and focused cases in the existing fixed
  behavior owner. Demonstrate a meaningful additional validation rule, an
  after-change effect that observes the updated maturity, and rejection before
  and after the write with atomic rollback. Check native guard priority when
  the extension would also reject. Assert observable state/results and existing
  event behavior, not an internal-call counter or another copy of the setter.

**Verification:** retain the existing fixed setter/authority cases and run the
new extension cases plus affected fixed lifecycle/shared/integration checks.
Prove the unchanged production default and the overridden behavior separately.
Recheck ABI, layout, fixed deployment sizes, and setter costs; an empty virtual
default is not assumed to compile away without inspecting the result.

**Complete when:** a derived hook can validate and react to a term update
without copying its setter, while the production template keeps its previous
behavior and rejected updates leave no partial term or feature state.

## M3-04: Periodic policy extraction

**Work**

- Move periodic packed configuration, inline dispatch/minimum adapters,
  `_pendingAprChanges`, constants/errors/events, decoding/initialization,
  schedule validation/queries, proposal management, APR strategies, and closure
  into `PeriodicTermPolicy`. Keep the proposal body unchanged until M3-05.
- Adopt the policy from `PeriodicTermHooks` in the same checkpoint. Preserve
  its constructor, exact flags, family string, `templateVersion() == 2`, artifact
  path, and concrete configuration tuple adapters. Keep proposal query formats
  and validation with one owner, using thin public type adapters where needed.
- Move/re-export `HookedMarket`, `PendingAprChange`, and
  `PendingAprChangeStorage` through `src/access/types/PeriodicTermHookTypes.sol`
  as needed. Account for the narrow `IMarketApr` query interface without a
  circular dependency or duplicate declaration. Preserve existing public
  imports and update affected owner-qualified references mechanically.
- Keep proposal creation, replacement, query, execution, APR-increase
  cancellation, and closure on the same proposal mapping. Preserve fixed
  response-window bounds, inclusive/exclusive boundaries, expiry behavior,
  strict reductions, and unpaid-withdrawal checks with their current priority.
- Retain `_executePeriodicReduction` as the shared execution helper. Ordinary
  reductions preserve reserves and skip `_applyDefaultAprUpdate`; equality
  retains the proposal and increases cancel it before using that default.
  Both ordinary and dedicated routes still reach `_checkAprChange`. The
  dedicated ABI returns only APR, validates current reserves, and supplies an
  empty calldata slice even when the caller appends data.
- Preserve `_validatePeriodicCloseMarket` and `_applyPeriodicCloseMarket`:
  registration, closed flag, cancellation/deletion, then closure event.
  Closure opens the withdrawal schedule without bypassing access checks and
  does not clear temporary-reserve state or synthesize an APR callback.

**Verification:** run periodic/common suites, all existing `AprValidationTest`
cases and the configuration probe, plus factory/lens/authority/borrower-account,
wrapper, and standard/revolving APR/withdrawal/closure integrations. Compare ABI,
packing, all three template sizes, and affected creation/window/queue/proposal/
ordinary APR/dedicated APR/closure costs against the qualified references.

**Complete when:** the entire periodic lifecycle has one reusable owner and the
concrete template uses it, with both APR routes and existing public consumers
verified. Moving only the callback while leaving a second proposal owner does
not complete this task.

## M3-05: Periodic proposal extension point

**Work**

- Add empty virtual `_checkPeriodicProposal`. Invoke it after existing
  administrator/registration/closed/window/bounds/strict-reduction checks and
  response-window calculations, before canceling an old proposal or storing
  and emitting the new one. Pass the exact computed `uint32` window bounds;
  retain narrowing and overflow behavior.
- Add a small test-only proposal rule and focused cases under the existing
  periodic behavior owner. Cover accepted creation/replacement, additional
  rejection with and without an existing proposal, exact proposed APR/window
  context, and native guard priority. Rejection preserves the old proposal and
  its response bounds; it must not commit cancellation or replacement effects.
- Keep `_checkAprChange` and its both-route validation/rollback tests in place.
  A proposal's earlier acceptance cannot substitute for execution validation.
  Reuse the existing test-only validation infrastructure where appropriate;
  keep the larger changing-feature/composition proof in M4.

**Verification:** run the proposal/window state-machine cases, the new focused
rule, both periodic APR routes and rollback probes, and affected real-market
integrations. Recheck raw ABI, proposal/configuration packing, periodic size
headroom, and proposal costs with the empty production default.

**Complete when:** a derived hook can reject proposal creation/replacement at
the documented boundary without copying proposal management or changing the
production lifecycle. Execution validation remains effective on both routes.

## M3-06: Qualification and M4 handoff

**Work**

- Reconcile the move/ownership map against the final tree. Shared defaults,
  fixed behavior, and periodic behavior each have one implementation. Concrete
  adapters read that state directly; no mirrored configuration, copied legacy
  implementation, or inherited test entrypoints remain. Explain any test-count
  change by properties and ownership.
- Check consequential overrides against the behavior map: retained/skipped
  defaults, state/event ownership and order, caller differences, queue/access
  rules, both APR routes, and separate creation/closure/management boundaries.
  Keep comments grounded in the actual functions and variables.
- Run the required commands on the completed M3 tree:

  ```sh
  forge test
  yarn test:fixed
  FOUNDRY_PROFILE=deploy forge test
  yarn lint:check
  ```

  Compare lint with the qualified M2 baseline, including standalone Solhint if
  the package command stops at Prettier. Format touched paths only. Repeat
  affected verification after fixes; otherwise reuse completed matching checks.
- Compare raw/semantic ABIs to M2 and M1. M3 should preserve the M2 ABIs,
  including existing parameter names. M1's narrow empty-to-named callback-input
  allowance does not authorize further renaming. Retain selectors, tuple and
  `internalType` formats, errors/events, mutability, constants, constructor/
  creation encodings, flags, family strings, and periodic revision 2.
- Export raw/normalized layouts. Preserve field packing, widths, and one owned
  configuration/proposal representation. Distinguish compiler/declaration-owner
  changes from actual slot changes; record and justify any latter change under
  M1's new-deployment design rather than treating this as a proxy migration.
- Confirm real template/market deployment and all existing integration paths.
  Measure runtime, creation, `STOP || initcode`, and constructor-payload limits;
  M2 leaves periodic only 1,899 bytes of stored-initcode headroom. Reconcile M1's
  representative callbacks and M2's creation/minimum/query/management evidence
  against final source/settings. Reuse identical-artifact measurements or
  regenerate unmatched ones with consistent fixtures/boundaries in an isolated
  checkout. Preserve explicit exclusions; never restore copied oracle suites
  to the canonical test tree. Explain material size/gas changes in review.
- Finish the results/tracker and identify M4's components and protecting tests:
  three-/four-policy composition, overlapping checks, feature state/API
  isolation, deliberate default replacement and skipped effects, callback
  activation, exemptions, lifecycle interactions, and rollback. Record any
  evidence-backed interface limitation; do not claim M3 proves arbitrary
  composition or future tranching compatibility.

**Complete when:** all M3 implementation checkpoints are reviewed and signed,
the two policies are adopted without parallel implementations, management
extension behavior and unchanged production behavior have evidence, required
tests pass, and lint introduces no regression. No unresolved behavior or
compatibility regression remains; cost changes are explained and design
tradeoffs are recorded for review. The user has a complete milestone to review
and push before a separate M4 plan/tracker is prepared.

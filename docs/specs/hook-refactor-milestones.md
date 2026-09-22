# Hook refactor milestones

- Status: M1 complete and ready for milestone review. M2 planning and refactor
  implementation have not started.
- Scope: the [agreed hook composition spec](hook-composition.md), informed by
  the [V2.5 behavior and override map](hook-behavior-map.md).
- Source baseline: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

These milestones describe reviewable outcomes and completion criteria. M1 has
an [execution plan](hook-refactor-m1-plan.md) and
[tracker](hook-refactor-m1-tracker.md); task breakdown and tracking for later
milestones follow separately. A milestone may contain several implementation
changes; it is not necessarily one commit or pull request.

| Milestone | Outcome | Depends on |
| --- | --- | --- |
| M1 — Interfaces and baseline | Concrete internal boundaries, storage approach, and compatibility evidence to compare against. | Agreed spec and behavior map. |
| M2 — Shared behavior | The three existing hooks use one implementation of their common behavior. | M1. |
| M3 — Term policies and overrides | Fixed and periodic behavior is reusable, with explicit APR and closure integration. | M2. |
| M4 — Extension and composition proof | Independent test features demonstrate additional checks, default replacement, and three-/four-policy combinations. | M3; a small initial probe belongs in M2. |
| M5 — Compatibility qualification | Final interfaces, integrations, deployment limits, costs, and documentation are verified. | M4. |

## M1 — Define interfaces and establish the baseline

Execution: [plan](hook-refactor-m1-plan.md) and
[current status](hook-refactor-m1-tracker.md).
Completed records: [baseline/evidence](hook-refactor-m1-baseline.md) and
[design/M2 handoff](hook-refactor-m1-design.md).

Use the existing behavior map to make the remaining internal design choices:

- Select the shared configuration/state interface and storage approach. Compare
  a common layout with adapters over packed template-specific state, especially
  the periodic hook's single-slot configuration.
- Specify the internal extension signatures and responsibilities for common
  lender actions, withdrawal scheduling, APR strategy selection, closure, and
  creation. Identify where the template adds checks, selects a default, or
  intentionally skips one.
- Assign state and event ownership, including credential bookkeeping,
  temporary reserves, and periodic proposals. Preserve the distinct existing
  caller checks and public configuration formats.
- Decide how implementation revision metadata will be handled while keeping
  integration-facing family strings stable.
- Capture ABI/configuration, runtime/initcode size, and representative gas
  baselines with the pinned toolchain. Use an existing test receipt only if its
  source, toolchain, and settings match; otherwise establish a matching test
  baseline. Historical release receipts are not automatically current evidence.

Baseline evidence should cover common deposit/transfer paths, withdrawal
queueing, APR changes, and closure. Keep generated receipts separate from
maintained protocol source; this does not create a second implementation or a
permanent legacy test oracle.

**Complete when:** the chosen signatures, ownership, storage approach, and
public adapters are concrete enough to implement; the mapped APR/closure
cases can be explained through them; and baseline evidence is identified.
A universal policy-compatibility framework is not a prerequisite.

## M2 — Consolidate common behavior across the existing hooks

Implement the shared foundation and adopt it in all three templates:

- Share deposit and transfer processing, minimum-deposit handling, common
  registration/access initialization, and no-op callbacks where appropriate.
- Reuse, reorganize, or replace `BaseAccessControls` and `MarketConstraintHooks`
  according to M1. Preserve one maintained implementation of each shared rule.
- Keep the existing constructors, creation formats, public views, callback
  configuration, credential behavior, and administrator-transfer behavior.
- Introduce a small test-only additional rule early, exercising a common action
  through a deliberate extension point. This checks that the new foundation
  supports extension before the term-policy extraction is complete.

Term-specific branches may remain in the concrete hooks until M3. The milestone
should not force their extraction merely to make every concrete contract a
thin wrapper immediately.

Validate the affected access/constraint suites and relevant factory, dispatch,
administrator-transfer, lens, and wrapper integrations. Compare ABI and sizes
as the three templates adopt the shared implementation; investigate material
storage/gas changes now rather than waiting for M5.

**Complete when:** all three hooks use the common implementations, the relevant
existing behavior remains covered, the initial extension probe passes, and no
old/new duplicate of the extracted production logic remains necessary.

## M3 — Extract term behavior and make overrides explicit

Move the remaining specialized behavior into reusable components:

- Fixed: maturity validation, queueing restrictions, term reduction, early
  closure, and the APR-reduction guard.
- Periodic: window validation and queries, queueing, closure, proposal creation,
  execution through both routes, cancellation, and proposal queries.
- Keep APR strategy selection explicit. Fixed adds a guard before shared
  behavior; periodic reductions skip the temporary-reserve implementation.
- Preserve closure's links to maturity, window state, and proposal state, plus
  the market-owned APR/reserve reset. Retain adapters for existing public types
  and encodings.

Document the consequential overrides near their implementation: what is called
or skipped, which state/events are affected, and which related entrypoints must
remain consistent. Do not introduce a generic resolver merely to remove these
explicit choices.

Validate the fixed and periodic behavior suites, including both APR routes,
closure, authority, schedule boundaries, and creation flags. Confirm their
integration with both standard and revolving markets and recheck template size.

**Complete when:** the three existing templates are assembled from shared
defaults and reusable term behavior, their existing behavior is preserved, and
the mapped discretionary choices are visible in the integration code and tests.

## M4 — Demonstrate extension and composition

Use small test-only components unrelated to a proposed tranching design:

- Combine two independent additional features with a term policy, including
  overlapping checks on one callback. Add a third feature to demonstrate a
  four-policy composition through new feature and integration code.
- Give a feature its own market-specific state and management/query API, and
  exercise multiple markets on the same instance.
- Replace a designated default deliberately. Check both the selected behavior
  and the absence of state/events from the skipped default, while retaining
  unrelated shared behavior.
- Exercise callback activation for a previously unused action, credential
  exemptions, applicable alternate APR routes, relevant lifecycle interactions,
  and rollback when an additional rule rejects an action.

Keep these properties in the canonical test tree, with concrete owning suites
and shared scenario helpers as described in [the suite rules](../../test/README.md).
The proof should exercise observable behavior, not only inheritance or internal
call counts. No test feature becomes a production product requirement.

**Complete when:** the spec's extension/default-replacement requirements are
demonstrated without routinely editing existing reusable components for each
new feature. If this exposes missing extension points, refine M2/M3 and rerun
the affected checks; a compiling composition alone does not complete M4.

## M5 — Qualify compatibility and document the result

Check the final implementation against the M1 baseline and the spec:

- Compare constructor/configuration encodings, selectors, returned tuples,
  events, errors, callback flags, family identity, and revision metadata.
- Confirm factory deployment, lens decoding, wrappers, administrator transfer,
  borrower-account interactions, and standard/revolving market integrations.
- Run the required default, fixed-seed, and deployment-profile suites in
  [`TESTS.md`](../../TESTS.md), plus applicable repository lint/check commands.
  Identify any pre-existing check failures against the matching baseline.
- Verify actual template deployment, including deployed runtime and the
  `STOP || initcode` storage contract. Compare size and representative gas costs
  and explain material regressions.
- Update the hook integration/contributor documentation with the final extension
  interfaces and examples of adding a rule and deliberately replacing a default.
  Record verification evidence against an exact source/toolchain identity.

**Complete when:** all acceptance criteria have evidence, remaining limitations
are stated, and the refactor is ready for code review with no parallel production
implementation left behind. Publishing/deploying new templates and rewriting
deployment inventories are not part of this milestone.

## Working boundaries

Each implementation milestone must leave the existing templates buildable and
their affected behavior tested. Use focused checks while changing a domain and
the repository-required checks to qualify the final result. Repeat or broaden
checks when changed code or unresolved concerns justify it.

M4 may feed back into M2/M3; the milestones do not make an early interface
decision irreversible. Size and cost measurements also belong alongside the
changes that could affect them, with final confirmation in M5.

This plan does not include tranche economics, repayment/default lifecycle
changes, market ABI changes, runtime feature installation, a mandatory ownership
bitmask, or unrelated tooling integration. Those remain separate work under the
scope boundaries in the spec.

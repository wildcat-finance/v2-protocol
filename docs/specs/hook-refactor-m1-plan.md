# M1 plan: interfaces and baseline

- Milestone: [M1 — Interfaces and baseline](hook-refactor-milestones.md#m1--define-interfaces-and-establish-the-baseline).
- Task status and evidence: [M1 tracker](hook-refactor-m1-tracker.md).
- Starting source revision: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

M1 turns the agreed architecture into concrete internal interfaces, a storage
decision, and a reproducible baseline for the refactor. The
[spec](hook-composition.md) defines the scope and acceptance requirements;
the [behavior map](hook-behavior-map.md) supplies the existing behavior analysis.
This plan defines the work. The tracker is the source of truth for task status.

Creating this plan and tracker does not complete the design or execute any
baseline checks. Existing evidence is reusable only after its identity and
contents have been checked.

## Deliverables

M1 produces two maintained records alongside the plan and tracker:

- `hook-refactor-m1-baseline.md`: source/toolchain identity, compatibility
  inventory, test receipts, size and gas measurements, and evidence references.
- `hook-refactor-m1-design.md`: chosen storage/component organization, internal
  signatures, state/event ownership, adapters, revision metadata, and design
  walkthroughs.

These are planned files, not evidence that already exists. Raw compiler exports,
logs, and measurements belong in an ignored local evidence directory such as
`audits/hook-refactor/m1/<run-id>/`, outside artifact folders cleared by Forge.
The maintained baseline record must identify commands, source/profile identity,
artifact paths, and hashes so a result can be checked or reproduced. It must
not depend solely on a temporary absolute path from one machine.

The work reuses existing contracts and canonical test fixtures. Any small
experiment needed to answer a storage or interface question is identified as
an experiment; M1 does not deliver the production refactor or maintain a second
protocol implementation.

## Task sequence

| Task | Deliverable | Dependencies |
| --- | --- | --- |
| M1-01 | Verified baseline identity and disposition of existing receipts. | Agreed spec, behavior map, and milestone scope. |
| M1-02 | External compatibility inventory and matching build/test evidence. | M1-01. |
| M1-03 | Runtime/initcode sizes and reproducible representative gas cases. | M1-02. |
| M1-04 | Storage, component, and shared-state ownership decision. | M1-02, M1-03. |
| M1-05 | Internal signatures, override responsibilities, and public adapters. | M1-04. |
| M1-06 | Implementation revision metadata decision. | M1-02. |
| M1-07 | Design walkthrough, evidence check, and M2 handoff. | M1-01 through M1-06. |

These dependencies identify the evidence required to finish a task. Drafting
can overlap where useful; for example, metadata does not depend on the storage
decision. M1-07 may expose a gap that sends work back to an earlier task.

## M1-01: Baseline identity

**Work**

- Confirm the intended source revision, working-tree changes relevant to builds,
  submodule revisions, and compiler inputs. Record documentation-only changes
  separately from any source, test, dependency, or build-configuration changes.
- Record the Foundry pin and actual executable version, solc version, relevant
  default/deployment settings, and fuzz timestamp/seed where applicable.
- Locate prior test/build/size receipts. Classify each as reusable, historical,
  or unavailable based on matching inputs and inspectable evidence. A previous
  conversational summary or an old passing count alone is insufficient.
- Start the maintained baseline record, identifying which evidence needs a
  fresh run. Do not silently change the baseline revision if the checkout has
  moved; explain the selected identity and its relationship to the behavior map.

**Complete when:** the baseline identity is recorded, prior receipts have an
explicit disposition, and the remaining measurements/runs are identified.

## M1-02: Compatibility inventory and verification baseline

**Work**

- Export compiler ABIs for the three concrete templates, including inherited
  functions, events, errors, indexed fields, and returned tuple shapes. Preserve
  the raw exports and identify any normalization used for later comparisons.
- Record constructor and market-creation encodings, optional-word behavior,
  numeric ranges, public configuration types, required/optional callback flags,
  and the configuration rules that force additional callbacks.
- Record family strings and currently exposed implementation revision metadata.
  Identify the lens, wrapper, factory, and repository source imports that depend
  on those interfaces. Bytecode hashes identify implementations but are not
  expected to remain unchanged after the refactor.
- Identify the existing tests covering these contracts and the significant
  exceptions in the behavior map. Record coverage gaps requiring later work;
  do not rewrite the already completed behavior analysis.
- Establish matching evidence for the commands in [`TESTS.md`](../../TESTS.md),
  reusing qualified receipts from M1-01 where possible:

  ```sh
  forge test
  yarn test:fixed
  FOUNDRY_PROFILE=deploy forge test
  ```

Record any baseline failures with their source identity and reproduction. They
must remain visible in later comparisons rather than being called refactor
regressions or silently converted into passes.

**Complete when:** each externally observable compatibility surface has a
recorded reference and the required build/test baseline has matching evidence
or a precisely recorded unresolved failure. An unresolved failure affecting
the refactor's acceptance requirements remains open at M1-07.

## M1-03: Size and gas baseline

**Work**

- Record runtime size, creation-code size, and deployment headroom for each
  template under the deployment settings. Account for the actual
  `STOP || initcode` storage contract and any constructor-argument contribution
  to the deployment path; do not compare runtime size alone.
- Define representative per-operation gas cases using the existing fixtures
  and production settings. Record the market/hook configuration, inputs,
  initial state, caller, cache/warmth assumptions, and measured call boundary.
- Measure or identify matching receipts for the cases below. Aggregate gas
  reports may supplement these cases but must not be presented as isolated
  per-operation measurements if they include setup or unrelated work.

| Case group | Representative distinctions |
| --- | --- |
| Deposits | First credentialed entry, known/cached entry, and a positive minimum. |
| Transfers | Unknown credentialed recipient, known recipient, and canonical wrapper. |
| Queueing | Open access/schedule behavior, fixed maturity, and a periodic open window. |
| APR changes | Shared reserve activation/restoration, fixed guard/delegation, periodic ordinary execution, and periodic permissionless execution. |
| Closure | Fixed permitted early closure and periodic closure with a pending proposal. |

Use the same fixture and measurement boundary for later comparisons. If a
small measurement harness is necessary, it must use canonical infrastructure
and remain usable against the refactored implementation. It is not a frozen
legacy implementation or a new parallel test suite.

**Complete when:** the size and gas records are reproducible and comparable,
with configuration-dependent cases labeled and measurements distinguished from
estimates. M5 will qualify final performance; M1 supplies the reference.

## M1-04: Storage and component ownership

**Work**

- Compare a shared internal configuration layout against common logic using
  accessors over template-specific packed state. Account for the periodic
  one-slot configuration and its `uint96` minimum, the open/fixed `uint128`
  minimums, and their existing public tuple formats.
- Choose where instance-wide and market-specific state live. Assign one owner
  to credential caches, known-lender state, registration/access settings,
  temporary reserves, schedules, and proposal state, including their events.
- Specify which responsibilities remain in `BaseAccessControls` and
  `MarketConstraintHooks`, and which move or are reorganized. Preserve one
  implementation of each shared behavior; no contract name is mandatory.
- Record expected storage-read, write, and code-size consequences. Use a small
  compiler/measurement experiment only where needed to answer the choice;
  label partial estimates and leave final-template qualification to later work.

**Complete when:** the design record selects an implementable layout and
component ownership model, explains the tradeoff, and describes adapters for
the unchanged public formats. It must not merely list alternatives for M2 to
resolve.

## M1-05: Internal interfaces and override responsibilities

**Work**

- Specify concrete internal function signatures and context for creation,
  common deposit/transfer processing, withdrawal scheduling/access, APR
  strategy selection, closure, and currently unused callbacks. Include relevant
  visibility, data location, return values, and state effects.
- Distinguish shared coordination, additional validation, default replacement,
  and feature-specific APIs. Identify whether and when the selected default
  runs; a blanket instruction to call `super` is insufficient.
- Describe the concrete open/fixed/periodic assembly and public adapters, with
  caller authentication, callback activation, credential-data handling,
  exemptions, state updates, and event order assigned to a component.
- Trace related entrypoints: both periodic APR execution paths; proposal
  creation/cancellation; closure's direct rate reset; fixed-term changes;
  public transfer-policy queries; and the ordinary queue path used by quarantine.
- Show where an independent feature adds a check and where a developer can
  deliberately replace a default while retaining unrelated shared behavior.
  Preserve room for bespoke feature state and APIs without tranching branches.

**Complete when:** M2/M3 can implement from a concrete internal contract rather
than infer semantics from illustrative component names. The design includes
the actual market-interface limitations and does not depend on a generic
compatibility resolver or ownership-bitmask framework.

## M1-06: Revision metadata

**Work**

- Preserve the three integration-facing `version()` family strings and the
  existing periodic `templateVersion()` ABI.
- Decide whether the periodic implementation revision changes and whether the
  other templates should expose implementation revision metadata. Explain the
  integration effect of any addition; this is a deliberate metadata decision.
- Specify the expected ABI/metadata comparison results and distinguish family
  identification from new bytecode/initcode identities. Existing deployment
  records continue to describe their deployed implementations.

**Complete when:** the design record contains a concrete choice and expected
metadata values/surfaces, rather than deferring that choice to the code changes.

## M1-07: Design walkthrough and M2 handoff

**Work**

- Walk the behavior map through the selected interfaces: shared lender
  processing, access exemptions, schedule checks, fixed APR delegation,
  periodic strategy replacement, both execution routes, and closure effects.
- Check an added rule and a deliberate default replacement using those same
  interfaces. These are design walkthroughs; they do not claim that M4's
  executable multi-policy proofs have already passed.
- Match the maintained baseline record to its raw evidence and identify any
  gaps or baseline failures that prevent meaningful compatibility comparison.
- Check the chosen design against the spec's public-compatibility and single-
  implementation requirements. Update the spec/map only where a clarification
  is needed; do not silently expand their product scope.
- Produce a concise M2 handoff listing the selected boundaries, expected files
  to change, affected tests, cost concerns to measure, and any deliberately
  deferred work belonging to later milestones.

**Complete when:** M1-01 through M1-06 have evidence, the storage/interfaces/
metadata choices are resolved, the walkthrough identifies no unexplained
behavior changes, and no unresolved issue prevents M2 from implementing the
shared foundation. Record completion and the handoff in the tracker.

## Execution boundaries

M1 is design and baseline work. Production refactoring starts in M2. Existing
matching receipts should be reused; new checks should fill evidence gaps or
answer a concrete design question. Small experiments must not become parallel
production implementations.

Follow the checkpoint and user-review workflow in the
[milestone working boundaries](hook-refactor-milestones.md#working-boundaries).
Design decisions, evidence, and any genuine blocker are recorded in the tracker
so the next session can continue from the actual state of the work.

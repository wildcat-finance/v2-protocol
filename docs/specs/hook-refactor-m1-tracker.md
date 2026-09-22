# M1 tracker: interfaces and baseline

- Plan: [M1 execution plan](hook-refactor-m1-plan.md).
- Milestone status: in progress.
- Execution tasks complete: 2 of 7.
- Active task: none.
- Next task: M1-03.
- Intended starting source revision: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

Source and toolchain identity are verified in the [baseline record](hook-refactor-m1-baseline.md).
All three required test runs passed; size/gas measurements remain pending. The plan owns task requirements;
this file owns their current status and evidence references. Each completed task
is checkpointed in a signed `kethcode` commit; the user reviews and pushes.

## Completed groundwork

| Item | Status | Evidence |
| --- | --- | --- |
| Refactor scope and composition approach | Done | [Agreed spec](hook-composition.md): shared defaults, deliberate overrides, and developer-written integration. |
| Existing behavior and discretionary overrides mapped | Done | [Behavior map](hook-behavior-map.md): current callbacks, APR/proposal/closure interactions, and interface limitations. |
| Milestone sequence established | Done | [Milestones](hook-refactor-milestones.md): M1 through M5. |
| M1 plan and tracker prepared | Done | [Plan](hook-refactor-m1-plan.md) and this file. These are planning deliverables, not completed execution tasks. |

## Task status

Use `Not started`, `In progress`, `Done`, or `Blocked`. Mark a task done only
when its completion criteria have linked or identified evidence. Use `Blocked`
for an actual impediment, recording what would resolve it; ordinary unmet task
dependencies remain `Not started`.

| ID | Task | Status | Depends on | Evidence / result |
| --- | --- | --- | --- | --- |
| [M1-01](hook-refactor-m1-plan.md#m1-01-baseline-identity) | Verify baseline identity and audit reusable receipts. | Done | Completed groundwork. | [Identity and receipt disposition](hook-refactor-m1-baseline.md). |
| [M1-02](hook-refactor-m1-plan.md#m1-02-compatibility-inventory-and-verification-baseline) | Capture compatibility inventory and matching verification evidence. | Done | M1-01. | [ABIs, inventory, tests](hook-refactor-m1-baseline.md#verification-receipts). |
| [M1-03](hook-refactor-m1-plan.md#m1-03-size-and-gas-baseline) | Establish comparable size and gas records. | Not started | M1-02. | Pending. |
| [M1-04](hook-refactor-m1-plan.md#m1-04-storage-and-component-ownership) | Decide storage layout and component/state ownership. | Not started | M1-02, M1-03. | Pending. |
| [M1-05](hook-refactor-m1-plan.md#m1-05-internal-interfaces-and-override-responsibilities) | Specify internal interfaces and integration responsibilities. | Not started | M1-04. | Pending. |
| [M1-06](hook-refactor-m1-plan.md#m1-06-revision-metadata) | Decide implementation revision metadata. | Not started | M1-02. | Pending. |
| [M1-07](hook-refactor-m1-plan.md#m1-07-design-walkthrough-and-m2-handoff) | Validate the design/evidence and prepare the M2 handoff. | Not started | M1-01 through M1-06. | Pending. |

## Open design decisions

| Decision | Owning task | Current state |
| --- | --- | --- |
| Shared layout versus accessors over template-specific packed state; public adapters. | M1-04. | Open; alternatives identified in the spec. |
| Responsibilities retained, moved, or replaced in the existing base contracts; one owner for shared state/events. | M1-04. | Open; reuse is permitted, existing contract boundaries are not mandatory. |
| Exact internal signatures, caller checks, ordering, default-replacement boundaries, and alternate-path coverage. | M1-05. | Open; behavior map supplies the required cases. |
| Periodic revision value and whether other templates gain revision metadata. | M1-06. | Open; family strings and the existing periodic getter ABI stay stable. |

Ownership/capability flags are not a required decision or dependency. Tranching
economics and runtime feature installation are outside M1.

## Evidence register

Replace pending entries with concrete paths, hashes, commands, and results in
the maintained records as execution proceeds. Planned filenames below are not
completed artifacts.

| Evidence | Owning task | Status / location |
| --- | --- | --- |
| Source, submodule, toolchain, and profile identity; prior-receipt disposition. | M1-01. | [Baseline record](hook-refactor-m1-baseline.md); raw manifests and hashes recorded there. |
| ABI/configuration inventory and required test receipts. | M1-02. | [Baseline record](hook-refactor-m1-baseline.md): 698 tests / 48 suites pass in each required run; full ABI exports hashed. |
| Runtime/initcode sizes, deployment headroom, gas scenarios, and results. | M1-03. | Pending; planned baseline record and identified raw evidence. |
| Selected layout, state/event ownership, internal signatures, adapters, and metadata decision. | M1-04, M1-05, M1-06. | Pending; planned `hook-refactor-m1-design.md`. |
| Behavior/extension walkthrough and M2 handoff. | M1-07. | Pending; planned design record and completion entry here. |

## Blockers and next action

No blocker has been identified during planning. Execution may reveal missing
receipts, failing baseline checks, or design tradeoffs; record the actual issue
and its effect when that happens.

Next: M1-03, record deployment sizes and per-operation gas from canonical traces.

## Progress log

| Entry | Update |
| --- | --- |
| Planning initialized | Added the M1 plan and tracker. Recorded completed groundwork separately; all seven execution tasks remain unstarted. |
| M1-01 complete | Confirmed source/submodules and pinned tools; captured input/configuration hashes; classified older receipts. Added a local Corepack shim for Yarn without changing package configuration. |
| M1-02 complete | Captured compiler ABIs and compatibility inventory. Default, fixed-seed, and deployment-profile runs each passed 698 tests across 48 suites. Input hashes still match. |

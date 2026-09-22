# M1 tracker: interfaces and baseline

- Plan: [M1 execution plan](hook-refactor-m1-plan.md).
- Milestone status: complete; reviewed and pushed by the user on 2026-09-22.
- Execution tasks complete: 7 of 7.
- Active task: none.
- Next action: review the [M2 plan](hook-refactor-m2-plan.md) and
  [tracker](hook-refactor-m2-tracker.md) before implementation.
- Intended starting source revision: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

Source and toolchain identity are verified in the [baseline record](hook-refactor-m1-baseline.md).
Required tests and size/gas baselines are complete. The plan owns task requirements;
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
| [M1-03](hook-refactor-m1-plan.md#m1-03-size-and-gas-baseline) | Establish comparable size and gas records. | Done | M1-02. | [Size and operation baselines](hook-refactor-m1-baseline.md#deployment-size-baseline). |
| [M1-04](hook-refactor-m1-plan.md#m1-04-storage-and-component-ownership) | Decide storage layout and component/state ownership. | Done | M1-02, M1-03. | [Storage and ownership decision](hook-refactor-m1-design.md#storage-decision). |
| [M1-05](hook-refactor-m1-plan.md#m1-05-internal-interfaces-and-override-responsibilities) | Specify internal interfaces and integration responsibilities. | Done | M1-04. | [Internal contract](hook-refactor-m1-design.md#internal-contract) and compiler signature probe. |
| [M1-06](hook-refactor-m1-plan.md#m1-06-revision-metadata) | Decide implementation revision metadata. | Done | M1-02. | [ABI revision and comparison rules](hook-refactor-m1-design.md#metadata-and-expected-abi-comparison). |
| [M1-07](hook-refactor-m1-plan.md#m1-07-design-walkthrough-and-m2-handoff) | Validate the design/evidence and prepare the M2 handoff. | Done | M1-01 through M1-06. | [Walkthrough](hook-refactor-m1-design.md#final-walkthrough), [handoff](hook-refactor-m1-design.md#m2-handoff), and evidence reconciliation. |

## Design decisions

| Decision | Owning task | Current state |
| --- | --- | --- |
| Shared layout versus accessors over template-specific packed state; public adapters. | M1-04. | Decided: existing packed storage with shared memory adapters; [design](hook-refactor-m1-design.md#storage-decision). |
| Responsibilities retained, moved, or replaced in the existing base contracts; one owner for shared state/events. | M1-04. | Decided: retain access/constraint owners, add shared coordination and reusable term policies; [ownership](hook-refactor-m1-design.md#component-and-state-ownership). |
| Exact internal signatures, caller checks, ordering, default-replacement boundaries, and alternate-path coverage. | M1-05. | Decided: [action defaults/checks, APR strategy, lifecycle, and views](hook-refactor-m1-design.md#internal-contract). |
| Periodic revision value and whether other templates gain revision metadata. | M1-06. | Decided: same families, periodic ABI revision remains 2, no new open/fixed getters. |

Ownership/capability flags are not a required decision or dependency. Tranching
economics and runtime feature installation are outside M1.

## Evidence register

The maintained records identify commands, source/settings, artifact locations,
hashes, and results. Raw generated evidence remains in the ignored directory;
the records and baseline source revision make it reproducible.

| Evidence | Owning task | Status / location |
| --- | --- | --- |
| Source, submodule, toolchain, and profile identity; prior-receipt disposition. | M1-01. | [Baseline record](hook-refactor-m1-baseline.md); raw manifests and hashes recorded there. |
| ABI/configuration inventory and required test receipts. | M1-02. | [Baseline record](hook-refactor-m1-baseline.md): 698 tests / 48 suites pass in each required run; full ABI exports hashed. |
| Runtime/initcode sizes, deployment headroom, gas scenarios, and results. | M1-03. | [Baseline measurements](hook-refactor-m1-baseline.md#operation-gas-baseline), with reproducible canonical test selectors and receipt hashes. |
| Selected layout, state/event ownership, internal signatures, adapters, and metadata decision. | M1-04, M1-05, M1-06. | [Design record](hook-refactor-m1-design.md): storage, ownership, interfaces, and metadata decided. |
| Behavior/extension walkthrough and M2 handoff. | M1-07. | [Design record](hook-refactor-m1-design.md#final-walkthrough); current behavior, independent added rules, deliberate default replacement, and M2 scope accounted for. |

## Blockers and next action

No unresolved baseline failure or design blocker remains. Production/test
Solidity is unchanged. The only executable-configuration edit explicitly pins
the already-active Foundry isolation/linking defaults; effective default/deploy
settings are unchanged. The user's reference PDF and lifecycle sketch remain
untracked and excluded from commits.

The user approved and pushed M1 on 2026-09-22. M2's own
[plan](hook-refactor-m2-plan.md) and [tracker](hook-refactor-m2-tracker.md) are
prepared for review before implementation. The implementation's performance,
parity, and multi-policy proofs remain obligations of M2–M5.

## Progress log

| Entry | Update |
| --- | --- |
| Planning initialized | Added the M1 plan and tracker. Recorded completed groundwork separately; all seven execution tasks remain unstarted. |
| M1-01 complete | Confirmed source/submodules and pinned tools; captured input/configuration hashes; classified older receipts. Added a local Corepack shim for Yarn without changing package configuration. |
| M1-02 complete | Captured compiler ABIs and compatibility inventory. Default, fixed-seed, and deployment-profile runs each passed 698 tests across 48 suites. Input hashes still match. |
| M1-03 complete | Recorded runtime, creation, STOP-prefixed storage, and constructor payload limits. Captured direct/nested callback gas from 18 existing tests; documented call isolation and exact scenario boundaries. |
| Foundry settings follow-up | Compared 1.7.1/1.8.3 effective defaults and explicitly retained isolation/dynamic linking. Default/deploy configurations are unchanged by the pins, preserving the M1 receipts; 115 production artifacts also match the old build. |
| M1-04 complete | Selected packed storage adapters and one owner per behavior/state/event. Compiler probes verified slot counts and public type re-exports, and identified mechanical inherited-error namespace updates. |
| M1-05 complete | Specified adapters, creation, action defaults/additional checks, APR selection/effective validation on both routes, lifecycle management, no-ops, and views. Compiler probe verified calldata/constructor/diamond signature shape; runtime composition proof remains M4. |
| M1-06 complete | Retained family strings and periodic ABI revision 2; no new revision getters. Documented exact ABI comparison and the limited empty-to-named callback input labels needed by shared coordinators. |
| M1-07 complete | Walked existing and illustrative extension/default-replacement paths, clarified virtual default-APR replacement and named term primitives, reconciled evidence, and recorded the M2 handoff. Input/receipt hashes, effective configurations, document links/anchors/whitespace, and checkpoint signatures verified. |
| 2026-09-22: milestone accepted | User confirmed M1 looks good and has been pushed; M2 plan/tracker prepared separately. |

## Signed checkpoints

| Task / checkpoint | Commit |
| --- | --- |
| M1-01 plus agreed planning documents | `bd88b44` |
| M1-02 | `21e5153` |
| M1-03 | `3b2c3fc` |
| Foundry settings follow-up | `674f43e` |
| M1-04 | `e202675` |
| M1-05 | `1f5b362` |
| M1-06 | `e1f95c3` |
| M1-07 | `d454f26` |

All checkpoints use `kethcode <dave@wildcat.finance>` and the repository-selected
SSH signing key. The user confirmed these M1 checkpoints have been pushed.

# M2 tracker: shared hook behavior

- Plan: [M2 execution plan](hook-refactor-m2-plan.md).
- Milestone status: planned; implementation has not started.
- Execution tasks complete: 0 of 6.
- Active task: none.
- Next action: user review of the plan and instruction to start M2-01.
- Approved M1 handoff: `d454f26fcf54db847657ef08c355e75e72d4356a`.
- Execution starting revision: to record in M2-01, after the planning checkpoint.

The user approved and pushed M1. The [M1 design](hook-refactor-m1-design.md)
and [baseline](hook-refactor-m1-baseline.md) supply the implementation contract
and reference evidence. This tracker does not claim M2 verification or
implementation merely because a requirement was resolved in M1.

## Completed groundwork

| Item | Status | Evidence |
| --- | --- | --- |
| Scope, single-implementation rule, and explicit policy integration | Done | [Spec](hook-composition.md), [behavior map](hook-behavior-map.md), and [milestones](hook-refactor-milestones.md). |
| Storage, interfaces, ownership, metadata, and reference measurements | Done | Approved [M1 design/handoff](hook-refactor-m1-design.md#m2-handoff) and [baseline](hook-refactor-m1-baseline.md). |
| M1 milestone review and push | Done | User confirmation on 2026-09-22; [M1 tracker](hook-refactor-m1-tracker.md). |
| M2 plan and tracker | Done | [Plan](hook-refactor-m2-plan.md) and this file; planning only. |
| Solidity checkpoint review rule | Recorded | User instruction: stage and obtain review before committing Solidity edits, including tests; [workflow](hook-refactor-m2-plan.md#deliverables-and-review-workflow). |

## Task status

Use `Not started`, `In progress`, `Ready for review`, `Done`, or `Blocked`.
`Ready for review` means the task's intended diff is staged and its verification
and evidence are available; it awaits the user's approval before a Solidity
commit. Waiting for that review is not a failed or blocked task. `Done` requires
the task's completion evidence and signed checkpoint, with approval for any
Solidity edits. Record the completion in that checkpoint; fill in its hash in
the next tracker update. Use `Blocked` only for an actual impediment and state
what would resolve it. Unmet dependencies remain `Not started`.

| ID | Task | Status | Depends on | Evidence / result |
| --- | --- | --- | --- | --- |
| [M2-01](hook-refactor-m2-plan.md#m2-01-execution-identity-and-coverage-ownership) | Confirm execution identity, receipts, and test ownership. | Not started | M1 approved; instruction to start M2. | Pending. |
| [M2-02](hook-refactor-m2-plan.md#m2-02-shared-construction-registration-and-minimums) | Share construction, registration/access configuration, and minimums. | Not started | M2-01. | Pending. |
| [M2-03](hook-refactor-m2-plan.md#m2-03-deposit-transfer-views-and-early-extension-probe) | Share deposit/transfer behavior and views; add the early probe. | Not started | M2-02. | Pending. |
| [M2-04](hook-refactor-m2-plan.md#m2-04-queueing-closure-coordination-and-empty-callbacks) | Share queue, closure coordination, and empty callbacks. | Not started | M2-03. | Pending. |
| [M2-05](hook-refactor-m2-plan.md#m2-05-apr-strategy-and-both-periodic-execution-routes) | Share APR coordination and validate both periodic routes. | Not started | M2-04. | Pending. |
| [M2-06](hook-refactor-m2-plan.md#m2-06-qualification-and-m3-handoff) | Qualify the milestone and record the M3 handoff. | Not started | M2-01 through M2-05. | Pending. |

## Review and checkpoint register

For each implementation task, record the staged scope/source identity,
verification result, user approval, and signed commit. Do not stack the next
implementation task on a staged diff awaiting review. Re-stage and obtain
renewed review after substantive changes to an approved diff. All commits use
`kethcode <dave@wildcat.finance>` with the repository-selected SSH key.

| Checkpoint | Review state | Signed commit |
| --- | --- | --- |
| M2 plan/tracker and M1 status updates | Documentation only; covered by existing commit authorization. | Planning commit: `docs: plan hook refactor M2 and initialize tracker`. |
| M2-01 | Not started. | Pending. |
| M2-02 | Not staged. | Pending. |
| M2-03 | Not staged. | Pending. |
| M2-04 | Not staged. | Pending. |
| M2-05 | Not staged. | Pending. |
| M2-06 | Not started. | Pending. |

## Evidence register

`hook-refactor-m2-results.md` is a planned execution deliverable, not an
existing result. Raw evidence will live under ignored
`audits/hook-refactor/m2/<run-id>/`, with commands, relative paths, identities,
and hashes recorded in that file. Keep M1's baseline receipts intact.

| Evidence | Owning task | Status |
| --- | --- | --- |
| Execution source/submodule/toolchain/settings identity and qualified M1 receipts. | M2-01. | Pending. |
| Baseline lint result and common-versus-term test ownership map. | M2-01. | Pending. |
| Shared construction/configuration/minimum compatibility, packing, and factory paths. | M2-02. | Pending. |
| Shared lender actions/views, extension acceptance/rejection, exemptions, and rollback. | M2-03. | Pending. |
| Queue schedule/access order, closure effects, no-ops, and unchanged batching. | M2-04. | Pending. |
| APR strategies, proposal effects, both validation routes, and skipped-default state/events. | M2-05. | Pending. |
| Raw/semantic ABI, storage, deployment sizes/headroom, and comparable M1 gas scenarios. | M2-02 through M2-06. | Pending; compare as each domain moves, reconcile at completion. |
| Required default/fixed-seed/deploy tests and lint, production integrations, final coverage ownership. | M2-06. | Pending. |
| Final source/evidence reconciliation and M3 handoff. | M2-06. | Pending. |

## Implementation watchpoints

These are checks carried from the approved design, not unresolved architecture
decisions or permission requests.

| Concern | Required treatment |
| --- | --- |
| Packed state and widths | Keep one owned configuration per market; preserve periodic's one-slot layout/`uint96` narrowing and avoid extra dispatch reads on hot paths. |
| Creation and authentication | Preserve staged decoding, pre-deployment creation, requested access versus forced callback flags, guard differences, and error/event order. |
| Credential exemptions | Exemptions belong inside defaults; additional rules and matching recipient views still apply. |
| Queue and closure | Market batching stays intact; term/access ordering and proposal effects remain unchanged; no invented APR callback on closure. |
| Periodic APR routes | Validate effective values on ordinary and dedicated routes; dedicated execution keeps reserves; reduction skips temporary-reserve effects. |
| ABI and source imports | Preserve the M1 comparison contract; qualify inherited errors/events by their owner without changing public selectors or tuple formats. |
| Deployment size and gas | Periodic has 2,577 bytes of M1 stored-initcode headroom; measure actual deltas with matching boundaries/settings as code moves. |
| Scope | Keep term extraction/management seams in M3, larger composition proofs in M4, and final qualification/docs in M5. No tranching policy selection. |

## Blockers and next action

No blocker is identified during planning. Execution identity, verification,
and runtime results remain pending. No Solidity, test, or build-setting change
is part of this planning checkpoint. The reference PDF and lifecycle sketch
remain untracked and excluded.

Next: review the M2 plan, then start M2-01 when instructed. The first checkpoint
containing Solidity changes must be staged for user review before committing.
The user retains milestone review and push; M3 planning follows M2 acceptance.

## Progress log

| Entry | Update |
| --- | --- |
| 2026-09-22: M1 accepted | User confirmed M1 looks good and has been pushed. |
| 2026-09-22: M2 planning | Prepared six sequential checkpoints from the approved handoff; recorded the Solidity review workflow and early extension probe. Checked document links/anchors, fences, and whitespace. All execution tasks remain unstarted. |

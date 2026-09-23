# M3 tracker: reusable term policies

- Plan: [M3 execution plan](hook-refactor-m3-plan.md).
- Milestone status: in progress; plan approved and execution authorized.
- Execution tasks complete: 5 of 6.
- Active task: M3-05 complete; M3-06 next.
- Next action: complete final M3 qualification and the M4 handoff.
- Approved M2 handoff: `c54e57312e63ceadee88492d8c47ae632b876b0b`.
- Execution starting revision: `25d38d016f8884d24dced6a9e1c320e5bed5cc34`.

The user accepted and pushed M2 on 2026-09-23. Its
[results and handoff](hook-refactor-m2-results.md#m3-handoff) supply the starting
implementation; the [M1 design](hook-refactor-m1-design.md) and
[baseline](hook-refactor-m1-baseline.md) retain the original compatibility
contract. M3-01 qualified the inherited evidence and mapped the work. M3-02
implements the fixed-policy extraction, reviewed and approved by the user.

## Completed groundwork

| Item | Status | Evidence |
| --- | --- | --- |
| Scope, component ownership, internal signatures, and deliberate override responsibilities | Done | [Spec](hook-composition.md), [behavior map](hook-behavior-map.md), and [M1 design](hook-refactor-m1-design.md). |
| Shared M2 implementation and qualification | Done | [M2 final results](hook-refactor-m2-results.md#m2-06-qualification-and-m3-handoff), qualified against `549bfaa`; documentation checkpoint `c54e573`. |
| M2 milestone review and push | Done | User confirmation on 2026-09-23; [M2 tracker](hook-refactor-m2-tracker.md). |
| M3 plan and tracker | Approved | User reviewed the plan and instructed execution on 2026-09-23. |
| Review and signing workflow | Recorded | [Checkpoint workflow](hook-refactor-m3-plan.md#deliverables-and-review-workflow); staged review before every Solidity commit, including tests. |

## Task status

Use `Not started`, `In progress`, `Ready for review`, `Done`, or `Blocked`.
`Ready for review` means implementation, checks, and evidence are complete and
the intended checkpoint is staged; it still requires user approval before a
Solidity commit. Do not stack the next implementation task on that staged
checkpoint. `Done` requires completion evidence and its signed commit, with
approval for Solidity changes. Record completion in that checkpoint and its
hash in the next tracker update. Use `Blocked` for an actual impediment and
state what resolves it; unmet dependencies remain `Not started`.

| ID | Task | Status | Depends on | Evidence / result |
| --- | --- | --- | --- | --- |
| [M3-01](hook-refactor-m3-plan.md#m3-01-handoff-identity-and-move-inventory) | Qualify the handoff and map moves, consumers, tests, and measurements. | Done | M2 accepted; instruction to start M3. | [Qualified identity, move/test map, and management measurements](hook-refactor-m3-results.md#m3-01-handoff-identity-and-move-inventory). |
| [M3-02](hook-refactor-m3-plan.md#m3-02-fixed-policy-extraction) | Extract and adopt the fixed policy. | Done | M3-01. | [Fixed ownership, unchanged bodies/ABI/layout/bytecode, focused default/deploy passes](hook-refactor-m3-results.md#m3-02-fixed-policy-extraction); user approved the staged checkpoint. |
| [M3-03](hook-refactor-m3-plan.md#m3-03-fixed-setter-extension-points) | Add fixed setter extension points and behavioral probes. | Done | M3-02. | [Setter boundaries, six new cases, unchanged production artifacts/costs, and focused default/deploy passes](hook-refactor-m3-results.md#m3-03-fixed-setter-extension-points); user approved the staged checkpoint. |
| [M3-04](hook-refactor-m3-plan.md#m3-04-periodic-policy-extraction) | Extract and adopt the complete periodic policy. | Done | M3-03. | [Complete lifecycle ownership, unchanged bodies/ABI/layout/bytecode, focused default/deploy checks and invariant campaign](hook-refactor-m3-results.md#m3-04-periodic-policy-extraction); user approved the staged checkpoint. |
| [M3-05](hook-refactor-m3-plan.md#m3-05-periodic-proposal-extension-point) | Add periodic proposal validation and focused tests. | Done | M3-04. | [Proposal boundary, six new cases, retained execution validation, unchanged production artifacts/costs and focused default/deploy passes](hook-refactor-m3-results.md#m3-05-periodic-proposal-extension-point); user approved the staged checkpoint. |
| [M3-06](hook-refactor-m3-plan.md#m3-06-qualification-and-m4-handoff) | Qualify M3 and record the M4 handoff. | Not started | M3-01 through M3-05. | Pending. |

## Review and checkpoint register

All commits use `kethcode <dave@wildcat.finance>` and the repository-selected SSH
signing key. The user reviews and pushes milestones. Documentation-only commits
use the existing authorization; approval of one Solidity checkpoint does not
authorize committing the next one before review.

| Checkpoint | Review state | Signed commit |
| --- | --- | --- |
| M3 plan/tracker and M2 acceptance status | User approved the plan and authorized execution. | `25d38d0`; kethcode SSH signature verified. |
| M3-01 | Documentation/evidence only under existing commit authorization. | `c68f1d9`; kethcode SSH signature verified. |
| M3-02 | User reviewed and authorized commit and continuation. | `2227aa2`; kethcode SSH signature verified; reviewed Solidity hashes retained. |
| M3-03 | User reviewed and authorized commit and continuation. | `24d9b8e`; kethcode SSH signature verified; reviewed Solidity hashes retained. |
| M3-04 | User reviewed and authorized commit and continuation. | `2eed041`; kethcode SSH signature verified; reviewed Solidity hashes retained. |
| M3-05 | User reviewed and authorized commit and continuation. | Signed in this checkpoint; hash recorded in the next update. |
| M3-06 | Not started. | Pending. |

## Evidence register

The [results record](hook-refactor-m3-results.md) identifies source/settings,
commands, raw artifact paths/hashes, and comparisons. Raw M3 evidence lives in
ignored `audits/hook-refactor/m3/2026-09-23/`. M1/M2
receipts are retained references, not claims of fresh M3 verification.

| Evidence | Owning task | Status |
| --- | --- | --- |
| Execution identity, reusable M2 evidence, move/consumer/test map, missing management measurements | M3-01 | [Qualified](hook-refactor-m3-results.md#m3-01-handoff-identity-and-move-inventory): 1,176 matching inputs, unchanged settings/tools/artifacts, retained M2 tests/lint; three existing management scenarios pass and supply 14 call measurements. |
| Fixed ownership, imports/ABI/packing, ordering, lifecycle integrations, size/gas | M3-02 | [Verified](hook-refactor-m3-results.md#m3-02-fixed-policy-extraction): 317 tests / 18 suites pass in each profile; all three ABIs, packed layouts, and executable bytes retained; no new size/gas or lint regression. |
| Fixed setter extension acceptance/rejection, guard priority, after-change state and rollback | M3-03 | [Verified](hook-refactor-m3-results.md#m3-03-fixed-setter-extension-points): 323 tests / 18 suites pass in each profile; six new cases in the existing fixed suite; empty defaults compile away; ABI/layout/size/gas and lint baselines retained. |
| Periodic ownership, public queries/types, complete proposal lifecycle, both APR routes, integrations and costs | M3-04 | [Verified](hook-refactor-m3-results.md#m3-04-periodic-policy-extraction): 323 tests / 18 suites pass in each profile; nine invariant properties pass over 60,000 calls; production artifacts/costs and handler bytecode retained; touched formatting resolves one prior failure. |
| Proposal extension context, acceptance/replacement/rejection, native guard priority and preserved prior proposal | M3-05 | [Verified](hook-refactor-m3-results.md#m3-05-periodic-proposal-extension-point): 329 tests / 18 suites pass in each profile; six new periodic cases; raw ABI/layout/bytecode/size/gas and lint baselines retained. |
| Final ownership/override review, three required test runs, lint comparison and production integrations | M3-06 | Pending. |
| Final ABI/layout/size/gas reconciliation and M4 handoff | M3-06 | Pending. |

## Starting measurements and watchpoints

These are accepted M2 results qualified at M3-01, not fresh M3 passes:

| M2 reference | Recorded result |
| --- | --- |
| Required default / fixed-seed / deploy runs | 707 tests across 51 suites pass in each run; nine invariant properties form one reported campaign. |
| Full lint | 34 untouched Prettier failures; standalone Solhint has zero errors and 22 warnings. |
| Runtime / creation / stored-initcode headroom, bytes | Open: 15,653 / 18,379 / 6,196. Fixed: 17,014 / 19,741 / 4,834. Periodic: 19,949 / 22,676 / 1,899. |
| Compatibility and costs | M2 raw ABIs and packed layouts retained; all 97 M1 callback observations reconciled, plus 70 comparable creation/minimum/query observations. [Details](hook-refactor-m2-results.md#final-compatibility-deployment-size-and-gas). |

| Concern | Required treatment |
| --- | --- |
| One implementation | Adopt each policy and remove the old body/declaration in the same task; retain shared access/constraint owners and one packed state representation. |
| Public imports and ABI | Re-export moved global types from existing concrete files. Preserve M2 names/tuples/selectors and artifact paths; update declaration-owner qualifications mechanically. |
| Constructor and flags | Initialize `BaseHooks` once from the concrete composition; retain requested access versus forced dispatch and existing family/revision metadata. |
| Fixed management | Preserve native guard order and equal-time behavior; validate before writing, run the after-change extension after the event, roll back on either rejection. Creation/closure remain distinct paths. |
| Periodic lifecycle | One proposal owner across management, both executions, increase cancellation, queries, and closure. Proposal checks precede replacement effects; effective APR checks still run on execution. |
| Default selection | Fixed retains its APR guard before the selected default. Periodic reductions skip temporary-reserve logic and keep current reserves; the dedicated path stays APR-only with empty data. |
| Schedule, access, and closure | Preserve queue error priority and closed-window behavior without bypassing withdrawal access. Keep market batching and the market-owned closure APR/reserve reset. |
| Deployment and cost | Measure runtime and `STOP || initcode`; periodic begins with 1,899 bytes of stored-initcode headroom. Keep comparable source/settings/fixture/call boundaries. |
| Tests and comments | Reuse concrete owning suites and helpers without inherited test entrypoints or copied oracles. Preserve technical names and branch explanations in comments. |
| Scope | Keep broader composition/replacement proofs in M4 and final contributor guidance/qualification in M5. No tranching policy selection or runtime feature slots. |

## Blockers and next action

M3-05 is approved for its signed checkpoint. M3-06 follows with full qualification
and the M4 handoff. No implementation blocker is known. Any further Solidity
change requires its own staged review before commit. The voice guide, reference
PDF, and lifecycle sketch remain untracked and excluded; no push is performed.

## Progress log

| Entry | Update |
| --- | --- |
| 2026-09-23: M2 accepted | User confirmed M2 looks good and has been pushed. |
| 2026-09-23: M3 planning | Prepared six sequential tasks, separating each policy move from its management extension points. Carried forward compatibility, packed ownership, lifecycle/override responsibilities, size/gas evidence, and staged Solidity review. Execution has not started. |
| 2026-09-23: M3 authorized / M3-01 complete | User approved the plan and instructed execution. Qualified M2 source/dependency/tool/settings/artifact identity and receipts; mapped policy/type/consumer moves and test ownership. Three existing management scenarios pass, adding five fixed setter and nine periodic proposal measurements. No Solidity changed; M3-02 retains staged review. |
| 2026-09-23: M3-02 ready for review | Extracted/adopted the fixed policy and re-exported its unchanged public type. All original declarations/bodies/comments are preserved; four consumer tests change imports/error/event qualifications only. Focused default/deploy checks each pass 317 tests across 18 suites; ABI, layout, bytecode, size/gas, and lint comparisons are recorded. Staged for user review before committing or beginning M3-03. |
| 2026-09-23: M3-02 approved | User reviewed the staged extraction and authorized commit and continuation. Verified the reviewed patch and source hashes are unchanged; only completion status is updated for the signed checkpoint. M3-03 retains its own staged review. |
| 2026-09-23: M3-03 ready for review | Added the two empty setter extension points, a test-only notice/budget derivative using the inherited setter, and six cases in the existing fixed owner. Default/deploy checks each pass 323 tests across 18 suites. Production bytecode, ABI, packed layout, size/gas, and lint baselines are unchanged. Staged for review before commit or M3-04. |
| 2026-09-23: M3-03 approved | User reviewed the staged setter extensions and authorized commit and continuation. Verified the reviewed patch and source hashes are unchanged; only completion status is updated for the signed checkpoint. M3-04 retains its own staged review. |
| 2026-09-23: M3-04 ready for review | Extracted/adopted the whole periodic lifecycle with unchanged functions/comments, re-exported types/interface, and five mechanical consumer updates. Focused default/deploy checks each pass 323 tests / 18 suites; the nine-property invariant campaign passes 2,000 runs / 60,000 calls. Production ABI/layout/bytecode/size/gas and handler bytecode are unchanged. Formatting the touched handler reduces existing Prettier failures from 34 to 33; Solhint remains unchanged. Staged for review before commit or M3-05. |
| 2026-09-23: M3-04 approved | User reviewed the staged periodic extraction and authorized commit and continuation. Verified the reviewed patch and source hashes are unchanged; only completion status is updated for the signed checkpoint. M3-05 retains its own staged review. |
| 2026-09-23: M3-05 ready for review | Added the empty proposal validation extension after native checks/window calculations and before replacement effects. The test-only derivative reuses the existing APR floor and inherited proposal entrypoint; six new cases cover acceptance, rejection, exact window context, retained prior state, native error priority and width checks. Default/deploy runs each pass 329 tests / 18 suites. Production ABI/layout/bytecode/size/gas and the 33-file/22-warning lint baseline remain unchanged. Staged for review before commit or M3-06. |
| 2026-09-23: M3-05 approved | User reviewed the staged proposal extension and authorized commit and continuation. Verified the reviewed patch, source hashes, and supporting evidence are unchanged; only completion status is updated for the signed checkpoint. M3-06 follows with final qualification. |

# M2 tracker: shared hook behavior

- Plan: [M2 execution plan](hook-refactor-m2-plan.md).
- Milestone status: in progress; M2-05 accepted.
- Execution tasks complete: 5 of 6.
- Active task: M2-06 qualification and M3 handoff.
- Next action: run the final milestone checks and reconcile the evidence.
- Approved M1 handoff: `d454f26fcf54db847657ef08c355e75e72d4356a`.
- Execution starting revision: `1b8e36c76713af709a9326adfceac33b15b5f619`.

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
| [M2-01](hook-refactor-m2-plan.md#m2-01-execution-identity-and-coverage-ownership) | Confirm execution identity, receipts, and test ownership. | Done | M1 approved; M2 start authorized. | [Identity, baseline lint, and ownership map](hook-refactor-m2-results.md). |
| [M2-02](hook-refactor-m2-plan.md#m2-02-shared-construction-registration-and-minimums) | Share construction, registration/access configuration, and minimums. | Done | M2-01. | [Implementation and verification](hook-refactor-m2-results.md#m2-02-shared-construction-registration-and-minimums); user approved the staged changes and authorized the signed checkpoint. |
| [M2-03](hook-refactor-m2-plan.md#m2-03-deposit-transfer-views-and-early-extension-probe) | Share deposit/transfer behavior and views; add the early probe. | Done | M2-02. | [Implementation, ownership, and verification](hook-refactor-m2-results.md#m2-03-deposit-transfer-views-and-early-extension-probe); user accepted the staged checkpoint and authorized M2-04. |
| [M2-04](hook-refactor-m2-plan.md#m2-04-queueing-closure-coordination-and-empty-callbacks) | Share queue, closure coordination, and empty callbacks. | Done | M2-03. | [Implementation and verification](hook-refactor-m2-results.md#m2-04-queueing-closure-coordination-and-empty-callbacks); user approved the staged changes and authorized the signed checkpoint. |
| [M2-05](hook-refactor-m2-plan.md#m2-05-apr-strategy-and-both-periodic-execution-routes) | Share APR coordination and validate both periodic routes. | Done | M2-04. | [Implementation and verification](hook-refactor-m2-results.md#m2-05-apr-strategy-and-both-periodic-execution-routes); user accepted the code and revised comments and authorized the signed checkpoint. |
| [M2-06](hook-refactor-m2-plan.md#m2-06-qualification-and-m3-handoff) | Qualify the milestone and record the M3 handoff. | In progress | M2-01 through M2-05. | Final checks and evidence reconciliation next. |

## Review and checkpoint register

For each implementation task, record the staged scope/source identity,
verification result, user approval, and signed commit. Do not stack the next
implementation task on a staged diff awaiting review. Re-stage and obtain
renewed review after substantive changes to an approved diff. All commits use
`kethcode <dave@wildcat.finance>` with the repository-selected SSH key.

| Checkpoint | Review state | Signed commit |
| --- | --- | --- |
| M2 plan/tracker and M1 status updates | Documentation only; plan approved and execution authorized. | `1b8e36c`. |
| M2-01 | Documentation/evidence only; existing commit authorization. | `774ca36`. |
| M2-02 | Verified; user approved the staged changes, including the comment revision. Cost deltas documented in results. | `9d52fe0`; kethcode SSH signature verified. |
| M2-03 | Verified; user accepted the staged changes and authorized continuation. Callback/view costs and smaller bytecode documented. | `6859b70`; kethcode SSH signature verified. |
| M2-04 | Verified; user accepted the staged changes and authorized continuation. Queue/closure behavior and cost comparisons recorded. | `95a2912`; kethcode SSH signature verified. |
| M2-05 | Verified; user accepted the code and revised comments and authorized continuation. Both periodic validation routes, rollback, compatibility, and costs recorded. | Included in this signed checkpoint; hash recorded in the next update. |
| M2-06 | In progress; qualification and handoff. | Pending. |

## Evidence register

The [results record](hook-refactor-m2-results.md) binds evidence to commands,
relative paths, source/settings, and hashes. Raw evidence lives under ignored
`audits/hook-refactor/m2/2026-09-22/`. M1's baseline receipts remain intact.

| Evidence | Owning task | Status |
| --- | --- | --- |
| Execution source/submodule/toolchain/settings identity and qualified M1 receipts. | M2-01. | [Qualified](hook-refactor-m2-results.md#m2-01-execution-identity-and-reusable-evidence): inputs/settings/tools and retained test/ABI/size evidence match. |
| Baseline lint result and common-versus-term test ownership map. | M2-01. | [Lint](hook-refactor-m2-results.md#lint-baseline): 41 existing formatting failures; Solhint passes with 22 warnings. [Ownership map](hook-refactor-m2-results.md#test-ownership-and-migration-map) recorded. |
| Shared construction/configuration/minimum compatibility, packing, and factory paths. | M2-02. | [Verified](hook-refactor-m2-results.md#verification): 207 tests / 13 suites pass in each focused profile; ABIs/layouts identical; creation probe passes. |
| Shared lender actions/views, extension acceptance/rejection, exemptions, and rollback. | M2-03. | [Verified](hook-refactor-m2-results.md#m2-03-verification): 226 tests / 15 suites pass in each focused profile, including the four-case extension probe and real wrapper integration. |
| Queue schedule/access order, closure effects, no-ops, and unchanged batching. | M2-04. | [Verified](hook-refactor-m2-results.md#m2-04-verification): 308 tests / 16 suites pass in each focused profile, including standard/revolving lifecycle and closure/batch settlement. |
| APR strategies, proposal effects, both validation routes, and skipped-default state/events. | M2-05. | [Verified](hook-refactor-m2-results.md#m2-05-verification): 317 tests / 18 suites pass in each profile, including five validator cases and borrower-account/real-market APR paths. |
| Raw/semantic ABI, storage, deployment sizes/headroom, and comparable M1 gas scenarios. | M2-02 through M2-06. | [M2-05 comparisons](hook-refactor-m2-results.md#m2-05-size-and-gas-comparisons): 47 surviving M1 observations, including all 22 ordinary/dedicated APR calls. Raw ABIs match M2-04; layouts match M1. Periodic stored-initcode headroom is 1,899 bytes. Default/deploy/gas executable bytes match. Milestone qualification pending. |
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
| Code comments | Preserve technical terms, function/variable names, and useful explanations beside branches. The user's voice guide changes tone; it is not a reason to remove that context. |
| Scope | Keep term extraction/management seams in M3, larger composition proofs in M4, and final qualification/docs in M5. No tranching policy selection. |

## Blockers and next action

The user accepted M2-05, including the revised comments, and authorized its
signed checkpoint and continuation. Both profiles pass 317 selected
tests. Raw ABIs match M2-04 and storage layouts match M1.
Runtime/creation code grows by 66–198 bytes from M2-04, leaving periodic 1,899
bytes of stored-initcode headroom. Successful ordinary APR observations add
260–288 gas; dedicated periodic execution adds 702 gas. Some open/periodic
lender actions also add 81 gas because the compiler factors out a shared
allocation helper. Full lint retains the same 34 formatting failures and
22 Solhint warnings. Local reference documents remain untracked.

Next: M2-06 full milestone qualification, evidence reconciliation, and M3 handoff.
Any new Solidity changes retain the staged review requirement.
The user retains milestone review and push; M3 planning follows M2 acceptance.

## Progress log

| Entry | Update |
| --- | --- |
| 2026-09-22: M1 accepted | User confirmed M1 looks good and has been pushed. |
| 2026-09-22: M2 planning | Prepared six sequential checkpoints from the approved handoff; recorded the Solidity review workflow and early extension probe. Checked document links/anchors, fences, and whitespace. All execution tasks remain unstarted. |
| 2026-09-22: M2-01 complete | User approved the plan and authorized execution. Qualified 1,166 inputs, effective settings, tools, and M1 receipts; established lint baseline and mapped test ownership. Installed locked dev dependencies locally without source/package/lockfile changes. |
| M2-02 ready for review | Shared construction/configuration/minimum implementation adopted by all three templates; equivalent assertions consolidated and boundary/rollback checks added. Focused default/deploy runs pass, ABI/storage comparisons match, and size/gas deltas are documented. Staged for review; not committed. |
| M2-02 comment review | Revised comments in six Solidity files using the user's local voice guide. Verified identical non-comment tokens in all 12 staged Solidity files, passing formatting, and unchanged Solhint output. Preserved original test receipts and recorded the amendment; no test rerun. Guide remains untracked; checkpoint remains staged and uncommitted. |
| M2-02 accepted | User approved the staged changes and instructed a signed kethcode commit, then continuation. Approval applies to this checkpoint; M2-03 retains the staged Solidity review gate. |
| M2-02 committed | Signed commit `9d52fe0` as `kethcode <dave@wildcat.finance>`; SSH signature verified. Approved Solidity patch matches the retained review receipt. |
| M2-03 ready for review | Shared deposit/transfer coordinators, defaults, and views adopted by all three templates; copied tests consolidated. Four extension cases prove recipient restrictions survive exemptions and roll back credential/known-state changes. Both focused profiles pass 226 tests. ABI, layout, size, gas, and lint comparisons recorded; staged and uncommitted. |
| M2-03 accepted | User accepted the staged deduplication and authorized M2-04. Signed checkpoint uses kethcode; the next Solidity checkpoint retains the review gate. |
| 2026-09-23: M2-03 committed | Signed commit `6859b70` as `kethcode <dave@wildcat.finance>`; SSH signature verified. Approved Solidity patch and file hashes match the commit. |
| 2026-09-23: M2-04 ready for review | Shared queue/closure coordination and six empty callbacks adopted by all three templates. Shared queue/no-op tests consolidated; term ordering and closure effects retained. Both profiles pass 308 affected tests. ABI/storage, deployment limits, gas, and lint evidence recorded; staged and uncommitted. |
| M2-04 accepted | User approved the staged checkpoint and instructed a signed commit and continuation. M2-05 retains the staged Solidity review gate. |
| 2026-09-23: M2-04 committed | Signed commit `95a2912` as `kethcode <dave@wildcat.finance>`; SSH signature verified. Approved Solidity patch and file hashes match the commit. |
| 2026-09-23: M2-05 ready for review | Shared APR coordination/default strategy and both periodic validation routes implemented. Five focused validator cases cover applied values, skipped default effects, data, and rollback. Both profiles pass 317 selected tests. Raw ABI/storage, bytecode identity, size, gas, and lint evidence recorded; staged and uncommitted. |
| M2-05 comment review | Restored the inline fixed-term revert explanation and revised APR comments to retain function/variable names and branch conditions. Only comments changed in four source files; all nine staged Solidity token streams match the tested versions. Formatting passes and Solhint output is unchanged. Original receipts retained with a separate comment-amendment record; still staged and uncommitted. |
| M2-05 accepted | User approved the code and revised comments and instructed a signed kethcode commit and continuation. The approved patch and all staged file hashes match the retained review receipt. M2-06 begins with qualification; any further Solidity changes require staged review. |

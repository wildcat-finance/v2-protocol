# M4 tracker: extension and composition proof

- Plan: [M4 execution plan](hook-refactor-m4-plan.md).
- Milestone status: plan and tracker prepared for review; execution not started.
- Execution tasks complete: 0 of 6.
- Active task: none.
- Next action: user reviews the plan before M4-01 begins.
- Approved M3 handoff: `eff4d5898a5384b35f16acba23fee2aca47745d0`.
- Execution starting revision: record when execution is authorized.

The user accepted and pushed M3 on 2026-09-23, then requested the next stage.
Its [results and handoff](hook-refactor-m3-results.md#m4-handoff) supply the
implementation and prior evidence. M4 demonstrates independent features and
deliberate default replacement; it does not select tranching economics.

## Completed groundwork

| Item | Status | Evidence |
| --- | --- | --- |
| Shared behavior and reusable fixed/periodic policies | Done | [M2 results](hook-refactor-m2-results.md), [M3 results](hook-refactor-m3-results.md). |
| M3 milestone review and push | Done | User confirmation on 2026-09-23; [M3 tracker](hook-refactor-m3-tracker.md). |
| Original-test replay addressing parity concern | Done | [Separate 53-case replay](hook-refactor-m3-results.md#supplemental-original-test-replay); no changed setup/assertions/expected values. |
| M4 plan and tracker | Ready for review | [Scope, six tasks, and completion criteria](hook-refactor-m4-plan.md); no execution authorization yet. |
| Review and signing workflow | Recorded | [Checkpoint workflow](hook-refactor-m4-plan.md#deliverables-and-review-workflow); staged review before every Solidity commit, including tests. |

## Task status

Use `Not started`, `In progress`, `Ready for review`, `Done`, or `Blocked`.
`Ready for review` means work, checks, and evidence are complete and the intended
checkpoint is staged. A Solidity checkpoint still needs approval before commit
or work on the next implementation task. `Done` requires completion evidence
and a signed commit, with approval for Solidity changes. Record completion in
that checkpoint and the hash in the next tracker update. Use `Blocked` only
for an actual impediment, stating what resolves it; unmet dependencies remain
`Not started`.

| ID | Task | Status | Depends on | Evidence / result |
| --- | --- | --- | --- | --- |
| [M4-01](hook-refactor-m4-plan.md#m4-01-handoff-identity-and-proof-map) | Qualify handoff and map probes, flags, owners, and measurements. | Not started | Plan approval and instruction to execute. | Create results record during execution. |
| [M4-02](hook-refactor-m4-plan.md#m4-02-three-policy-checks-and-feature-state) | Compose two transfer features with each term choice. | Not started | M4-01. | Pending. |
| [M4-03](hook-refactor-m4-plan.md#m4-03-fourth-feature-and-callback-activation) | Add borrow feature and prove real activation/deployment. | Not started | M4-02. | Pending. |
| [M4-04](hook-refactor-m4-plan.md#m4-04-deliberate-apr-default-replacement) | Replace the APR default and prove skipped effects. | Not started | M4-03. | Pending. |
| [M4-05](hook-refactor-m4-plan.md#m4-05-alternate-routes-and-lifecycle-integration) | Prove alternate routes and lifecycle behavior through real markets. | Not started | M4-02 through M4-04. | Pending. |
| [M4-06](hook-refactor-m4-plan.md#m4-06-qualification-and-m5-handoff) | Qualify M4 and record the M5 handoff. | Not started | M4-01 through M4-05. | Pending. |

## Review and checkpoint register

Commits use `kethcode <dave@wildcat.finance>` and the repository-selected SSH
signing key. Documentation-only commits use the existing authorization; review
of one Solidity checkpoint does not authorize committing the next. The user
reviews and pushes the milestone.

| Checkpoint | Review state | Signed commit |
| --- | --- | --- |
| M4 plan/tracker and M3 acceptance record | Documentation-only planning; plan awaits user review. | Signed with this checkpoint; record hash at the next tracker update. |
| M4-01 | Not started; documentation/evidence only. | Pending. |
| M4-02 | Not started; stage Solidity for review before commit. | Pending. |
| M4-03 | Not started; stage Solidity for review before commit. | Pending. |
| M4-04 | Not started; stage Solidity for review before commit. | Pending. |
| M4-05 | Not started; stage Solidity for review before commit. | Pending. |
| M4-06 | Not started; apply staged-review rule if qualification requires Solidity fixes. | Pending. |

## Evidence register

Create `hook-refactor-m4-results.md` at M4-01. Raw evidence belongs under ignored
`audits/hook-refactor/m4/<run-id>/`. Identify source/settings, commands, paths,
hashes, and comparisons; retained M3 receipts are not fresh M4 passes.

| Evidence | Owning task | Status |
| --- | --- | --- |
| Execution identity, retained receipts, concrete configuration recipe, proof ownership, cost plan | M4-01 | Pending. |
| Overlapping transfer rules, state/API ownership, credential exemptions, authority and isolation, rollback | M4-02 | Pending. |
| Fourth feature without reusable-component edits, borrow activation/authentication, all six term/market deployment combinations | M4-03 | Pending. |
| Selected APR result, retained guards, absent skipped-default effects, effective-value rejection | M4-04 | Pending. |
| Changed proposal/execution conditions, both APR routes, separate creation/setter/closure behavior, market accounting | M4-05 | Pending. |
| Required suites/lint, test ownership, production compatibility/costs, composition deployability, final requirement map | M4-06 | Pending. |

## Starting evidence and watchpoints

These are accepted M3 results, to be qualified at M4-01. They are not new runs
performed for this planning checkpoint.

| M3 reference | Recorded result |
| --- | --- |
| Required default / fixed-seed / deploy runs | 719 reported tests across 51 suites pass in each run; nine invariant properties form one campaign of 2,000 runs / 60,000 calls. |
| Supplemental original-test replay | All 53 original cases pass against completed M3 after mechanical declaration-owner/import adaptations only. |
| Full lint | 33 untouched Prettier failures; standalone Solhint has zero errors and 22 warnings. All M3-touched Solidity passes formatting. |
| Runtime / creation / stored-initcode headroom, bytes | Open: 15,653 / 18,379 / 6,196. Fixed: 17,014 / 19,741 / 4,834. Periodic: 19,949 / 22,676 / 1,899. |
| Compatibility and costs | Production raw ABIs/layouts/executable bytes match M2; only previously accepted M1 callback-input names differ. Retained gas evidence keeps its original conditions/exclusions. [Details](hook-refactor-m3-results.md#final-compatibility-deployment-size-and-gas). |

| Concern | Required treatment |
| --- | --- |
| Callback configuration | Public deployment config and effective market flags must agree. Resolve the open constructor's fixed configuration without copying its implementation. Forced dispatch must not silently request credentials. |
| Three/four policy proof | Count the term policy plus independent features. Explicitly call each selected rule; the fourth addition must not rewrite existing features or reusable base/term logic. |
| Feature state and authority | One market-keyed owner, authenticated management, multiple markets per instance, administrator transfer, and observable amounts/state/events. |
| Transfer promises | Known lenders/wrappers still face extra checks. Recipient-only views do not validate amounts. A positive per-transfer limit must not become a global shutdown or exhausted cumulative quota. |
| Timing and rollback | Creation precedes market deployment; callbacks precede later market work. Test rejection after earlier writes and downstream asset-transfer failure. |
| APR replacement | Skip default state/events deliberately; retain bounds and fixed maturity guard. Periodic reductions keep their proposal lifecycle and bypass the replacement default. |
| Alternate routes and closure | Dedicated periodic execution is APR-only with empty data. Proposal admission does not replace execution checks. Closure resets APR/reserves outside `_checkAprChange`; setter extensions do not cover creation/closure. |
| Deployment | Measure actual composed artifacts and use real factories. Periodic has only 1,899 bytes of stored-initcode headroom; source reuse does not guarantee fit. |
| Evidence and scope | Keep canonical owners/assertions and existing production behavior. No tranching requirements, new runtime composition machinery, or external deployment/SDK work. |

## Blockers and next action

No execution blocker is established. The callback-configuration recipe and
periodic size budget are explicit design/verification work, not reasons to
waive the proof. Next action is user review of the M4 plan, then M4-01 on
authorization. No Solidity has changed in this planning checkpoint, and no
tests were rerun for documentation edits. The voice guide, reference PDF, and
lifecycle sketch remain untracked and excluded.

## Progress log

| Entry | Update |
| --- | --- |
| 2026-09-23: M3 accepted | User confirmed the reviewed M3 milestone is pushed and requested the next stage. |
| 2026-09-23: M4 planning | Prepared six tasks covering independent transfer features, a fourth borrow feature, deliberate APR default replacement, lifecycle integration, and qualification. Recorded concrete callback/size constraints, prior parity evidence, and staged Solidity review. Execution has not started. |

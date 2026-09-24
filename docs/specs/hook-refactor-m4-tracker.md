# M4 tracker: extension and composition proof

- Plan: [M4 execution plan](hook-refactor-m4-plan.md).
- Milestone status: authorized and in progress; M4-04 complete.
- Execution tasks complete: 4 of 6.
- Active task: M4-05, alternate routes and lifecycle integration.
- Next action: implement and verify M4-05, then stage its Solidity checkpoint for review.
- Approved M3 handoff: `eff4d5898a5384b35f16acba23fee2aca47745d0`.
- Execution starting revision: `579bba16f5204b0a4b815811a527aed61dfb256f`.

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
| M4 plan and tracker | Approved | User instructed M4 execution on 2026-09-23 after reboot. |
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
| [M4-01](hook-refactor-m4-plan.md#m4-01-handoff-identity-and-proof-map) | Qualify handoff and map probes, flags, owners, and measurements. | Done | Plan approval and instruction to execute. | [Qualified identity, open configuration correction, proof ownership, and measurements](hook-refactor-m4-results.md#m4-01-handoff-identity-and-proof-map). |
| [M4-02](hook-refactor-m4-plan.md#m4-02-three-policy-checks-and-feature-state) | Compose two transfer features with each term choice. | Done | M4-01. | [Open configuration correction, shared feature rules, 14 composition properties, unchanged production artifacts/costs, and two 339-test passes](hook-refactor-m4-results.md#m4-02-three-policy-checks-and-feature-state). |
| [M4-03](hook-refactor-m4-plan.md#m4-03-fourth-feature-and-callback-activation) | Add borrow feature and prove real activation/deployment. | Done | M4-02. | [Independent borrow policy, six-cell real factory matrix, rollback/authority, unchanged existing entrypoints, and two 345-test passes](hook-refactor-m4-results.md#m4-03-fourth-feature-and-callback-activation). |
| [M4-04](hook-refactor-m4-plan.md#m4-04-deliberate-apr-default-replacement) | Replace the APR default and prove skipped effects. | Done | M4-03. | [Shared replacement/validator, skipped effects and retained guards, original validator ABI/layout preservation, and two 352-test passes](hook-refactor-m4-results.md#m4-04-deliberate-apr-default-replacement). |
| [M4-05](hook-refactor-m4-plan.md#m4-05-alternate-routes-and-lifecycle-integration) | Prove alternate routes and lifecycle behavior through real markets. | Not started | M4-02 through M4-04. | Pending. |
| [M4-06](hook-refactor-m4-plan.md#m4-06-qualification-and-m5-handoff) | Qualify M4 and record the M5 handoff. | Not started | M4-01 through M4-05. | Pending. |

## Review and checkpoint register

Commits use `kethcode <dave@wildcat.finance>` and the repository-selected SSH
signing key. Documentation-only commits use the existing authorization; review
of one Solidity checkpoint does not authorize committing the next. The user
reviews and pushes the milestone.

| Checkpoint | Review state | Signed commit |
| --- | --- | --- |
| M4 plan/tracker and M3 acceptance record | User approved the plan and authorized execution. | `579bba1`; kethcode SSH signature verified. |
| M4-01 | Documentation/evidence only under existing authorization. | `d653f15`; kethcode SSH signature verified. |
| M4-02 | User approved the staged checkpoint and authorized commit/continuation. | `d3811bb`; kethcode SSH signature verified. |
| M4-03 | User approved commit and instructed a hold for reboot on 2026-09-24. | `81934d7`; kethcode SSH signature verified. |
| M4-04 | User approved the staged checkpoint and authorized commit/continuation on 2026-09-24. | Signed with this checkpoint; hash recorded in the next tracker update. |
| M4-05 | Not started; stage Solidity for review before commit. | Pending. |
| M4-06 | Not started; apply staged-review rule if qualification requires Solidity fixes. | Pending. |

## Evidence register

The [results record](hook-refactor-m4-results.md) identifies source/settings,
commands, paths, hashes, and comparisons. Raw evidence lives under ignored
`audits/hook-refactor/m4/2026-09-23/` and `2026-09-24/`; retained M3 receipts are
not fresh M4 passes.

| Evidence | Owning task | Status |
| --- | --- | --- |
| Execution identity, retained receipts, concrete configuration recipe, proof ownership, cost plan | M4-01 | [Qualified](hook-refactor-m4-results.md#m4-01-handoff-identity-and-proof-map): 1,182 matching inputs, unchanged tools/settings/submodules, 55 M3 artifact hashes and eight references verified plus the original-test replay. Open constructor configuration gap and single-owner extraction mapped. |
| Overlapping transfer rules, state/API ownership, credential exemptions, authority and isolation, rollback | M4-02 | [Verified](hook-refactor-m4-results.md#m4-02-three-policy-checks-and-feature-state): four retained cases expanded across all terms, ten new properties, 25 original assertions/revert expectations retained, 339 tests / 18 suites pass in both profiles. Production ABI/layout/bytecode unchanged; three composed runtimes and stored-initcode contracts fit. |
| Fourth feature without reusable-component edits, borrow activation/authentication, all six term/market deployment combinations | M4-03 | [Verified](hook-refactor-m4-results.md#m4-03-fourth-feature-and-callback-activation): four new properties cover real stored-initcode/factory deployment, normalized borrow bounds, prior transfer rules, shared-instance isolation, authority transfer, downstream rollback, and earlier core guards. 345 tests / 19 suites pass in both profiles. All 737 existing entrypoints and production/transfer components unchanged; periodic stored-initcode headroom 653 bytes. |
| Selected APR result, retained guards, absent skipped-default effects, effective-value rejection | M4-04 | [Verified](hook-refactor-m4-results.md#m4-04-deliberate-apr-default-replacement): seven new properties, explicit bounds and unchanged term routing, successful-call event absence, seeded-state preservation, rollback, and retained access/transfer/withdrawal/authority rules. 352 tests / 19 suites pass in both profiles. Shared validator retains its ABI, 17 storage entries, and original rule statements; periodic replacement stored-initcode headroom 1,260 bytes. |
| Changed proposal/execution conditions, both APR routes, separate creation/setter/closure behavior, market accounting | M4-05 | Pending. |
| Required suites/lint, test ownership, production compatibility/costs, composition deployability, final requirement map | M4-06 | Pending. |

## Starting evidence and watchpoints

These are accepted M3 results qualified at M4-01. They are retained evidence,
not new M4 test runs.

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
| Deployment | Measure actual composed artifacts and use real factories. Periodic production starts with 1,899 bytes of stored-initcode headroom; the two-feature composition leaves 1,118 and the added borrow feature leaves 653. The separate transfer-plus-APR-replacement example leaves 1,260; its real factory deployment remains M4-05. Source reuse does not guarantee fit. |
| Evidence and scope | Keep canonical owners/assertions and existing production behavior. No tranching requirements, new runtime composition machinery, or external deployment/SDK work. |

## Blockers and next action

M4-04 is approved and complete. M4-05 now exercises the selected behavior through
real market operations, including alternate APR routes and closure. Its Solidity
checkpoint requires staged review before commit or M4-06. The voice guide, PDF,
and lifecycle sketch remain excluded.

## Progress log

| Entry | Update |
| --- | --- |
| 2026-09-23: M3 accepted | User confirmed the reviewed M3 milestone is pushed and requested the next stage. |
| 2026-09-23: M4 planning | Prepared six tasks covering independent transfer features, a fourth borrow feature, deliberate APR default replacement, lifecycle integration, and qualification. Recorded concrete callback/size constraints, prior parity evidence, and staged Solidity review. Execution has not started. |
| 2026-09-23: M4 authorized / M4-01 complete | User instructed execution. Qualified the unchanged M3 inputs, tools/settings, artifacts, signatures and supplemental replay; mapped proof owners, feature state/authority/order, and costs. Identified open constructor configuration as the first boundary correction. Documentation-only signed checkpoint; M4-02 retains staged Solidity review. |
| 2026-09-23: M4-02 ready for review | Extracted/adopted open configuration and adapters with unchanged original declarations/comments. Added two independent test features and explicit assemblies for each term, replacing the old recipient-only mock. Preserved its four cases/assertions and added ten properties. Final default/deploy checks each pass 339 tests / 18 suites; production ABI/layout/bytecode/costs and lint baseline are retained. Measured composed sizes, actual initcode storage deployments, and 15 transfer callback costs. Staged for review before commit or M4-03. |
| 2026-09-23: M4-02 approved | User approved the staged checkpoint and instructed commit/continuation. Verified the reviewed index and all 40 evidence hashes before changing completion status only. Signed kethcode checkpoint; M4-03 is next. |
| 2026-09-23: M4-03 ready for review | Added the borrow feature through new component/assembly code and extended the existing real-factory fixture. Four properties exercise all six compositions, including failed asset-transfer rollback and authority/market isolation. Final default/deploy checks each pass 345 tests / 19 suites; all original 737 entrypoints and production/transfer components remain unchanged. Recorded deployment sizes and 36 nested callback observations from 48 market calls. Staged for review before commit or M4-04. |
| 2026-09-24: M4-03 approved; hold for reboot | User approved commit and instructed a hold. Verified the exact reviewed index, all 52 evidence artifacts, and 1,187 qualified inputs before changing completion status only. Signed kethcode checkpoint; M4-04 remains unstarted pending the user's return. |
| 2026-09-24: M4-04 resumed and ready for review | User resumed execution. Verified the signed handoff and prior evidence, extracted/adopted the shared validator, and added three APR replacement assemblies with seven new properties. Preserved original assertions except six moved-error selector qualifications. Final default/deploy checks each pass 352 tests / 19 suites; production and prior feature components/artifacts remain unchanged. Confirmed original validator ABI/layout/rules, deployment sizes, and 27 APR callback observations. Staged for review before commit or M4-05. |
| 2026-09-24: M4-04 approved | User approved the staged checkpoint and instructed continuation. Verified the exact reviewed index, all 59 evidence artifacts, and 1,190 qualified inputs before changing completion status only. Signed kethcode checkpoint; M4-05 is next. |

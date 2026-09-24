# M5 tracker: integration compatibility and final documentation

- Plan: [M5 execution plan](hook-refactor-m5-plan.md).
- Milestone status: authorized and in progress; M5-01 complete.
- Execution tasks complete: 1 of 6.
- Active task: M5-02, public formats, identity, and source compatibility.
- Next action: compare final public formats and consumers against M1 and M4.
- Completed M4 checkpoint: `add362d22ab28b6d63f7e5627517f5f2e7e56121`.
- Original compatibility reference: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c`.

On 2026-09-24 the user made existing integration compatibility the leading M5
priority, while retaining documentation, deployment/cost, and qualification
work. The user directed final removal of the working documents and spec from
the release tree, with an updated spec saved for the knowledge base. V2.6
tranching assessment follows qualification of hook extensibility separately.

## Groundwork and handoff

| Item | Status | Evidence / disposition |
| --- | --- | --- |
| M1–M3 | Complete, reviewed, and pushed | Original compatibility baseline and shared/term ownership records. |
| M4 | All six tasks complete; user checkpoint approvals recorded | [M4 tracker](hook-refactor-m4-tracker.md) and [handoff](hook-refactor-m4-results.md#m5-handoff). Final checkpoint `add362d`, signed kethcode and verified. Milestone push has not been recorded. |
| M5 priorities and documentation disposition | Recorded | User instructions on 2026-09-24; incorporated in the plan. |
| M5 plan/tracker | Approved | User returned from maintenance and instructed execution on 2026-09-24. |
| Review/signing workflow | Retained | Every Solidity checkpoint, including tests, requires staged review before commit. Documentation-only commits retain existing authorization. |

## Task status

Use `Not started`, `In progress`, `Ready for review`, `Done`, or `Blocked`.
`Ready for review` means implementation, checks, evidence, and staging are
complete. `Done` requires a signed checkpoint and applicable Solidity approval.
Record commit hashes in the next tracker update. Unmet dependencies remain
`Not started`; reserve `Blocked` for a concrete impediment.

| ID | Task | Status | Depends on | Evidence / result |
| --- | --- | --- | --- | --- |
| [M5-01](hook-refactor-m5-plan.md#m5-01-handoff-and-compatibility-inventory) | Qualify handoff and map consumer assumptions, proof owners, and gaps. | Done | Plan review and instruction to execute. | [Qualified identity, consumer assumptions, actual proof boundaries, and cleanup inventory](hook-refactor-m5-results.md#m5-01-handoff-and-compatibility-inventory). |
| [M5-02](hook-refactor-m5-plan.md#m5-02-public-formats-identity-and-source-compatibility) | Qualify public encodings, metadata, decoders, imports, and artifact identity. | Not started | M5-01. | Pending. |
| [M5-03](hook-refactor-m5-plan.md#m5-03-real-integration-behavior-and-deployment) | Qualify actual consumer behavior and factory deployment. | Not started | M5-02. | Pending. |
| [M5-04](hook-refactor-m5-plan.md#m5-04-maintained-integration-and-contributor-guides) | Update maintained integration and hook-development guides. | Not started | M5-02 and M5-03. | Pending. |
| [M5-05](hook-refactor-m5-plan.md#m5-05-final-qualification-and-updated-spec) | Reconcile final tests/compatibility/costs and update the spec for export. | Not started | M5-01 through M5-04. | Pending. |
| [M5-06](hook-refactor-m5-plan.md#m5-06-handoff-export-and-release-tree-cleanup) | Verify external handoff, remove working documents, and qualify release tree. | Not started | M5-05. | Pending. |

## Review and checkpoint register

| Checkpoint | Review state | Signed commit |
| --- | --- | --- |
| M5 planning | User approved execution on return from maintenance. | `f3d5e78`; kethcode SSH signature verified. |
| M5-01 | Documentation/evidence only under existing authorization. | Signed with this checkpoint; hash recorded in the next tracker update. |
| M5-02 | Not started; stage any Solidity changes for review. | Pending. |
| M5-03 | Not started; stage any Solidity changes for review. | Pending. |
| M5-04 | Not started. | Pending. |
| M5-05 | Not started; stage any Solidity changes for review. | Pending. |
| M5-06 | Not started; final documentation removal is authorized after verified export. | Record final status/commit in the external handoff receipt. |

## Starting evidence and watchpoints

These M4 results were identity-qualified in M5-01; they are not fresh M5 runs.
Raw evidence is retained under ignored `audits/hook-refactor/`.

| Evidence / boundary | Starting result or required treatment |
| --- | --- |
| Required full suites | Default, fixed-seed, and deploy each pass 746 reported tests / 51 suites. Nine invariants form one campaign: 2,000 runs, 60,000 calls, zero handler reverts/discards. |
| Source ownership | 754 source entrypoints; all 727 M3 entries retained and 27 M4 additions. Retain the original expectations and account for any later edits. |
| Raw ABI/storage/code | Production ABIs/code match M3/M2. Fresh normalized layouts match M1/M2/M3, 11 entries each. Original callback-input naming allowances are 24 / 24 / 28 for open / fixed / periodic. |
| Original integration behavior | Highest priority. Identify the actual consumer and its expected format/behavior; inspect assertions and mocks rather than treating passing suite totals as sufficient evidence. |
| Lint | 33 untouched Prettier failures; standalone Solhint has zero errors and 22 warnings. All 16 existing M4-changed Solidity files pass formatting. |
| Production deployment headroom | Stored initcode: open 6,196 bytes, fixed 4,834, periodic 1,899. Retain the accepted M1-to-M2 increases in the comparison. |
| Composition limits | Periodic borrow has 653 bytes of stored-initcode headroom; periodic APR replacement has 1,260. Record actual deployment paths per artifact. |
| APR authentication correction | Open/fixed stateful examples now authenticate before selection; regression fails before and passes after. Existing production callback behavior remains unchanged. |
| Alternate routes and lifecycle | Dedicated periodic execution uses current reserves and empty data. Creation, fixed management, and closure have separate boundaries; withdrawal batching continues after closure. |
| External consumers | Repository evidence does not establish successful SDK/app/subgraph execution. Explain observed compatibility consequences without inventing required external changes. |
| Final cleanup | Export and verify before removing working documents. Preserve maintained documentation and excluded user references. |

## Documentation disposition

| Material | Final destination |
| --- | --- |
| Supported callback/access/term/event/authority behavior | Maintained guides under `docs/integrations/` and `docs/protocol/`, with the existing documentation index. |
| How to develop and compose hooks | `docs/integrations/hook-development.md`, using canonical compiling examples. |
| Updated composition spec | Verified `hook-composition.md` in `../hook-refactor-handoff/<run-id>/` for the user's knowledge-base transfer. No copy in the final release tree. |
| Final qualification, referenced raw evidence, cleanup status/commit | External handoff with manifest and hashes; local ignored evidence may also remain. |
| Working behavior map, baseline/design, milestone plans/trackers/results, and spec | Remove the enumerated refactor files from `docs/specs/` in M5-06 after verified export. This tracker is included. |
| Voice guide, PDF, lifecycle sketch | Keep untracked and untouched. |
| Deployment inventories and historical release/audit facts | Preserve their factual meaning; no publication or deployment-status rewrite. |

M5-01 records the exact removal set; M5-06 checks it before deletion. Final
task completion and commit identity move to the external handoff receipt because
the tracker itself does not ship. Release docs must have no links to the removed
working records or local scratch evidence.

## Blockers and next action

No execution blocker is recorded. The user authorized M5 after maintenance.
M5-01 qualified 1,190 current inputs, 88 M4 artifacts, original M1 references,
and tools/settings/dependencies, then mapped actual consumer assertions.
Identified coverage additions are the real factory/lens connection (including
fixed configuration and administrator discovery) and wrapper behavior through
both real factories for all terms. M5-02 handles public formats first; those
integration connections belong to M5-03. No export/deletion or push has occurred.

## Progress log

| Entry | Update |
| --- | --- |
| 2026-09-24: M5 planning | Prioritized public and behavioral integration compatibility, mapped existing consumers/proof owners, retained all remaining milestone work, and added verified external spec/evidence handoff before removal of working documents. Prepared six tasks and preserved the staged Solidity review/signing workflow. Execution has not started. |
| 2026-09-24: M5 authorized / M5-01 complete | User resumed after maintenance and instructed execution. Verified the unchanged M4 handoff, seven M1 reference files and all 1,166 original inputs, signatures, and tools/settings/dependencies. Inspected consumer assertions and mock boundaries, recorded three targeted integration connections, accepted source/ABI differences, and the exact 19-document cleanup set. Documentation-only signed checkpoint; M5-02 follows. |

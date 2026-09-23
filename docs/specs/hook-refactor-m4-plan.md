# M4 plan: extension and composition proof

- Milestone: [M4 — Demonstrate extension and composition](hook-refactor-milestones.md#m4--demonstrate-extension-and-composition).
- Task status and evidence: [M4 tracker](hook-refactor-m4-tracker.md).
- Approved M3 handoff: `eff4d5898a5384b35f16acba23fee2aca47745d0`, reviewed
  and pushed by the user on 2026-09-23.
- M3 implementation: `a0867e059e7929d2aaed7bb3288319501d1ef894`.
- Original compatibility reference: [M1 baseline](hook-refactor-m1-baseline.md).

M2 consolidated shared behavior; M3 made fixed and periodic behavior reusable.
M4 tests whether independent features can use those boundaries together, with
explicit decisions where their behavior overlaps. The [spec](hook-composition.md),
[behavior map](hook-behavior-map.md), [M1 design](hook-refactor-m1-design.md), and
[M3 handoff](hook-refactor-m3-results.md#m4-handoff) define the contract.

This plan is prepared for user review. Execution starts after approval. The
plan owns scope and completion criteria; the tracker owns execution status.

## Outcome and boundaries

Demonstrate three forms of extension: additional checks, independently owned
feature state/APIs, and deliberate replacement of a designated default.
Use small test-only features whose behavior is easy to observe. Their rules
are probes of the architecture, not proposed tranching or lending requirements.

| Probe | Proposed behavior | Boundary being tested |
| --- | --- | --- |
| Recipient restriction | Reject one configured recipient per market; expose the same recipient rule through the existing no-data query. | Additional transfer validation after ordinary credentials, including known lenders and registered wrappers. |
| Transfer amount limit | Enforce a positive maximum scaled amount per transfer and record accepted scaled volume per market. Provide administrator-only configuration and public queries. | A second independent rule on the same callback, feature-owned state/events, explicit ordering, and rollback. The volume is observable accounting, not a cumulative quota that eventually stops every transfer. |
| Borrow amount limit | Enforce a maximum normalized amount per borrow, with market-specific configuration and an observable accepted-amount effect. | Add a fourth policy through new component/integration code; activate and authenticate a normally unused callback. |
| APR default replacement | Return a simple bounded APR/reserve result through `_applyDefaultAprUpdate`, without invoking its inherited implementation. | Select one calculation, prove absent temporary-reserve effects, and retain surrounding term rules and effective-value validation. |

Use the same first two feature implementations with open, fixed, and periodic
behavior. Fixed or periodic plus those features is the three-policy proof;
open remains the absence of an additional schedule policy. Add the borrow
feature to those assemblies for the four-policy proof. The shared base is
infrastructure, not another counted feature. Policy counts describe these
examples; they introduce no architectural limit.

The concrete assembly chooses the order of overlapping rules by explicit
helper calls. Do not rely on a `super` chain silently choosing or dropping a
rule. For transfers, make the ordering visible and exercise rejection after
both credential bookkeeping and an earlier feature write. The APR example
selects a replacement default separately from adding validation; two competing
calculations are not automatically combined.

Reuse or extract existing test probes where useful. If a rule is extracted,
adopt it from its existing mock in the same checkpoint and preserve its tests;
do not leave parallel copies of the same rule. Keep `BaseAccessControls`,
`MarketConstraintHooks`, and the term policies as the owners of existing
behavior. Shared fixtures contain no `test*` or `invariant*` entrypoints.

M4 may expose a missing extension boundary. Demonstrate that gap, make the
smallest justified correction, and stage it with the affected compatibility
checks. A correction is feedback into M2/M3, not permission to redesign their
interfaces speculatively. In particular, resolve callback-configuration access
before using the fourth-feature addition as evidence that existing components
need no edits.

No tranche economics, repayment/default lifecycle, core accounting or batching
change, market/factory ABI expansion, runtime policy installation, capability
ownership flags, new credential-data envelope, deployment publication, or
unrelated tooling work belongs here. M5 retains final refactor qualification
and maintained contributor examples. External SDK/app/subgraph repositories
are not being qualified in M4.

## Deliverables and review workflow

Deliver reusable test-only components, concrete compositions, behavioral proofs
in the canonical suite, any demonstrated boundary correction, and
`hook-refactor-m4-results.md`. Start the results record during execution. Keep
raw manifests, compiler exports, logs, and receipts under ignored
`audits/hook-refactor/m4/<run-id>/`; record paths and hashes in the results.
Retain earlier milestone evidence as references, without claiming fresh runs.

Every task is a checkpoint. For **any checkpoint containing Solidity, including
tests**, complete verification and evidence, update the tracker, stage the
intended diff, and stop for user review before committing or beginning the
next implementation task. Explain behavior, compatibility, and size findings.
After approval, commit as `kethcode <dave@wildcat.finance>` with the selected SSH
key and verify the signature. Substantive post-review edits require review of
the revised staged diff.

Documentation-only checkpoints may be signed under existing authorization.
Record completion in its checkpoint and the hash in the next tracker update.
The user reviews and pushes at milestone end. Do not push or begin M5 under
M4's authorization. Keep the voice guide, reference PDF, and lifecycle sketch
out of commits. Comments must retain technical names and meaningful branch
explanations while following the user's voice guide.

## Task sequence

| Task | Deliverable | Depends on |
| --- | --- | --- |
| M4-01 | Qualify the handoff; map probes, callback flags, test owners, and measurements. | Approved plan and instruction to start M4. |
| M4-02 | Two independent transfer features composed with each term choice. | M4-01. |
| M4-03 | Add the borrow feature, including real callback activation and deployment. | M4-02. |
| M4-04 | Deliberate APR default replacement with explicit skipped effects. | M4-03. |
| M4-05 | Complete alternate-route and lifecycle proofs through real markets. | M4-02 through M4-04. |
| M4-06 | Qualify the composition evidence and hand off to M5. | M4-01 through M4-05. |

## M4-01: Handoff identity and proof map

**Work**

- Record source/dependency identity, tool hashes, effective default/deploy
  settings, and signing identity. Qualify M3's retained receipts, including the
  separate original-test replay, against current inputs. Do not rerun an
  unchanged suite merely to rename its evidence.
- Map each proof to an existing owner and concrete integration point. Use
  `HookExtensionsTest` for overlapping transfer rules, `AprValidationTest` for
  APR selection/validation, and the existing term and production integration
  owners for their distinct lifecycle properties. A new concrete suite is
  justified only for a distinct domain; do not duplicate their test cases.
- Resolve the constructor/flag recipe. Fixed and periodic policies allow a
  concrete assembly to supply `BaseHooks` configuration once. `OpenTermHooks`
  currently supplies fixed flags in its constructor. Identify how an open
  composition can declare required transfer/borrow dispatch while reusing its
  packed adapters and initialization. Do not copy the open implementation or
  let public `config()` disagree with the flags the composition requires.
  Record any demonstrated boundary correction for M4-02 review.
- Specify feature state owners, administrator checks, registration checks,
  defaults at creation, units, helper ordering, and public query promises.
  Features use their own management APIs and existing creation context; they
  do not reinterpret credential `extraData` independently.
- Inventory measurements. M3 leaves periodic 1,899 bytes of stored-initcode
  headroom. Plan real factory deployment of the composed artifacts and
  comparable accepted/rejected transfer, borrow, and APR observations. Keep
  costs of intentionally added rules distinct from production regressions.
- Start the results record with the proof map and evidence disposition.

**Complete when:** every requirement has an owning test and implementation
boundary, callback activation has an explicit configuration recipe or a
documented gap to fix, and retained evidence has attributable inputs.
This checkpoint is documentation/evidence only.

## M4-02: Three-policy checks and feature state

**Work**

- Implement or extract the recipient and transfer-amount probes under
  `test/mocks/`, then explicitly compose them with all three term choices.
  Keep rule bodies in their feature components and composition decisions in
  the concrete assembly. Resolve any demonstrated configuration boundary
  from M4-01 without duplicating existing production behavior.
- Give feature data one authoritative representation keyed by market. Reuse
  the hooks administrator and registration checks for management; distinguish
  two registered markets sharing one instance from an unregistered caller.
  Initialize defaults after term configuration without querying undeployed
  market code. Verify rejected initialization leaves no partial registration
  or feature effects.
- Prove both transfer rules independently reject, both allow a valid action,
  and overlapping failures follow the selected order. Retain minimum-deposit,
  credential, known-lender, and term restrictions. Rejection after earlier
  credential/feature writes must restore all affected state atomically.
- Keep known-recipient and exact registered-wrapper credential exemptions
  local to the default. Both additional rules still apply. Keep the recipient
  view consistent with recipient restrictions; it does not promise that an
  amount, balance, or allowance will pass. Positive per-transfer limits must
  preserve the permanent `isMarketTransferDisabled == false` promise.
- Exercise feature management/query APIs, state/event ownership, multiple
  markets on one instance, and authority after administrator transfer. Prove
  required transfer dispatch can be enabled without requesting transfer
  credentials. Freeze these reusable components as the reference for M4-03.

**Verification:** run existing extension/common/term tests plus the new
runtime-matrix cases in both profiles. Check construction and factory storage
size early; do not defer an oversized periodic composition to qualification.
If production code changes, compare all three production ABIs, layouts,
bytecode/sizes, affected integrations, and relevant costs to M3 and M1.

**Complete when:** one set of independent features works with open, fixed, and
periodic behavior, selected rules and authority are observable, and rejection
preserves shared, term, and feature state. Existing reusable production behavior
still has one owner.

## M4-03: Fourth feature and callback activation

**Work**

- Add the independent borrow-limit component and new concrete assemblies.
  The feature addition may change integration code, but must not require
  edits to the existing two features or reusable base/term implementations.
  If a boundary still needs correction, record it and establish a corrected
  reference before claiming this proof.
- Declare required borrow dispatch in deployment configuration and verify it
  in the bound market's effective flags, even when the borrower omitted it.
  Authenticate the market inside the formerly empty callback before reading
  or writing feature state. Retain the original templates' unguarded no-op
  behavior rather than applying a new global guard.
- Deploy the composed hooks from actual stored initcode and create standard
  and revolving markets through their factories for all three term choices.
  Reuse production fixture helpers; a direct callback impersonation alone
  does not prove activation or deployability.
- Prove below/at/above-limit borrowing, unknown-caller rejection, per-market
  isolation, and continuing enforcement of both earlier transfer features.
  Assert borrowed assets and recorded normalized amounts, not call counters.
- Demonstrate that the feature runs before the rest of the market action.
  A later failing underlying-asset transfer must roll back the feature effect
  as well as market changes. Earlier market borrowability/closed checks retain
  their priority. Keep creation defaults free of undeployed-market reads.

**Verification:** run the composition cases, real factory/dispatch scenarios,
and affected authority/wrapper/standard/revolving checks in both profiles.
Measure runtime, creation, stored initcode, and actual constructor payloads for
each composed artifact. A raised local code-size limit is not deployment
evidence; verify the 24,576-byte runtime/storage and 49,152-byte initcode limits.

**Complete when:** four-policy compositions enforce all selected rules through
real markets, the new callback is declared and dispatched correctly, and the
fourth feature is added without rewriting reusable components.

## M4-04: Deliberate APR default replacement

**Work**

- Add one small test-only replacement of `_applyDefaultAprUpdate`, reusable
  across the term assemblies. Select a bounded result distinguishable from
  the standard temporary-reserve calculation. Preserve APR bounds explicitly;
  replacing the helper also replaces the bounds check inside it.
- Leave each term's `_applyAprUpdate` strategy intact. Fixed must still reject
  reductions before maturity. Periodic increases/equality reach the selected
  default, while proposal-based reductions through either route keep current
  reserves and skip it. Document these choices beside the integration.
- For inputs where the inherited default would activate, update, cancel, or
  expire temporary reserves, assert the replacement's result and effects,
  unchanged seeded default state, and absence of the corresponding default
  events. Seed nonzero state where necessary so an accidental default call
  cannot hide behind an already empty mapping.
- Reuse effective-value validation to prove the selected result is checked
  and a rejection rolls back selected-strategy effects. Keep unrelated access,
  transfer features, withdrawal scheduling, and authority effective. Do not
  call the skipped implementation and merely discard its return values.

**Verification:** run the replacement and existing APR validation/constraint
cases in both profiles, including fixed guard priority and both periodic
execution routes. Distinguish receipt-visible events from reverted execution
traces when asserting absence of committed effects. Recheck new concrete
artifact size and affected production compatibility after any source change.

**Complete when:** results and state/events distinguish the chosen replacement
from the skipped default, and retained term/shared rules still constrain it.

## M4-05: Alternate routes and lifecycle integration

**Work**

- Exercise the assembled behavior through real standard/revolving market
  operations. Add only properties missing from the earlier tasks and retained
  suites; do not create another copy of every term scenario.
- For periodic APR changes, accept a proposal, change an additional validation
  condition, then attempt execution through both entrypoints. Rejection must
  preserve the pending proposal and roll back other effects. Restoring the
  condition permits execution with the original timing/payment guards. Keep
  equality retention, increase cancellation, and closure cancellation covered.
- Verify effective values at the market boundary. Dedicated periodic execution
  returns APR only, preserves current reserves, and provides empty hook data
  even if bytes are appended. A replacement default cannot give this route
  the ability to change reserves.
- Cover creation, fixed setter changes, and early closure as separate paths.
  Setter validation/effects do not implicitly run during initialization or
  closure. Preserve the fixed early-closure permission rule and periodic
  closure's removal of schedule restrictions without bypassing access.
- Make the APR example's closure choice explicit: allow the existing close
  transition without applying an APR floor to the market's forced APR zero.
  The market funds debt, may dispatch repayment, calls closure, then resets
  APR/reserves itself. `_checkAprChange` is not a closure guard. Test any
  chosen extra closure rule through the closure boundary itself.
- Retain market-owned withdrawal batching and post-closure queueing/execution
  behavior. Use actual balances, state, feature records, events, and reverts
  to connect callback decisions to the resulting lifecycle.

**Verification:** run affected term/APR, production matrix, authority, wrapper,
and withdrawal/closure suites in both profiles. Confirm factory deployment of
any additional concrete replacement composition used for these proofs.

**Complete when:** alternate routes and lifecycle paths cannot silently bypass
the selected rules, and the evidence distinguishes intentional exceptions from
missing enforcement or unsupported core capabilities.

## M4-06: Qualification and M5 handoff

**Work**

- Reconcile every spec/M4 requirement with observable evidence and its owning
  suite. Explain new, moved, or removed test cases; preserve existing expected
  behavior and avoid inherited test entrypoints or a permanent legacy oracle.
- Review explicit integration choices: ordering, default selection/skipped
  effects, caller authentication, requested access versus dispatch, state and
  API ownership, both APR routes, queries, and lifecycle boundaries. Identify
  any boundary correction and the proof that adding the fourth feature then
  required only new feature/integration code.
- Run the completed canonical tree with the repository-required commands:

  ```sh
  forge test
  yarn test:fixed
  FOUNDRY_PROFILE=deploy forge test
  yarn lint:check
  ```

  Compare lint against M3, running standalone Solhint if Prettier stops the
  package command. Format only touched files. Repeat affected checks after
  changes or unresolved failures; reuse matching completed evidence otherwise.
- Compare production raw/semantic ABIs, normalized layouts, creation/runtime
  code and sizes to M3 and the M1 compatibility reference. M3's ABIs are the
  immediate expected output; M1's approved unnamed-to-named callback-input
  differences do not authorize further public-format changes. Test features
  may add their own APIs without adding those APIs to the existing templates.
- Reconcile actual deployment limits for every concrete composition. Retain
  original production gas evidence only where executable identity and call
  conditions justify reuse; measure affected paths after production changes.
  Report representative composition costs separately under matching settings,
  state, inputs, isolation, and direct/nested call boundaries.
- Record what the examples establish, where explicit integration remains
  necessary, and remaining core/interface or size constraints. Working examples
  do not establish arbitrary compatibility among all possible policies.
  Hand the final boundaries and examples to M5 contributor documentation and
  qualification; do not start M5 automatically.

**Complete when:** composition, replacement, activation, isolation, and lifecycle
requirements have attributable passing evidence; existing production behavior
and deployment limits remain qualified; the milestone is ready for user review
and push with any limitations stated.

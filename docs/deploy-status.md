# v2.5 Deployment Tooling Status

As of 2026-08-23. Production Solidity is frozen at integration commit `49f891c`, which includes the reviewed gas overlay, the first pre-audit remediations, and the canonical test-suite cutover. Ceremony-only descendants must preserve that production source. A fresh headless Sepolia-fork run from this source is green; the independent locked-UI rehearsal remains required before a live transaction. [deployment.md](./deployment.md) is the process runbook, [deploy-checklist.md](./deploy-checklist.md) is the condensed operator checklist, and [anvil-v2-5-rehearsal.md](./anvil-v2-5-rehearsal.md) is the pre-Sepolia acceptance run.

## Built and verified

**Inventory:** `factory-inventory.json` schema 1.1 is append-only and records `canonical`, `live`, and `retired` factory generations. Activation finalization adds the new generation without changing the registration state of an older generation. Retirement is generated later from the finalized, reconciled inventory and records only the factories actually removed from both ArchController roles. Existing markets are never removed. Live Sepolia and mainnet reconciliation are green.

**Activation plan:** `script/deploy/v2-5/01-07` deploys and configures the new generation. It deploys the wrapper factory, borrower identity registry, AccessList role-provider factory, standard and revolving factories, the four-part lens, and the three supported hook templates. It registers the six factory/template pairs and both new hooks factories. It does not retire an old factory.

**Revolving init code:** `WildcatMarketRevolving` creation code is 23,343 bytes under the locked deploy profile. One leading `STOP` makes the stored runtime 23,344 bytes, leaving 1,232 bytes of EIP-170 margin. The revolving factory uses one storage contract again. The deployment scripts reject the payload before producing a plan or broadcasting if it stops fitting.

**Retirement plan:** `script/deploy/v2-5/retirement/01-generate-plan.sh` reads the post-activation inventory and creates a fresh plan for every still-registered superseded factory. Each factory loses `controllerFactory` before `controller`. `02-finalize-inventory.sh` applies only a fully verified retirement run-state. Sepolia forwards both removals through the persistent authority helper without transferring ArchController ownership.

**Plan engine:** `scripts/plan.js` assembles, validates, executes, verifies, and bundles plans. It accepts a named entries directory so activation and retirement cannot share stale plan entries. Every card has decoded arguments and an on-chain predicate. Forwarded calls preserve their logical target, signature, and decoded arguments while independently encoding the helper transport. Known networks must match their configured chain IDs.

**Safe bundles:** `scripts/plan-bundle.js` turns cards into atomic Safe transactions using `MultiSend` delegatecall and canonical `CreateCall` CREATE2 deployments. Safe nonces are pinned when the package is generated. Safe Transaction Builder JSON is review-only because the Builder drops `operation: 1`; proposals must go through the deploy UI and Safe SDK.

**Release UI:** `deploy-ui/` supports locked EOA and Safe packages. It independently reconstructs calldata from the plan, binds the package to a digest, verifies the connected chain and executor, rechecks receipts and predicates before trusting stored progress, and stops on any failed predicate.

**Sepolia authority:** the version-2 `MockArchControllerOwner` takes an explicit executor set, preserves permissionless testnet borrower registration and legacy fee administration, and forwards one authorized protocol action at a time to tightly bounded targets. `scripts/authority-migration.js` generates three independently reviewable migration plans. `scripts/authority-helper.js` verifies the complete ArchController/SphereX authority shape before atomically finalizing the stable deployment alias. The old wallet remains an authorized helper executor during the validation period.

**Fork launcher:** `rehearse.sh` requires an explicit archive RPC, pins one fork block, verifies historical reads, persists Anvil state, and supports guarded resume. On a Sepolia-shaped fork it performs the three-phase helper rotation first. `--full` then executes and finalizes activation, runs both canary markets, validates the downstream handoff, executes the separate retirement plan, refreshes the handoff, and requires the helper to remain ArchController owner throughout.

**Handoff:** `scripts/generate-handoff.js` reports all factory generations, index flags, start blocks, the borrower identity registry, the AccessList role-provider factory, the revolving init-code storage address, and the v2.5 ABI changes needed by the subgraph and SDK. Its market inventory now includes the exact `queueWithdrawalScaled(uint256)` signature, wrapper registration functions/event/errors, borrower identity and transfer surface, and the rebuilt factory and event model.

## Rehearsal evidence

The 2026-08-23 headless run used production Solidity from `49f891c` and pinned Sepolia block `11548975`. Generated Anvil artifacts are disposable and are not checked in. This proves the current engine, bytecode, plan shape, canaries, handoff, and predicates. It does not approve live addresses or replace the locked-UI walkthrough.

- Current Sepolia authority rotation: five phase-1 cards from the old executor, three phase-2 cards from the new executor, and three delayed phase-3 cards from the new executor all passed. The replacement helper runtime hash was `0x71813272287ef573f8a2f96101f1a9ba6982761ad9de14a3e65e88c236a8a6fa`. The final preflight proved both wallets authorized, helper ownership plus ArchController SphereX admin/operator, helper engine default-admin/operator, revocation of the old wallet's direct engine operator role, and preservation of the ArchController sender-adder role.
- Current Sepolia-shaped activation: 24 cards, consisting of 14 deployments and 10 calls. Eight owner actions were forwarded through the helper. All predicates passed, activation inventory finalization and reconciliation were green, and the helper remained ArchController owner.
- Current Sepolia-shaped acceptance: the standard and revolving canaries both deposited, queued, closed, and finalized. The activation and post-retirement handoffs generated and passed `--check`. Fresh activation and retirement EOA packages were accepted by the locked deploy-profile package validator, and the embedded activation package passed the deploy-UI test/build gate. The browser transaction walkthrough and reload/resume proof remain open.
- Current Sepolia-shaped retirement: nine superseded factories produced 18 forwarded, ordered removals. All predicates passed, retirement inventory finalization and reconciliation were green, no market was removed, and the helper remained ArchController owner.
- Mainnet-shaped activation: 24 cards, consisting of 14 deployments and 10 calls. Direct fork execution, predicate verification, inventory finalization, and reconciliation were green.
- Mainnet-shaped retirement: the finalized rehearsal inventory had one superseded registered factory, producing one two-call retirement plan. Direct fork execution and reconciliation were green.
- Historical Foundation Safe simulation: the 24 activation cards fit into three bundles using 14,417,671, 19,277,694, and 15,179,791 gas. The two retirement cards fit into one bundle using 94,042 gas. Every bundle stayed below the 20,000,000 gas ceiling and every predicate passed through the real Safe execution path. These figures predate the current production Solidity and must be regenerated before mainnet.
- The Foundation Safe was read as version 1.4.1 with threshold 3. The current release therefore requires three activation approvals and one later retirement approval from each participating signer. If the same three signers approve all four bundles, that is 12 signatures total. Cards are inner review actions and do not each need Safe signatures.

The rehearsal Safe nonce, CREATE2 addresses, and generated package hashes are not release constants. Regenerate them from the current Safe state at production freeze and repeat the exact simulation.

## Current release-source status

`49f891c` includes the reviewed 15-commit gas keep-list and the first pre-audit remediation. Four production files changed after the previous ceremony refresh: market reserve accounting, temporary reserve-ratio rounding, lens token metadata decoding, and wrapper escrow provenance. Those changes do not alter the public ABI, but they change the standard/revolving market, hook-template, lens, wrapper, and wrapper-factory bytecode. Every predicted address, package digest, explorer input, and handoff must therefore come from a fresh plan.

The current deploy-profile suite passed 680 tests across 46 suites, and the source-size build is green. The deploy UI passed 34 unit tests, both live-fork engine tests, a production build with a freshly embedded activation package, and `npm audit` with zero advisories. The previously completed subgraph and SDK parity checks cover the current public ABI/event surface. None of that replaces tomorrow's locked-UI ceremony gate.

## Remaining release work

1. Run the fresh Sepolia fork through the locked deploy UI: the three authority packages, activation, reload/resume proof, inventory finalization, canaries, explorer-input checks, and handoff validation. Preserve that final package and commit identity; do not reuse the disposable headless artifacts.
2. Execute the three authority packages on live Sepolia, finalize the helper alias only after the full preflight, and update the prepared SDK ABI/address after the accepted live deployment.
3. Deploy activation on live Sepolia and leave the existing preview factories registered during the validation window.
4. Validate the new generation through the subgraph, SDK, app, and canary flows. Generate the Sepolia retirement plan only after that state is finalized and reconciled.
5. Execute the separate Sepolia retirement ceremony when the preview factories are no longer needed. Remove the old helper executor only in a later, separately reviewed operation after several stable days.
6. At mainnet release freeze, regenerate and simulate the three activation bundles against the current Safe nonce. Run the activation signing session, validate the release, then prepare the separate one-bundle retirement signing session from the post-activation inventory.
7. Move superseded deployment scripts to `script/legacy/` only after the current ceremony is accepted. Plasma explorer configuration remains deferred until those networks onboard.

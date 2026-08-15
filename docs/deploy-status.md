# v2.5 Deployment Tooling Status

As of 2026-08-15. This is the current implementation and rehearsal record. [deployment.md](./deployment.md) is the process runbook, [deploy-checklist.md](./deploy-checklist.md) is the condensed operator checklist, and [anvil-v2-5-rehearsal.md](./anvil-v2-5-rehearsal.md) is the pre-Sepolia acceptance run.

## Built and verified

**Inventory:** `factory-inventory.json` schema 1.1 is append-only and records `canonical`, `live`, and `retired` factory generations. Activation finalization adds the new generation without changing the registration state of an older generation. Retirement is generated later from the finalized, reconciled inventory and records only the factories actually removed from both ArchController roles. Existing markets are never removed. Live Sepolia and mainnet reconciliation are green.

**Activation plan:** `script/deploy/v2-5/01-07` deploys and configures the new generation. It deploys the wrapper factory, borrower identity registry, AccessList role-provider factory, standard and revolving factories, the four-part lens, and the three supported hook templates. It registers the six factory/template pairs and both new hooks factories. It does not retire an old factory.

**Revolving init code:** `WildcatMarketRevolving` creation code is 23,091 bytes under the locked deploy profile. One leading `STOP` makes the stored runtime 23,092 bytes, leaving 1,484 bytes of EIP-170 margin. The revolving factory uses one storage contract again. The deployment scripts reject the payload before producing a plan or broadcasting if it stops fitting.

**Retirement plan:** `script/deploy/v2-5/retirement/01-generate-plan.sh` reads the post-activation inventory and creates a fresh plan for every still-registered superseded factory. Each factory loses `controllerFactory` before `controller`. `02-finalize-inventory.sh` applies only a fully verified retirement run-state. Sepolia independently reclaims and restores the helper owner during both ceremonies.

**Plan engine:** `scripts/plan.js` assembles, validates, executes, verifies, and bundles plans. It accepts a named entries directory so activation and retirement cannot share stale plan entries. Every card has decoded arguments and an on-chain predicate. Known networks must match their configured chain IDs.

**Safe bundles:** `scripts/plan-bundle.js` turns cards into atomic Safe transactions using `MultiSend` delegatecall and canonical `CreateCall` CREATE2 deployments. Safe nonces are pinned when the package is generated. Safe Transaction Builder JSON is review-only because the Builder drops `operation: 1`; proposals must go through the deploy UI and Safe SDK.

**Release UI:** `deploy-ui/` supports locked EOA and Safe packages. It independently reconstructs calldata from the plan, binds the package to a digest, verifies the connected chain and executor, rechecks receipts and predicates before trusting stored progress, and stops on any failed predicate.

**Fork launcher:** `rehearse.sh` requires an explicit archive RPC, pins one fork block, verifies historical reads, persists Anvil state, and supports guarded resume. `--full` executes and finalizes activation, confirms ownership restoration, then generates, executes, and finalizes the separate retirement plan.

**Handoff:** `scripts/generate-handoff.js` reports all factory generations, index flags, start blocks, the borrower identity registry, the AccessList role-provider factory, the revolving init-code storage address, and the v2.5 ABI changes needed by the subgraph and SDK.

## Current rehearsal evidence

These are disposable Anvil forks and generated artifacts are not checked in. They prove the current engine and plan shape, but a fresh locked-UI rehearsal from the reviewed release commit remains the live release gate.

- Sepolia-shaped activation: 26 cards, consisting of 14 deployments and 12 calls. The extra two calls reclaim the ArchController from `MockArchControllerOwner` and return it afterward. All predicates passed, activation inventory finalization and reconciliation were green, and the helper owned the ArchController again.
- Sepolia-shaped retirement: nine superseded factories produced 18 ordered removals, plus independent reclaim and return calls, for 20 cards total. All predicates passed, retirement inventory finalization and reconciliation were green, no market was removed, and the helper owned the ArchController again.
- Mainnet-shaped activation: 24 cards, consisting of 14 deployments and 10 calls. Direct fork execution, predicate verification, inventory finalization, and reconciliation were green.
- Mainnet-shaped retirement: the finalized rehearsal inventory had one superseded registered factory, producing one two-call retirement plan. Direct fork execution and reconciliation were green.
- Exact Foundation Safe simulation: the 24 activation cards fit into three bundles using 14,417,671, 19,277,694, and 15,179,791 gas. The two retirement cards fit into one bundle using 94,042 gas. Every bundle stayed below the 20,000,000 gas ceiling and every predicate passed through the real Safe execution path.
- The Foundation Safe was read as version 1.4.1 with threshold 3. The current release therefore requires three activation approvals and one later retirement approval from each participating signer. If the same three signers approve all four bundles, that is 12 signatures total. Cards are inner review actions and do not each need Safe signatures.

The rehearsal Safe nonce, CREATE2 addresses, and generated package hashes are not release constants. Regenerate them from the current Safe state at production freeze and repeat the exact simulation.

## Remaining release work

1. Run the fresh Sepolia-fork activation through the locked deploy UI in EOA mode, including reload and resume, then complete inventory finalization, canaries, explorer-input checks, and handoff validation.
2. Deploy activation on live Sepolia and leave the existing preview factories registered during the validation window.
3. Validate the new generation through the subgraph, SDK, app, and canary flows. Generate the Sepolia retirement plan only after that state is finalized and reconciled.
4. Execute the separate Sepolia retirement ceremony when the preview factories are no longer needed.
5. At mainnet release freeze, regenerate and simulate the three activation bundles against the current Safe nonce. Run the activation signing session, validate the release, then prepare the separate one-bundle retirement signing session from the post-activation inventory.
6. Move superseded deployment scripts to `script/legacy/` only after the current ceremony is accepted. Plasma explorer configuration remains deferred until those networks onboard.

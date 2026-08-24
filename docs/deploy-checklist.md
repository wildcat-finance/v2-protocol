# v2.5 Deploy Checklists

These are condensed operator checklists. Use [deployment.md](./deployment.md) for the full process and [deploy-status.md](./deploy-status.md) for rehearsal status and evidence. Every command starts at the repository root with `FOUNDRY_PROFILE=deploy`.

Activation and retirement are separate releases. Activation deploys and registers v2.5 without disabling an existing factory. Retirement is generated only after activation has been finalized, indexed, and validated. Never carry a pre-generated retirement plan into the activation call.

## A. Fork test drive

- [ ] Record the reviewed source revision, confirm `git diff --quiet 49f891c93768f9986f985204c2f533c77c5e6f60 -- src`, and preserve any existing `deployments/anvil/`. The launcher replaces that directory and stops only an Anvil process using the selected port.
- [ ] Run the full deploy-profile protocol test suite and a deploy-profile source size build.
- [ ] In `deploy-ui/`, run `npm ci`, `npm audit`, `npm test`, `npm run build`, and `SEPOLIA_RPC_URL="$FORK_RPC_URL" npm run test:fork` after the deploy-profile build has produced current artifacts.
- [ ] Use one explicitly selected archive RPC and confirm its chain ID and historical storage access. Do not add an implicit fallback.
- [ ] Fund both real executor wallets on Sepolia before pinning the fork. The user-driven rehearsal must not impersonate either account or replace its balance.
- [ ] Start a fresh fork with `FORK_NETWORK=sepolia FORK_RPC_URL=https://eth-sep.hinterlight.net ANVIL_PORT=8547 bash script/deploy/v2-5/rehearse.sh`.
- [ ] Confirm the launcher stops after preparing authority phase 1. No transaction has executed. Walk its five cards in the locked UI with `0xca732651410E915090d7A7D889A1E44eF4575fcE`, then export the unedited run-state.
- [ ] Run `bash script/deploy/v2-5/rehearse-stage.sh phase-2`. Walk its three cards with `0xca7007a75296b532ce1606d9e130eaa849800ca7`, then export the unedited run-state.
- [ ] Run `bash script/deploy/v2-5/rehearse-stage.sh advance-delay`, review the recorded timestamp change, then run `bash script/deploy/v2-5/rehearse-stage.sh phase-3` and walk its three cards with the new wallet.
- [ ] Run the authority-helper preflight. Confirm the replacement helper owns the ArchController, holds the expected SphereX roles, authorizes both wallets, and the old wallet has no direct engine operator role.
- [ ] Run `bash script/deploy/v2-5/rehearse-stage.sh activation`. Confirm its 24 cards: 14 deployments, 10 calls, eight forwarded owner actions, six template registrations, two new factory registrations, and no ownership handoff or factory/market removal.
- [ ] Walk the activation cards with the new wallet. At a midpoint, export a checkpoint and prove same-fork reload and resume. Every predicate must turn green from on-chain verification.
- [ ] Export the unedited activation run-state and run `bash script/deploy/v2-5/rehearse-stage.sh finalize-activation`.
- [ ] Run inventory validation, lint, reconciliation, and the authority-helper preflight. Confirm the helper remained the ArchController owner throughout.
- [ ] Validate the generated handoff. Fork-only canaries are optional supplemental contract-flow coverage, not wallet-ceremony acceptance.
- [ ] Preserve `source-commit`, the plan, package digest, run-states, transaction hashes, fork block, Anvil state snapshot, and final inventory as rehearsal evidence. Stop only the recorded Anvil PID.

Retirement is a later ceremony. Rehearse it from a fresh fork of the accepted
post-activation Sepolia state when the validation window is complete.

`rehearse.sh --full` performs authority migration, activation, canaries,
handoff checks, and retirement headlessly. It is useful as an engine check but
does not replace the real-wallet locked-UI acceptance run.

## B. Live Sepolia activation

- [ ] Confirm the exact deployment-affecting source passed the fresh Anvil rehearsal.
- [ ] Execute and independently verify the three authority-helper migration packages from [sepolia-v2-5-first-deployment.md](./sepolia-v2-5-first-deployment.md): phase 1 with the old wallet, phases 2 and 3 with the new wallet, respecting the SphereX delay.
- [ ] Generate phase 2 and phase 3 only from the verified phase-1 run-state. Do not reuse pre-generated authority plans or resolve either phase against the legacy helper.
- [ ] Finalize the deployment alias only after the replacement helper passes the full authority preflight. Preserve the original address as `MockArchControllerOwnerLegacy` and keep the old wallet authorized by the replacement helper.
- [ ] Reconcile the live Sepolia inventory before generating anything.
- [ ] Set `DEPLOYMENTS_NETWORK=sepolia`, `RELEASE_TAG=v2-5`, `OWNER_MODE=plan`, the reviewed RPC, and the exact expected executor.
- [ ] Run deployment steps 01 through 06, then `bash script/deploy/v2-5/07-generate-plan.sh`.
- [ ] Confirm the activation plan has 24 cards: 14 deployments and 10 calls. Eight owner actions must use the reviewed helper forwarding path. It must register six templates and two factories and contain no ownership handoff, `removeControllerFactory`, `removeController`, or `removeMarket` call.
- [ ] Confirm the deployment list includes the borrower identity registry, AccessList role-provider factory, and revolving init-code storage contract.
- [ ] Generate the locked EOA package, record its digest and fingerprint, and build the production UI with that package embedded.
- [ ] Walk all 24 activation cards with the new Sepolia executor. Wait for each receipt and predicate before proceeding.
- [ ] Export and independently verify the activation run-state. Finalize with `08-finalize-inventory.sh`, then validate, lint, and reconcile the inventory.
- [ ] Re-run the authority preflight, verify every deployment on the explorer, and generate and check the subgraph/SDK handoff. Sepolia canaries are optional follow-up validation, not an activation gate.
- [ ] Leave the preview factories registered while the new generation is tested through the subgraph, SDK, and app.

## C. Live Sepolia retirement

- [ ] Start from the committed post-activation inventory and reconcile it against live Sepolia.
- [ ] Confirm the new v2.5 generation has passed the agreed validation window and the team intends to stop new origination through every listed superseded factory.
- [ ] Set the same reviewed network, RPC, and executor values, then run `bash script/deploy/v2-5/retirement/01-generate-plan.sh`.
- [ ] Review the dynamic target list and exact plan. Each target must have `removeControllerFactory(address)` immediately before `removeController(address)`. The plan must contain no deployment, registration, or market-removal call.
- [ ] Confirm every retirement call uses the reviewed helper forwarding path and the plan contains no ownership handoff. Do not reuse activation run-state or browser progress.
- [ ] Generate a locked EOA package for `v2-5-retirement`, record its separate digest and fingerprint, and execute it as a separate ceremony.
- [ ] Independently verify the retirement run-state and finalize it with `RUN_STATE=deployments/sepolia/run-state-v2-5-retirement.json RPC_URL="$RPC_URL" bash script/deploy/v2-5/retirement/02-finalize-inventory.sh`.
- [ ] Validate, lint, and reconcile the final inventory. Re-run the authority preflight and confirm existing markets remain registered.

## D. Mainnet activation with the Foundation Safe

- [ ] Reconcile mainnet, freeze the reviewed source and configuration, and have the Foundation signers on the call.
- [ ] Generate steps 01 through 07 with `DEPLOYMENTS_NETWORK=mainnet` and `EXPECTED_EXECUTOR=0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`.
- [ ] Confirm the activation plan has 24 cards: 14 deployments and 10 calls, with no retirement or market-removal call.
- [ ] Read the current Safe nonce immediately before packaging. Bundle the exact plan with `node scripts/plan.js bundle --plan deployments/mainnet/plan-v2-5.json --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae --start-nonce <nonce>`.
- [ ] Confirm the current activation compiles to three bundles. Rehearse those exact bundles through the real Safe path on a pinned mainnet fork and require every predicate to pass below the 20,000,000 gas ceiling.
- [ ] Generate the Safe ceremony package, record its digest and fingerprint, distribute the review sheet, and build the locked production UI.
- [ ] For each of the three bundles, the operator proposes with `operation: 1`, the threshold signers approve once, and the operator executes after threshold. Do not use Safe Transaction Builder to propose.
- [ ] Export or derive the activation run-state, independently verify it, finalize it with step 08, and reconcile.
- [ ] Verify deployments, run release checks, and deliver the generated handoff. Leave the superseded factory registered during validation.

The 24 cards are inner review actions inside the generated Safe transactions. Each transaction needs the Safe's normal threshold approval, not one signature per card.

## E. Mainnet retirement with the Foundation Safe

- [ ] Begin only after activation finalization and the agreed validation window. Reconcile the post-activation inventory first.
- [ ] Read the current Safe nonce again. Do not assume it is the activation start nonce plus three.
- [ ] Generate `plan-v2-5-retirement.json` from the current inventory and review every target. The rehearsed inventory produced one target and two ordered calls; regenerate if live state differs.
- [ ] Bundle and simulate the exact retirement plan as a new release package. The rehearsed plan fits into one Safe bundle.
- [ ] Run a separate signer session. Each threshold signer approves the single retirement bundle once, then the operator executes and verifies both predicates.
- [ ] Finalize with `retirement/02-finalize-inventory.sh`, reconcile, and confirm existing markets remain registered and usable.

Across the currently rehearsed activation and retirement plans, the Foundation handles four Safe transactions. With threshold 3 and the same three participating signers, that is four approvals per signer and 12 signatures total.

## Reference facts

- Foundation Safe: `0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`, version 1.4.1, threshold 3 at the rehearsal snapshot.
- Historical activation rehearsal gas: 14,417,671, 19,277,694, and 15,179,791. Regenerate from the final production source and current Safe nonce.
- Historical retirement rehearsal gas: 94,042 for one target. Regenerate from the post-activation inventory.
- Safe nonces, CREATE2 addresses, package hashes, gas use, and retirement target counts must be regenerated at release freeze.
- `FOUNDRY_PROFILE=deploy` is mandatory. The revolving market creation code fits one init-code storage contract under that exact profile, and plan generation rejects it if that stops being true.
- Current revolving market creation code is 23,343 bytes. The stored runtime is 23,344 bytes including its leading `STOP`, leaving 1,232 bytes of EIP-170 margin.
- Canonical Safe libraries: MultiSend `0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526` and CreateCall `0x9b35Af71d77eaf8d7e40252370304687390A1A52`.

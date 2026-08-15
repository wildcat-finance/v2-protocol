# v2.5 Deploy Checklists

These are condensed operator checklists. Use [deployment.md](./deployment.md) for the full process and [deploy-status.md](./deploy-status.md) for current rehearsal evidence. Every command starts at the repository root with `FOUNDRY_PROFILE=deploy`.

Activation and retirement are separate releases. Activation deploys and registers v2.5 without disabling an existing factory. Retirement is generated only after activation has been finalized, indexed, and validated. Never carry a pre-generated retirement plan into the activation call.

## A. Fork test drive

- [ ] Record the reviewed source revision and preserve any existing `deployments/anvil/`. The launcher replaces that directory and stops only an Anvil process using the selected port.
- [ ] Run the full deploy-profile protocol test suite and a deploy-profile source size build.
- [ ] Run `npm ci && npm test` in `deploy-ui/`.
- [ ] Use one explicitly selected archive RPC and confirm its chain ID and historical storage access. Do not add an implicit fallback.
- [ ] Start a fresh fork with `FORK_NETWORK=sepolia FORK_RPC_URL=https://eth-sep.hinterlight.net ANVIL_PORT=8547 bash script/deploy/v2-5/rehearse.sh`.
- [ ] Confirm the activation plan has 27 cards on the Sepolia-shaped fork: 15 deployments, 12 calls, reclaim first, restore last, six template registrations, two new factory registrations, and no factory or market removals.
- [ ] Build a locked EOA ceremony package and walk the activation cards through the production UI. Prove same-fork reload and resume. Every predicate must turn green from on-chain verification.
- [ ] Export the unedited activation run-state, run independent plan verification, and finalize it with `08-finalize-inventory.sh`.
- [ ] Run inventory validation, lint, and reconciliation. Confirm the helper owns the ArchController again.
- [ ] Run both canary markets and validate the generated handoff.
- [ ] Generate retirement only now with `bash script/deploy/v2-5/retirement/01-generate-plan.sh`.
- [ ] Review every retirement target from the finalized inventory. The current Sepolia inventory produces nine targets, 18 ordered removals, and two helper-owner calls for 20 cards. There must be no market removal.
- [ ] Build and walk a separate locked EOA retirement package. Verify every predicate, finalize it with `retirement/02-finalize-inventory.sh`, reconcile again, and confirm ownership is back with the helper.
- [ ] Preserve the plan, package digest, run-states, transaction hashes, logs, fork block, and final inventory as rehearsal evidence. Stop only the recorded Anvil PID.

`rehearse.sh --full` performs the same activation/finalization/retirement sequence headlessly. It is useful as an engine check but does not replace the locked-UI acceptance run.

## B. Live Sepolia activation

- [ ] Confirm the exact deployment-affecting source passed the fresh Anvil rehearsal.
- [ ] Reconcile the live Sepolia inventory before generating anything.
- [ ] Set `DEPLOYMENTS_NETWORK=sepolia`, `RELEASE_TAG=v2-5`, `OWNER_MODE=plan`, the reviewed RPC, and the exact expected executor.
- [ ] Run deployment steps 01 through 06, then `bash script/deploy/v2-5/07-generate-plan.sh`.
- [ ] Confirm the activation plan has 27 cards: 15 deployments and 12 calls. It must reclaim first, restore last, register six templates and two factories, and contain no `removeControllerFactory`, `removeController`, or `removeMarket` call.
- [ ] Confirm the deployment list includes the borrower identity registry, AccessList role-provider factory, and both revolving init-code storage contracts.
- [ ] Generate the locked EOA package, record its digest and fingerprint, and build the production UI with that package embedded.
- [ ] Walk all 27 activation cards with the exact Sepolia developer EOA. Wait for each receipt and predicate before proceeding.
- [ ] Export and independently verify the activation run-state. Finalize with `08-finalize-inventory.sh`, then validate, lint, and reconcile the inventory.
- [ ] Verify every deployment on the explorer, run the standard and revolving canaries, and generate and check the subgraph/SDK handoff.
- [ ] Leave the preview factories registered while the new generation is tested through the subgraph, SDK, and app.

## C. Live Sepolia retirement

- [ ] Start from the committed post-activation inventory and reconcile it against live Sepolia.
- [ ] Confirm the new v2.5 generation has passed the agreed validation window and the team intends to stop new origination through every listed superseded factory.
- [ ] Set the same reviewed network, RPC, and executor values, then run `bash script/deploy/v2-5/retirement/01-generate-plan.sh`.
- [ ] Review the dynamic target list and exact plan. Each target must have `removeControllerFactory(address)` immediately before `removeController(address)`. The plan must contain no deployment, registration, or market-removal call.
- [ ] Confirm the retirement plan has its own helper reclaim and restore cards. Do not reuse activation run-state or browser progress.
- [ ] Generate a locked EOA package for `v2-5-retirement`, record its separate digest and fingerprint, and execute it as a separate ceremony.
- [ ] Independently verify the retirement run-state and finalize it with `RUN_STATE=deployments/sepolia/run-state-v2-5-retirement.json RPC_URL="$RPC_URL" bash script/deploy/v2-5/retirement/02-finalize-inventory.sh`.
- [ ] Validate, lint, and reconcile the final inventory. Confirm the helper owns the ArchController and existing markets remain registered.

## D. Mainnet activation with the Foundation Safe

- [ ] Reconcile mainnet, freeze the reviewed source and configuration, and have the Foundation signers on the call.
- [ ] Generate steps 01 through 07 with `DEPLOYMENTS_NETWORK=mainnet` and `EXPECTED_EXECUTOR=0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`.
- [ ] Confirm the activation plan has 25 cards: 15 deployments and 10 calls, with no retirement or market-removal call.
- [ ] Read the current Safe nonce immediately before packaging. Bundle the exact plan with `node scripts/plan.js bundle --plan deployments/mainnet/plan-v2-5.json --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae --start-nonce <nonce>`.
- [ ] Confirm the current activation compiles to three bundles. Rehearse those exact bundles through the real Safe path on a pinned mainnet fork and require every predicate to pass below the 20,000,000 gas ceiling.
- [ ] Generate the Safe ceremony package, record its digest and fingerprint, distribute the review sheet, and build the locked production UI.
- [ ] For each of the three bundles, the operator proposes with `operation: 1`, the threshold signers approve once, and the operator executes after threshold. Do not use Safe Transaction Builder to propose.
- [ ] Export or derive the activation run-state, independently verify it, finalize it with step 08, and reconcile.
- [ ] Verify deployments, run release checks, and deliver the generated handoff. Leave the superseded factory registered during validation.

The 25 cards are inner review actions inside three Safe transactions. With threshold 3, activation needs three approvals from each participating signer, not 25. If the same three signers participate, activation produces nine signatures total.

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
- Current activation bundle gas: 17,561,801, 18,107,377, and 14,771,586.
- Current retirement bundle gas: 94,042 for the one-target mainnet rehearsal.
- Safe nonces, CREATE2 addresses, package hashes, gas use, and retirement target counts must be regenerated at release freeze.
- `FOUNDRY_PROFILE=deploy` is mandatory. The revolving market uses two init-code storage contracts because one EIP-170 payload is too small.
- Canonical Safe libraries: MultiSend `0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526` and CreateCall `0x9b35Af71d77eaf8d7e40252370304687390A1A52`.

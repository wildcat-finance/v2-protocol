# v2.5 Deploy Checklists

Condensed operator checklists. The full runbook with explanations is
[deployment.md](./deployment.md); current tooling status is
[deploy-status.md](./deploy-status.md). Every command assumes repo root and
`FOUNDRY_PROFILE=deploy`.

## A. Fork test drive (frontend, EOA mode)

The "kick the tires" loop. No live network is touched.

- [ ] `FORK_NETWORK=sepolia bash script/deploy/v2-5/rehearse.sh`
      (set `FORK_RPC_URL` to your archive node; add `--full` instead for the
      headless end-to-end run with no frontend)
- [ ] `cd deploy-ui && npm install && npm run dev` → open the printed URL
- [ ] Wallet: add network `http://127.0.0.1:8547`, chainId `31337`; import
      the executor key the script prints (the rehearsal authorizes it in the
      helper; the first and last cards reclaim and restore ownership)
- [ ] Load `deployments/anvil/plan-v2-5.json` in the page — EOA mode, plan
      only, no bundles
- [ ] Walk the cards; every predicate must go green; try a reload mid-way to
      see resume
- [ ] Export run-state → run step 08 (command printed by the script);
      reconcile must be GREEN
- [ ] Clean up: kill anvil, `rm -rf deployments/anvil`

## B. Live Sepolia rollout (the real test deploy)

Mints the real v2.5 generation on Sepolia. Dev EOA signs.

The first-time, command-by-command operator procedure is
[sepolia-v2-5-first-deployment.md](./sepolia-v2-5-first-deployment.md). Use that
walkthrough for the live run; the bullets below are only a condensed index.

- [ ] Preflight: `node scripts/factory-inventory.js reconcile --network sepolia
      --rpc-url "$RPC_URL"` → GREEN before starting
- [ ] Env: `DEPLOYMENTS_NETWORK=sepolia RELEASE_TAG=v2-5 OWNER_MODE=plan
      EXPECTED_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE
      RPC_URL=<sepolia rpc>`
- [ ] Generate: run steps 01–06 (`forge script
      script/deploy/v2-5/NN-*.s.sol --rpc-url "$RPC_URL"`), then `bash
      script/deploy/v2-5/07-generate-plan.sh`
- [ ] Confirm the dev EOA is authorized in `MockArchControllerOwner`; the
      generated plan has 24 cards, including reclaim first and restore last
- [ ] Package and build: `plan.js ceremony-package --mode eoa`, then build
      deploy-ui with `CEREMONY_PACKAGE=../deployments/sepolia/ceremony-v2-5-eoa.json`
- [ ] Drive the embedded EOA ceremony with the exact dev EOA in the browser wallet
      (or headless: `node scripts/plan.js execute --plan
      deployments/sepolia/plan-v2-5.json --rpc <rpc> --private-key <pk>`)
- [ ] All 24 cards complete; the final ownership predicate is green;
      export/collect run-state
- [ ] Finalize: `RUN_STATE=deployments/sepolia/run-state-v2-5.json
      RPC_URL=<rpc> bash script/deploy/v2-5/08-finalize-inventory.sh`
      → apply-run + reconcile GREEN
- [ ] Canary: `09-canary-market.sh` (BORROWER must be registered and
      CANARY_ASSET deliberately selected)
- [ ] Explorer verification: `forge verify-contract` per new deployment
      (preserve the deploy-profile standard JSON inputs in `deployments/sepolia/`)
- [ ] Handoff: `node scripts/generate-handoff.js --network sepolia
      --release v2-5` → send to subgraph/SDK
- [ ] Commit the inventory + handoff changes

## C. Mainnet ceremony (Foundation Safe)

After Sepolia is proven and the release is blessed.

- [ ] Preflight: reconcile GREEN on mainnet; team on the call; signers ready
- [ ] Generate 01–06 + 07 with `DEPLOYMENTS_NETWORK=mainnet
      EXPECTED_EXECUTOR=0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`
- [ ] Read and freeze the current Safe nonce; bundle with `--start-nonce`:
      `node scripts/plan.js bundle --plan deployments/mainnet/plan-v2-5.json
      --safe 0xC15b…D9Ae --start-nonce <nonce>` → expected 2–4 bundles
- [ ] Rehearse the exact bundles on a mainnet fork:
      `plan.js bundle-simulate` → all predicates green, gas under ceiling
- [ ] Generate the Safe ceremony package; build deploy-ui with that package
      embedded; distribute `review-v2-5.md`, digest, and fingerprint
- [ ] Host the resulting static `dist/`; confirm it opens in locked Safe mode
      with no file selection
- [ ] Per generated bundle: operator proposes (page, `operation: 1`) → signers
      review card + sign (3 sigs) → operator executes → predicate board
      green. TX Builder import must NOT be used to propose.
- [ ] Export run-state (or `plan.js bundle-verify`) → step 08 → reconcile
      GREEN
- [ ] Explorer verification per deployment; handoff generation; commit
- [ ] Post-ceremony: `plan.js verify` full pass; subgraph/SDK teams pick up
      the handoff

## Reference facts

- Foundation Safe: `0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae` (v1.4.1,
  threshold 3) — mainnet ArchController owner
- Historical pre-sixth-registration bundle gas: ~15.8M / 17.3M / 9.8M. Do not
  reuse it; regenerate and re-simulate the current mainnet bundles against the
  20M ceiling.
- `FOUNDRY_PROFILE=deploy` is mandatory (HooksFactoryRevolving exceeds
  EIP-170 on the default profile)
- Canonical Safe libs (both networks): MultiSend
  `0x3886…B526`, CreateCall `0x9b35…1A52`

# v2.5 Sepolia-fork rehearsal

Use this checklist for the release-acceptance rehearsal. It uses the real
wallets and live Sepolia contracts on a pinned Anvil fork. Every transaction
goes through the locked deployment UI.

The normal path must not impersonate accounts, inject ETH, change storage, or
send a transaction before the UI. Its only fork-only action is the explicit
timestamp advance. Do not use `rehearse.sh --full` for acceptance; it is
headless test coverage. Retirement is a separate ceremony.

## Fixed inputs

| Item | Expected value |
| --- | --- |
| Fork | Sepolia `11155111`; wallet network Anvil `31337` |
| Old executor | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| New executor | `0xca7007a75296b532ce1606d9e130eaa849800ca7` |
| ArchController | `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f` |
| Legacy helper | `0xa476920af80B587f696734430227869795E2Ea78` |
| Solidity baseline | `49f891c93768f9986f985204c2f533c77c5e6f60` |

The replacement helper must keep both executors authorized. Phase 3 removes
only the old executor's direct SphereX engine operator role.

## Stop conditions

Stop on source or fork drift, an unfunded wallet, the wrong wallet or chain, a
changed package digest, a failed transaction, a red predicate, or failed
run-state verification. Preserve the package, run-state, transaction hashes,
browser state, and Anvil log before diagnosing anything. Never edit a plan or
run-state.

For every package: confirm chain `31337`, the expected wallet, digest, and card
count; execute in order; wait for each receipt and predicate; export the
run-state unchanged.

## 1. Prepare

- [ ] Fund both wallets on Sepolia before creating the fork.
- [ ] From the `v2-protocol` repository root, set the environment and record
      the exact source:

```bash
export FOUNDRY_PROFILE=deploy
export FORK_NETWORK=sepolia
export FORK_RPC_URL=https://eth-sep.hinterlight.net
unset FORK_FALLBACK_RPC_URL
export ANVIL_PORT=8547
export ANVIL_STARTUP_TIMEOUT=120
export OLD_EXECUTOR=0xca732651410E915090d7A7D889A1E44eF4575fcE
export NEW_EXECUTOR=0xca7007a75296b532ce1606d9e130eaa849800ca7
export PRODUCTION_SOLIDITY_BASELINE=49f891c93768f9986f985204c2f533c77c5e6f60

git branch --show-current
git rev-parse HEAD
git status --short
git diff --quiet "$PRODUCTION_SOLIDITY_BASELINE" -- src
```

- [ ] Run the cold gates:

```bash
forge test
forge build --sizes src script/common script/deploy/v2-5

(
  cd deploy-ui
  npm ci
  npm audit
  npm test
  npm run build
  SEPOLIA_RPC_URL="$FORK_RPC_URL" npm run test:fork
)
```

## 2. Start the fork and UI

- [ ] Start a fresh fork. The launcher must pin one block, find both funded
      wallets, build a five-card phase-1 package, and execute nothing.

```bash
bash script/deploy/v2-5/rehearse.sh
```

- [ ] Serve the locked UI in a second terminal:

```bash
(cd deploy-ui && npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort)
```

- [ ] Add `http://127.0.0.1:8547` as chain `31337` in the browser wallet. Keep
      this fork and preview server running through activation.

## 3. Rotate the authority helper

### Phase 1: old executor

- [ ] Connect `0xca732651410E915090d7A7D889A1E44eF4575fcE` and confirm five cards: deploy
      the replacement helper with both wallets authorized; reclaim and transfer
      ArchController ownership; start both SphereX admin transfers.
- [ ] Execute and export
      `deployments/anvil/run-state-authority-helper-phase-1.json`.
- [ ] Prepare phase 2:

```bash
bash script/deploy/v2-5/rehearse-stage.sh phase-2
```

### Phase 2: new executor

- [ ] Reload the UI with `0xca7007a75296b532ce1606d9e130eaa849800ca7` and confirm three cards: accept
      ArchController SphereX administration; move its operator role to the
      helper; register the new wallet as a Sepolia borrower.
- [ ] Execute and export
      `deployments/anvil/run-state-authority-helper-phase-2.json`.
- [ ] Advance only the disposable fork, then review
      `deployments/anvil/authority-delay-rehearsal.json`:

```bash
bash script/deploy/v2-5/rehearse-stage.sh advance-delay
```

- [ ] Prepare phase 3:

```bash
bash script/deploy/v2-5/rehearse-stage.sh phase-3
```

### Phase 3: new executor

- [ ] Reload the UI with the new executor and confirm three cards: accept
      SphereX engine administration; grant the helper its operator role; revoke
      the old wallet's direct operator role. There must be no helper
      deauthorization card.
- [ ] Execute and export
      `deployments/anvil/run-state-authority-helper-phase-3.json`.

## 4. Activate v2.5

- [ ] Generate the activation package:

```bash
bash script/deploy/v2-5/rehearse-stage.sh activation
```

- [ ] Confirm the authority preflight passes and both wallets remain authorized.
- [ ] Reload the UI with the new executor. Confirm 24 cards: 14 deployments, 10
      calls, eight forwarded owner actions, six template registrations, two
      factory registrations, and no ownership handoff, retirement, or market
      removal.
- [ ] Execute in order. At a reviewed midpoint, export
      `run-state-v2-5-checkpoint.json`, reload, resume, and confirm prior
      receipts and predicates are rechecked.
- [ ] Export `deployments/anvil/run-state-v2-5.json`.
- [ ] Finalize:

```bash
bash script/deploy/v2-5/rehearse-stage.sh finalize-activation
```

- [ ] Confirm inventory validation, lint, reconciliation, authority preflight,
      and handoff checks pass.
- [ ] Confirm both wallets remain authorized and the old wallet has no direct
      SphereX engine operator role.

Optional: run the standard and revolving canaries on this disposable fork.
They are supplemental contract-flow coverage, not wallet-ceremony acceptance
and not a live deployment requirement:

```bash
cast rpc anvil_impersonateAccount "$NEW_EXECUTOR" --rpc-url "http://127.0.0.1:$ANVIL_PORT"
OWNER_MODE=direct DEPLOYMENTS_NETWORK=anvil BORROWER="$NEW_EXECUTOR" \
  RPC_URL="http://127.0.0.1:$ANVIL_PORT" RELEASE_TAG=v2-5 \
  bash script/deploy/v2-5/09-canary-market.sh
```

## 5. Preserve evidence and stop

- [ ] Preserve `source-commit`, the fork block, four plan/package digests, four
      unedited final run-states, transaction hashes, delay evidence, the
      midpoint checkpoint, final inventory, reconciliation, authority
      preflight, handoff, and Anvil state snapshot.
- [ ] Record status, then stop only the recorded Anvil process:

```bash
bash script/deploy/v2-5/rehearse-stage.sh status
kill "$(cat deployments/anvil/anvil.pid)"
```

## Recovery

After an Anvil crash, restore the persisted fork. Do not run fresh setup first:

```bash
FORK_NETWORK=sepolia \
FORK_RPC_URL="$FORK_RPC_URL" \
ANVIL_PORT="$ANVIL_PORT" \
bash script/deploy/v2-5/rehearse.sh --resume
```

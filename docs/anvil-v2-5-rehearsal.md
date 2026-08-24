# v2.5 Sepolia-fork rehearsal

Rehearse the live Sepolia ceremony against a pinned Anvil fork with the real
wallets and the locked deployment UI. The operator sequence is the live
sequence. The only fork-only steps are starting, resuming, advancing time, and
stopping Anvil.

Do not use `rehearse.sh --full` for release acceptance. It impersonates
accounts for headless engine coverage. Retirement is a later ceremony.

## Fixed inputs

| Item              | Expected value                               |
| ----------------- | -------------------------------------------- |
| Fork              | Sepolia `11155111` on local chain `31337`    |
| Old executor      | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| New executor      | `0xca7007a75296b532ce1606d9e130eaa849800ca7` |
| ArchController    | `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f` |
| Legacy helper     | `0xa476920af80B587f696734430227869795E2Ea78` |
| Solidity baseline | `49f891c93768f9986f985204c2f533c77c5e6f60`   |

The replacement helper must keep both wallets authorized. Phase 3 removes only
the old wallet's direct SphereX engine operator role.

## Stop conditions

Stop on source or fork drift, an unfunded wallet, the wrong chain or wallet, a
changed package digest, a failed transaction, a red predicate, or failed
run-state verification. Preserve the exact package, run-state, browser state,
transaction hashes, Anvil state, and log before diagnosing. Never edit a plan
or run-state.

Phase 1 cards 2 and 3 are one ownership handoff. If interrupted after reclaim,
resume the same reviewed package and complete the transfer before stopping.

For every package: stop the preview, run the next stage, restart the preview,
confirm chain `31337`, wallet, digest, fingerprint, and card count, execute in
order, wait for every receipt and predicate, then export the run-state unchanged.

## 1. Prepare

- [ ] From the `v2-protocol` repository root, set the target:

```bash
cd "$(git rev-parse --show-toplevel)"
set -euo pipefail

export FOUNDRY_PROFILE=deploy
export FORK_NETWORK=sepolia
export FORK_RPC_URL=https://eth-sep.hinterlight.net
unset FORK_FALLBACK_RPC_URL
export ANVIL_PORT=8547
export ANVIL_STARTUP_TIMEOUT=120
export DEPLOYMENTS_NETWORK=anvil
export RPC_URL="http://127.0.0.1:$ANVIL_PORT"
export PRODUCTION_SOLIDITY_BASELINE=49f891c93768f9986f985204c2f533c77c5e6f60

stage() {
  bash script/deploy/v2-5/ceremony-stage.sh "$@"
}
```

- [ ] Require a clean, pushed source and unchanged production Solidity:

```bash
git branch --show-current
git rev-parse HEAD
test "$(git rev-parse HEAD)" = "$(git rev-parse '@{upstream}')"
test -z "$(git status --porcelain)"
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

- [ ] Fund both real wallets on Sepolia, then start a fresh fork. This seeds
      `deployments/anvil` and executes nothing:

```bash
bash script/deploy/v2-5/rehearse.sh
```

## 2. Execute the shared sequence

| Stage                 | Wallet | Cards | Output                                                      |
| --------------------- | ------ | ----: | ----------------------------------------------------------- |
| `phase-1`             | old    |     5 | `deployments/anvil/run-state-authority-helper-phase-1.json` |
| `phase-2`             | new    |     3 | `deployments/anvil/run-state-authority-helper-phase-2.json` |
| `delay`               | none   |     0 | `deployments/anvil/authority-delay-v2-5.json`               |
| `phase-3`             | new    |     3 | `deployments/anvil/run-state-authority-helper-phase-3.json` |
| `activation`          | new    |    24 | `deployments/anvil/run-state-v2-5.json`                     |
| `finalize-activation` | none   |     0 | inventory, reconciliation, preflight, and handoff           |
| `status`              | none   |     0 | `deployments/anvil/status-v2-5.txt`                         |

- [ ] Prepare phase 1:

```bash
stage phase-1
```

- [ ] In a second terminal, serve the exact build:

```bash
(cd deploy-ui && npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort)
```

- [ ] Add `http://127.0.0.1:8547` as chain `31337`. With the old wallet,
      execute five cards: deploy the two-wallet helper; reclaim and transfer
      ArchController ownership; start both SphereX admin transfers. Export the
      phase-1 run-state above.
- [ ] Stop the preview, prepare phase 2, then restart the same preview command:

```bash
stage phase-2
```

- [ ] With the new wallet, execute three cards: accept ArchController SphereX
      administration; move its operator role to the helper; register the new
      wallet as a Sepolia borrower. Export the phase-2 run-state.
- [ ] Stop the preview and run the delay stage. On Anvil this advances only the
      disposable fork to the exact SphereX eligibility time:

```bash
stage delay
```

- [ ] Prepare phase 3. The Anvil delay adapter has already moved the fork to
      the exact eligibility time:

```bash
stage phase-3
```

- [ ] Restart the preview. With the new wallet, execute three cards: accept
      SphereX engine administration; grant the helper its operator role; revoke
      the old wallet's direct role. Confirm there is no helper deauthorization
      card. Export the phase-3 run-state.
- [ ] Stop the preview, prepare activation, then restart it:

```bash
stage activation
```

- [ ] Confirm 24 cards: 14 deployments, 10 calls, eight forwarded owner
      actions, six template registrations, two factory registrations, and no
      ownership handoff, retirement, or market removal.
- [ ] Execute in order with the new wallet. At a reviewed midpoint, export
      `deployments/anvil/run-state-v2-5-checkpoint.json`, reload, resume, and
      confirm all earlier receipts and predicates are rechecked.
- [ ] Export the final activation run-state, stop the preview, and finalize:

```bash
stage finalize-activation
```

- [ ] Confirm inventory validation, lint, reconciliation, authority preflight,
      and handoff checks pass. Confirm both wallets remain authorized and the
      old wallet no longer has the direct SphereX engine operator role.

Optional: run the standard and revolving canaries on the disposable fork. They
are contract-flow coverage, not wallet-ceremony acceptance or a live gate:

```bash
cast rpc anvil_impersonateAccount \
  0xca7007a75296b532ce1606d9e130eaa849800ca7 \
  --rpc-url "$RPC_URL"
OWNER_MODE=direct DEPLOYMENTS_NETWORK=anvil \
  BORROWER=0xca7007a75296b532ce1606d9e130eaa849800ca7 \
  RPC_URL="$RPC_URL" RELEASE_TAG=v2-5 \
  bash script/deploy/v2-5/09-canary-market.sh
```

## 3. Preserve evidence and stop

- [ ] Record final status before stopping the fork:

```bash
stage status | tee deployments/anvil/status-v2-5.txt
kill "$(cat deployments/anvil/anvil.pid)"
```

- [ ] Archive the unedited evidence and record its digest:

```bash
EVIDENCE_ARCHIVE="v2-5-sepolia-rehearsal-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
COPYFILE_DISABLE=1 tar -czf "$EVIDENCE_ARCHIVE" deployments/anvil
shasum -a 256 "$EVIDENCE_ARCHIVE"
```

- [ ] Preserve the commit, fork block, four plans, packages, digests and
      run-states, delay evidence, checkpoint, transaction hashes, final
      inventory, reconciliation, preflight, handoff, Anvil state, and log.
- [ ] Review the archive for private keys, mnemonics, RPC credentials, and
      bearer tokens before committing it.

## Recovery

Restore a crashed fork without running fresh setup:

```bash
bash script/deploy/v2-5/rehearse.sh --resume
```

Restart the exact saved UI package and select **Resume same Anvil fork**. Do not
regenerate a completed or partially executed phase.

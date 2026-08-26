# v2.5 Sepolia first-deployment checklist

Run the accepted rehearsal sequence against live Sepolia: three authority
packages, the SphereX delay, then one 24-card activation package. Every
transaction is signed through the locked deployment UI.

Retirement is a later ceremony after the validation window. Do not run live
canaries as part of activation.

## Fixed inputs

| Item           | Expected value                               |
| -------------- | -------------------------------------------- |
| Network        | Sepolia `11155111`                           |
| Old executor   | `0xca732651410E915090d7A7D889A1E44eF4575fcE` |
| New executor   | `0xca7007a75296b532ce1606d9e130eaa849800ca7` |
| ArchController | `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f` |
| Legacy helper  | `0xa476920af80B587f696734430227869795E2Ea78` |
| SphereX engine | `0xCc65C2Ad8ab5b5c63489cfC77F782175E0c6A36e` |
| Activation     | 24 cards: 14 deployments and 10 calls        |

The replacement helper must keep both wallets authorized. Phase 3 removes only
the old wallet's direct SphereX engine operator role.

## Stop conditions

Stop on source drift, a dirty starting worktree, an unfunded wallet, the wrong
RPC, chain or wallet, a changed package digest, unexpected card count, failed
transaction, red predicate, or failed verification. Preserve the exact plan,
package, browser state, run-state, transaction hash, and error before
diagnosing. Never edit evidence, skip a card, or generate a later phase from
unverified state.

Phase 1 cards 2 and 3 are one ownership handoff. If interrupted after reclaim,
resume the same reviewed package and complete the transfer before stopping.

For every package: stop the preview, run the next stage, restart the preview,
confirm chain `11155111`, wallet, digest, fingerprint, and card count, execute
in order, wait for every receipt and predicate, then export the run-state
unchanged.

## 1. Prepare

- [ ] Complete and accept a new real-wallet rehearsal using the shared stage
      interface.
- [ ] From the `v2-protocol` repository root, set the live target:

```bash
cd "$(git rev-parse --show-toplevel)"

export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RPC_URL='<reviewed Sepolia RPC URL>'
export PRODUCTION_SOLIDITY_BASELINE=49f891c93768f9986f985204c2f533c77c5e6f60
export DEPLOYMENT_COMMIT="$(git rev-parse HEAD)"

stage() {
  bash script/deploy/v2-5/ceremony-stage.sh "$@"
}
```

- [ ] Confirm a clean, pushed source with unchanged production Solidity and the
      live RPC:

```bash
git branch --show-current
printf 'deployment commit: %s\n' "$DEPLOYMENT_COMMIT"
git rev-parse '@{upstream}'
git status --short
git diff --stat "$PRODUCTION_SOLIDITY_BASELINE" -- src
cast chain-id --rpc-url "$RPC_URL"
```

Continue only if the deployment and upstream commits match, status and the diff
print nothing, and the chain ID is `11155111`.

- [ ] Run the same cold gates used for rehearsal:

```bash
forge test
forge build --sizes src script/common script/deploy/v2-5

(
  cd deploy-ui
  npm ci
  npm audit
  npm test
  npm run build
  SEPOLIA_RPC_URL="$RPC_URL" npm run test:fork
)
```

## 2. Execute the shared sequence

| Stage                 | Wallet | Cards | Output                                                        |
| --------------------- | ------ | ----: | ------------------------------------------------------------- |
| `phase-1`             | old    |     5 | `deployments/sepolia/run-state-authority-helper-phase-1.json` |
| `phase-2`             | new    |     3 | `deployments/sepolia/run-state-authority-helper-phase-2.json` |
| `delay`               | none   |     0 | `deployments/sepolia/authority-delay-v2-5.json`               |
| `phase-3`             | new    |     3 | `deployments/sepolia/run-state-authority-helper-phase-3.json` |
| `activation`          | new    |    24 | `deployments/sepolia/run-state-v2-5.json`                     |
| `finalize-activation` | none   |     0 | inventory, reconciliation, preflight, and handoff             |
| `status`              | none   |     0 | `deployments/sepolia/status-v2-5.txt`                         |

- [ ] Prepare phase 1. This also checks the complete live authority baseline,
      wallet balances, chain, inventory identity, and package shape:

```bash
stage phase-1
```

- [ ] In a second terminal, serve the exact build:

```bash
(cd deploy-ui && npm exec -- vite preview --host 127.0.0.1 --port 4173 --strictPort)
```

- [ ] With the old wallet, execute five cards: deploy the two-wallet helper;
      reclaim and transfer ArchController ownership; start both SphereX admin
      transfers. Export the phase-1 run-state above.
- [ ] Stop the preview, prepare phase 2, then restart the same preview command:

```bash
stage phase-2
```

- [ ] Confirm the reviewed replacement-helper runtime hash and both wallet
      authorizations pass. With the new wallet, execute three cards: accept
      ArchController SphereX administration; move its operator role to the
      helper; register the new wallet as a Sepolia borrower. Export phase 2.
- [ ] Stop the preview and record the live SphereX schedule:

```bash
stage delay
```

- [ ] Wait until the printed UTC eligibility time. Do not advance, mine, or
      otherwise mutate Sepolia. Prepare phase 3; it will refuse to continue
      early and will add the ready block and timestamp to the delay evidence:

```bash
stage phase-3
```

- [ ] Restart the preview. With the new wallet, execute three cards: accept
      SphereX engine administration; grant the helper its operator role; revoke
      the old wallet's direct role. Confirm there is no helper deauthorization
      card. Export phase 3.
- [ ] Stop the preview, prepare activation, then restart it:

```bash
stage activation
```

- [ ] Confirm 24 cards: 14 deployments, 10 calls, eight forwarded owner
      actions, six template registrations, two factory registrations, and no
      ownership handoff, retirement, or market removal.
- [ ] Execute in order with the new wallet. At a reviewed midpoint, export
      `deployments/sepolia/run-state-v2-5-checkpoint.json`, reload, resume, and
      confirm all earlier receipts and predicates are rechecked.
- [ ] Export the final activation run-state, stop the preview, and finalize:

```bash
stage finalize-activation
stage status | tee deployments/sepolia/status-v2-5.txt
```

- [ ] Confirm inventory validation, lint, reconciliation, authority preflight,
      and handoff checks pass. Confirm both wallets remain authorized and the
      old wallet no longer has the direct SphereX engine operator role.

## 3. Preserve evidence

- [ ] Verify the replacement helper and all 14 activation deployments on the
      explorer, preserving their compiler inputs.
- [ ] Archive the unedited evidence and record its digest:

```bash
printf '%s\n' "$DEPLOYMENT_COMMIT" > deployments/sepolia/source-commit-v2-5.txt
EVIDENCE_DIR="${EVIDENCE_DIR:?set EVIDENCE_DIR to a durable path outside this repository}"
mkdir -p "$EVIDENCE_DIR"
EVIDENCE_ARCHIVE="$EVIDENCE_DIR/v2-5-sepolia-live-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
COPYFILE_DISABLE=1 tar -czf "$EVIDENCE_ARCHIVE" deployments/sepolia
shasum -a 256 "$EVIDENCE_ARCHIVE"
```

- [ ] Preserve the commit; four plans, packages, digests and unedited
      run-states; delay evidence; checkpoint; transaction hashes; replacement
      helper and code hash; final inventory; reconciliation; preflight;
      handoff; and explorer compiler inputs.
- [ ] Review the evidence for private keys, mnemonics, RPC credentials, and
      bearer tokens before retaining it. Do not commit ceremony archives to
      the protocol repository; promote selected evidence to the reviewed
      release evidence store.
- [ ] Validate the new generation through the subgraph, SDK, and app while the
      old factories remain live. Stop the preview. Do not generate retirement.

## Recovery

After an interruption, restart the exact saved package and resume from browser
progress or the exported run-state. Require all earlier receipts and predicates
to recheck. Do not rerun a stage to regenerate a completed or partially
executed package.

After a failure, preserve the evidence and stop. Do not edit the plan, retry
from a new package, or continue into a later phase without separate review.

## Later: retirement

Retirement gets its own plan, package, run-state, review, and ceremony after the
validation window. Generate it from the finalized live inventory. Removing the
old wallet from the replacement helper is later still.

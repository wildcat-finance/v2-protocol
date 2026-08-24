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
      interface. Fill in its commit, archive, and digest below before proceeding.
- [ ] From the `v2-protocol` repository root, set the live target:

```bash
cd "$(git rev-parse --show-toplevel)"

export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=sepolia
export RPC_URL='<reviewed Sepolia RPC URL>'
export PRODUCTION_SOLIDITY_BASELINE=49f891c93768f9986f985204c2f533c77c5e6f60
export REHEARSED_COMMIT='<accepted shared-flow rehearsal commit>'
export REHEARSAL_ARCHIVE='<accepted rehearsal archive path>'
export REHEARSAL_ARCHIVE_SHA256='<accepted rehearsal archive sha256>'
export DEPLOYMENT_COMMIT="$(git rev-parse HEAD)"

stage() {
  bash script/deploy/v2-5/ceremony-stage.sh "$@"
}
```

- [ ] Require a clean, pushed descendant with unchanged production and
      ceremony tooling, then verify the rehearsal archive:

```bash
check_live_source() (
  set -euo pipefail

  case "$REHEARSED_COMMIT$REHEARSAL_ARCHIVE$REHEARSAL_ARCHIVE_SHA256" in
    *'<'*)
      echo 'live preflight failed: fill the accepted rehearsal values first' >&2
      return 1
      ;;
  esac
  if ! upstream_commit="$(git rev-parse '@{upstream}' 2>/dev/null)"; then
    echo 'live preflight failed: this branch has no upstream' >&2
    return 1
  fi

  git branch --show-current
  printf 'deployment commit: %s\n' "$DEPLOYMENT_COMMIT"
  if [[ "$DEPLOYMENT_COMMIT" != "$upstream_commit" ]]; then
    echo "live preflight failed: upstream is $upstream_commit" >&2
    return 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo 'live preflight failed: worktree is dirty' >&2
    git status --short >&2
    return 1
  fi
  if ! git merge-base --is-ancestor "$REHEARSED_COMMIT" "$DEPLOYMENT_COMMIT"; then
    echo 'live preflight failed: rehearsal commit is not an ancestor' >&2
    return 1
  fi
  if ! git diff --quiet "$REHEARSED_COMMIT"..HEAD -- \
    src script scripts deploy-ui foundry.toml package.json yarn.lock \
    deployments/sepolia/ceremony-config.json \
    deployments/sepolia/deployments.json \
    deployments/sepolia/factory-inventory.json; then
    echo 'live preflight failed: deployment-affecting files changed after rehearsal' >&2
    return 1
  fi
  if ! git diff --quiet "$PRODUCTION_SOLIDITY_BASELINE" -- src; then
    echo 'live preflight failed: production Solidity differs from the baseline' >&2
    return 1
  fi

  archive_sha256="$(shasum -a 256 "$REHEARSAL_ARCHIVE" | awk '{print $1}')"
  if [[ "$archive_sha256" != "$REHEARSAL_ARCHIVE_SHA256" ]]; then
    echo "live preflight failed: rehearsal archive digest is $archive_sha256" >&2
    return 1
  fi
  chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
  if [[ "$chain_id" != '11155111' ]]; then
    echo "live preflight failed: RPC chain ID is $chain_id" >&2
    return 1
  fi

  echo 'live preflight: GREEN'
)
check_live_source
```

- [ ] Run the same cold gates used for rehearsal:

```bash
(
  set -euo pipefail

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
EVIDENCE_ARCHIVE="v2-5-sepolia-live-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
COPYFILE_DISABLE=1 tar -czf "$EVIDENCE_ARCHIVE" deployments/sepolia
shasum -a 256 "$EVIDENCE_ARCHIVE"
```

- [ ] Preserve the commit; four plans, packages, digests and unedited
      run-states; delay evidence; checkpoint; transaction hashes; replacement
      helper and code hash; final inventory; reconciliation; preflight;
      handoff; and explorer compiler inputs.
- [ ] Review the evidence for private keys, mnemonics, RPC credentials, and
      bearer tokens before committing it.
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

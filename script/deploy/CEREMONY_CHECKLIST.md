# Sepolia activation ceremony checklist

Use this checklist for fixed-authority Sepolia activations. The release runbook
supplies the deployment scope, config file and expected changes.
[Release runbooks](../../docs/operations/deployment.md)

## 1. Set the release

Run this in `v2-protocol`. It sets the config file for this terminal and prints
the release name.

```sh
export SEPOLIA_REPLACEMENT_CONFIG="deployments/sepolia/v$(jq -er '.version' package.json).json"
jq -er '.release' "$SEPOLIA_REPLACEMENT_CONFIG"
```

If you already ran the `export` command in the release runbook, start at step 2.

## 2. Run the checks

Use the same terminal for the rest of the ceremony. If the signing wallet is
on another machine, set `CEREMONY_HOST` to the build machine's trusted LAN
address before starting the fork.

```sh
export FORK_RPC_URL=https://rpc.hinterlight.net/11155111
export DEPLOYMENTS_NETWORK=anvil
unset RPC_URL RUN_STATE

stage() {
  SEPOLIA_REPLACEMENT_CONFIG="${SEPOLIA_REPLACEMENT_CONFIG:?run step 1 in this terminal}" \
    bash script/deploy/v2-5/sepolia-fix-1-stage.sh "$@"
}

rehearse() {
  SEPOLIA_REPLACEMENT_CONFIG="${SEPOLIA_REPLACEMENT_CONFIG:?run step 1 in this terminal}" \
    bash script/deploy/v2-5/rehearse-sepolia-fix-1.sh "$@"
}

stage check
```

Wait for `Cold gates GREEN` before starting the fork. The checks use your
local files. Unused library checkouts and unrelated edits can stay in place.

## 3. Rehearse with the signing wallet

```sh
rehearse --ui
stage activation
```

- [ ] In a second terminal, run the preview command printed by `stage activation`.
  Open the printed UI URL and connect the expected executor to the printed Anvil
  RPC on chain `31337`. The fork source URL above is for the build machine.
- [ ] Match the UI to the stage's `READY` output for this rehearsal. Check the
  release label, chain, executor, card count, digest and fingerprint. The fork
  and live packages each have their own digest.
- [ ] Sign the cards in order and wait for each receipt and predicate to turn
  green. Click **Export run state** after the last card. If the browser is on
  another machine, copy its export unchanged to the build machine.
- [ ] Run the following commands after the export. If the build machine's
  Downloads folder has no unique new export, pass the export's path in
  `RUN_STATE` for `stage finalize-activation`. Wait for
  `Real-wallet Anvil rehearsal ACCEPTED` before stopping the fork.

```sh
stage finalize-activation
stage status
rehearse --stop
```

The automated `rehearse --full` exercises the transactions on a disposable fork.
The real-wallet export supplies the acceptance record for live signing.

## 4. Execute on Sepolia

Use the packet you just rehearsed. If the packet or signing UI changes, repeat
the rehearsal before signing on Sepolia.

- [ ] Stop the rehearsal preview. In the setup shell, select the live network
  and clear any saved rehearsal export path.

```sh
export DEPLOYMENTS_NETWORK=sepolia
export RPC_URL="$FORK_RPC_URL"
unset RUN_STATE
stage activation
```

- [ ] Start the newly printed preview command. Connect the expected executor
  to Sepolia `11155111`. Match the live release, card count, digest and
  fingerprint to the live `READY` output and the reviewed packet.
- [ ] Sign the live cards in order. Verify each receipt and predicate, then
  export the live run state. Use this export for finalization.

```sh
stage finalize-activation
stage status
stage finalize-inventory
```

## 5. Retain evidence and hand off

- [ ] Find the run state and handoff for your release in `deployments/sepolia/`.
  Factory activations write a `handoff-*.json` file and its Markdown companion.
  Template-only activations write a `template-update-*.json` file. Use the
  release runbook for the expected inventory and downstream checks.
- [ ] Commit the finalized deployment records, evidence ZIP and its `.sha256`
  file. The ZIP is under `deployments/sepolia/ceremony-evidence/`.
  Keep the signing session and exports until the handoff is verified.

If finalization succeeded and archiving failed, retry `stage archive-evidence`
on the machine holding the session. Set `CEREMONY_EVIDENCE_DIR` to the
repository-relative session directory if its pointer is unavailable.

## Recovery

If a wallet, chain, digest or card count differs from the stage output, stop
before signing. If a transaction or predicate fails, retain the run state and
session directory for diagnosis. To resume after a browser or preview interruption,
restart the printed preview command for the same session.

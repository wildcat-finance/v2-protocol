# V2.5.4 Sepolia replacement ceremony

The reviewed scope and source pin are in the
[V2.5.4 runbook](../../docs/operations/sepolia-v2-5-4.md).
The completed V2.5.3 fix-1 packet remains historical evidence.

Run the fixed-authority factory replacement twice:

1. Through the real-wallet locked UI on a pinned Sepolia fork.
2. Through the same stage interface on live Sepolia.

The stage script derives, validates, prints, and retains the run identity. Do
not create a manual run sheet.

This ceremony has 22 cards:

- 12 contract deployments.
- 10 activation calls.

It does not rotate authority or retire predecessor factories.

## Fixed inputs

- Live network: Sepolia `11155111`.
- Rehearsal network: Anvil `31337`, pinned from Sepolia.
- Executor: `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`.
- Activation: 22 cards, consisting of 12 deployments and 10 calls.
- Authority: Existing helper and SphereX roles remain fixed.

Before connecting the wallet, match the locked UI against the stage output:

- Source commit and protocol version.
- Executor and card count.
- Full package digest and short fingerprint.

## Stop conditions

Stop if any of these occur:

- The source tree is dirty or unpushed.
- A cold gate or verification fails.
- The chain, wallet, digest, or card count is wrong.
- A transaction fails or a predicate turns red.

Export the run-state and preserve the session directory before diagnosing. Do
not edit evidence, skip a card, or repair a live package in place.

## 1. Prepare

- [ ] From the `v2-protocol` root, define the helpers used below:

```sh
cd "$(git rev-parse --show-toplevel)"

export FORK_RPC_URL='https://eth-sep.hinterlight.net'
export DEPLOYMENTS_NETWORK=anvil
unset RPC_URL

stage() {
  bash script/deploy/v2-5/sepolia-v2-5-4-stage.sh "$@"
}

rehearse() {
  FORK_RPC_URL="$FORK_RPC_URL" \
    bash script/deploy/v2-5/rehearse-sepolia-v2-5-4.sh "$@"
}
```

- [ ] Run the source, deploy-profile, dependency, UI, and fork gates:

```sh
stage check
```

Continue only after it prints `Cold gates GREEN` for the pushed `HEAD`.

## 2. Real-wallet Anvil rehearsal

- [ ] Start a fresh pinned fork, then prepare the locked rehearsal UI:

```sh
rehearse --ui
stage activation
```

These commands:

- Select the fork block.
- Validate the target state.
- Derive the chain-31337 plan from the reviewed Sepolia plan.
- Build the locked UI.
- Print the complete run identity.

The rehearsal transform is mechanical. Only the network, chain ID, release
label, and transaction-envelope chain IDs differ from the live plan.

- [ ] In a second terminal, serve the exact build:

```sh
(cd deploy-ui && npm exec -- vite preview \
  --host 127.0.0.1 --port 4173 --strictPort)
```

- [ ] Open `http://127.0.0.1:4173`.
- [ ] Connect the expected executor to local RPC `http://127.0.0.1:8548`, chain
      `31337`.
- [ ] Confirm the digest, fingerprint, executor, and 22-card count.
- [ ] Execute all 22 cards in order. Wait for every receipt and green predicate,
      then click **Export run state**.
- [ ] Verify and accept the browser export, print status, then stop only the
      recorded Anvil process:

```sh
stage finalize-activation
stage status
rehearse --stop
```

`finalize-activation`:

1. Finds the new browser export in `~/Downloads`.
2. Copies it unchanged into the ignored rehearsal evidence directory.
3. Verifies every receipt and postcondition.
4. Writes the acceptance record required by the live stage.

If the browser saved more than one candidate, set `RUN_STATE` to the correct
file and rerun the command.

## 3. Live Sepolia activation

- [ ] Stop the rehearsal preview. Select live Sepolia and prepare the locked UI:

```sh
export DEPLOYMENTS_NETWORK=sepolia
unset RPC_URL
stage activation
```

The stage refuses to proceed unless the cold gates match the current pushed
source.

An accepted real-wallet rehearsal may come from an earlier commit only when all
of these remain unchanged:

- Tracked configuration and plan.
- Protocol version.
- The complete `deploy-ui` tree.
- Live package digest.

The stage reruns live preflight immediately before building the UI.

- [ ] Restart the same preview command from section 2.
- [ ] Open `http://127.0.0.1:4173` and connect the expected executor to Sepolia.
- [ ] Confirm chain `11155111`, digest, fingerprint, executor, and 22-card
      count.
- [ ] Execute all 22 cards in order. Wait for every receipt and green predicate,
      then click **Export run state**.
- [ ] Verify the export and print final status:

```sh
stage finalize-activation
stage status
```

- [ ] Finalize the append-only inventory and generate the downstream handoff:

```sh
stage finalize-inventory
```

The ignored `deployments/sepolia/ceremony-evidence/` session directory retains:

- Verified run-state.
- Preflight and post-activation reports.
- Package identity.
- Operator evidence.

The stage also copies the verified run-state to
`deployments/sepolia/run-state-v2-5-4.json` for inventory and
downstream handoff work.

`finalize-inventory` sends no transactions. It:

- Appends the replacement factory generations.
- Updates canonical deployment aliases.
- Writes the release handoff.
- Reconciles those records against Sepolia.

The predecessor factories remain registered and indexed.

Stop the preview after verification. Do not retire either predecessor factory
in this ceremony.

## Recovery

If the preview or browser closes, restart the exact preview against the same
recorded Anvil or live session. The UI rechecks saved receipts and predicates.
Do not rerun `stage activation` for a partially executed package.

After a failure, preserve the session directory and stop. A corrected package
needs a new rehearsal and acceptance record before live execution.

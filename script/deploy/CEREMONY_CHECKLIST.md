# V2.5.3 Sepolia replacement ceremony

Run the fixed-authority factory replacement first through the real-wallet
locked UI on a pinned Sepolia fork, then through the same stage interface on
live Sepolia. The stage script derives, validates, prints, and retains the run
identity. No manual run sheet is required.

This ceremony deploys 12 contracts and executes 10 activation calls. It does
not rotate authority or retire the predecessor factories.

## Fixed inputs

| Item              | Expected value                                 |
| ----------------- | ---------------------------------------------- |
| Live network      | Sepolia `11155111`                             |
| Rehearsal network | Anvil `31337`, pinned from Sepolia             |
| Executor          | `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`   |
| Activation        | 22 cards: 12 deployments and 10 calls          |
| Authority         | Existing helper and SphereX roles remain fixed |

The stage output prints the source commit, protocol version, executor, card
count, full package digest, and short fingerprint. Compare that output with the
locked UI before connecting the wallet.

## Stop conditions

Stop on a dirty or unpushed source tree, failed cold gate, wrong chain or
wallet, changed digest, unexpected card count, failed transaction, red
predicate, or failed verification. Export the run-state and preserve the
session directory before diagnosing. Never edit evidence, skip a card, or
repair a live package in place.

## 1. Prepare

- [ ] From the `v2-protocol` root, define the two commands used below:

```sh
cd "$(git rev-parse --show-toplevel)"

export FORK_RPC_URL='https://eth-sep.hinterlight.net'
export DEPLOYMENTS_NETWORK=anvil
unset RPC_URL

stage() {
  bash script/deploy/v2-5/sepolia-fix-1-stage.sh "$@"
}

rehearse() {
  FORK_RPC_URL="$FORK_RPC_URL" \
    bash script/deploy/v2-5/rehearse-sepolia-fix-1.sh "$@"
}
```

- [ ] Run the complete source, deploy-profile, dependency, UI, and fork gates:

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

The commands select the fork block, validate the target state, derive the
chain-31337 rehearsal plan from the reviewed Sepolia plan, build the locked UI,
and print the complete run identity. The rehearsal transform is mechanical:
only the network, chain ID, release label, and transaction envelope chain IDs
differ from the live plan.

- [ ] In a second terminal, serve the exact build:

```sh
(cd deploy-ui && npm exec -- vite preview \
  --host 127.0.0.1 --port 4173 --strictPort)
```

- [ ] Open `http://127.0.0.1:4173`. Connect the expected executor to local RPC
      `http://127.0.0.1:8548`, chain `31337`. Confirm the printed digest,
      fingerprint, executor, and 22-card count.
- [ ] Execute all 22 cards in order. Wait for every receipt and green predicate,
      then click **Export run state**.
- [ ] Verify and accept the browser export, print status, then stop only the
      recorded Anvil process:

```sh
stage finalize-activation
stage status
rehearse --stop
```

`finalize-activation` finds the new browser export in `~/Downloads`, copies it
unchanged into the ignored rehearsal evidence directory, verifies every receipt
and postcondition, and writes the acceptance record required by the live stage.
If the browser saved more than one candidate, set `RUN_STATE` to the intended
file and rerun the command.

## 3. Live Sepolia activation

- [ ] Stop the rehearsal preview. Select live Sepolia and prepare the locked UI:

```sh
export DEPLOYMENTS_NETWORK=sepolia
unset RPC_URL
stage activation
```

The stage refuses to proceed unless the cold gates and accepted real-wallet
rehearsal match the current pushed source, reviewed live plan, and live package
digest. It reruns the live preflight immediately before building the UI.

- [ ] Restart the same preview command from section 2.
- [ ] Open `http://127.0.0.1:4173`. Connect the expected executor to Sepolia.
      Confirm chain `11155111` and the printed digest, fingerprint, executor,
      and 22-card count.
- [ ] Execute all 22 cards in order. Wait for every receipt and green predicate,
      then click **Export run state**.
- [ ] Verify the export and print final status:

```sh
stage finalize-activation
stage status
```

The verified run-state, preflight, post-activation report, package identity, and
operator evidence remain under the ignored
`deployments/sepolia/ceremony-evidence/` session directory. The verified
run-state is also copied to
`deployments/sepolia/run-state-v2-5-sepolia-fix-1.json` for final inventory and
downstream handoff work.

Stop the preview after verification. Do not retire either predecessor factory
in this ceremony.

## Recovery

If the preview or browser closes, restart the exact preview against the same
recorded Anvil or live session. The UI rechecks saved receipts and predicates
before continuing. Do not rerun `stage activation` for a partially executed
package.

After a failure, preserve the session directory and stop. Any corrected package
gets a new rehearsal and acceptance record before live execution.

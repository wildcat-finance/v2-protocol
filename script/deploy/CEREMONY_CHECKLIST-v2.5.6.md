# V2.5.6 Sepolia activation ceremony

Run the fixed-authority v2.5.6 activation twice:

1. Through the real-wallet locked UI on a pinned Sepolia fork.
2. Through the same stage interface on live Sepolia.

The stage script derives, validates, prints, and retains the run identity. Do
not create a manual run sheet.

Scope and preparation status live in the
[v2.5.6 runbook](../../docs/operations/sepolia-v2.5.6.md). This ceremony has 15 cards:

- 3 hook-template storage deployments.
- 6 template registrations and 6 old-template disables.

This ceremony reuses the existing factories, market stores, lenses, wrapper,
identity registry, and AccessList role-provider factory.

It disables only the three v2.5.5 templates on each current factory, after all
new templates are registered. Disabling cannot be undone and stops new hook
instances; existing instances remain usable on-chain. Authority rotation and
factory deregistration are separate ceremonies.

## Fixed inputs

- Live network: Sepolia `11155111`.
- Rehearsal network: Anvil `31337`, pinned from Sepolia.
- Executor: `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`.
- Activation: 15 cards, consisting of 3 deployments and 12 calls.
- Authority: Existing helper and SphereX roles remain fixed.

Before connecting the wallet, match the locked UI against the stage output:

- Source commit and protocol version.
- Executor and card count.
- Full package digest and short fingerprint.

## Stop conditions

Stop if any of these occur:

- Tracked files or submodules are dirty, build/ceremony inputs are untracked,
  or the source commit is unpushed.
- A cold gate or verification fails.
- The chain, wallet, digest, or card count is wrong.
- A transaction fails or a predicate turns red.

Untracked notes and machine-local files outside build/ceremony input paths do
not block the source gate. The [runbook](../../docs/operations/sepolia-v2.5.6.md#prepare-the-packet)
lists the protected paths.

Export the run-state and preserve the session directory before diagnosing. Do
not edit evidence, skip a card, or repair a live package in place.

## 1. Prepare

- [ ] Use the pinned [JavaScript toolchain](../../CONTRIBUTING.md#javascript-toolchain).
      The cold gate installs both dependency trees from their lockfiles with
      lifecycle scripts disabled.
- [ ] Have Python 3.9 or newer available as `python3` for the final evidence ZIP.
      No Python packages need to be installed.

- [ ] From the `v2-protocol` root, define the helpers used below:

```sh
cd "$(git rev-parse --show-toplevel)"

export FORK_RPC_URL='https://eth-sep.hinterlight.net'
export DEPLOYMENTS_NETWORK=anvil
unset RPC_URL

stage() {
  bash script/deploy/v2-5/sepolia-v2.5.6-stage.sh "$@"
}

rehearse() {
  FORK_RPC_URL="$FORK_RPC_URL" \
    bash script/deploy/v2-5/rehearse-sepolia-v2.5.6.sh "$@"
}
```

- [ ] If the browser and wallet are on another machine on your trusted LAN,
      set `CEREMONY_HOST` to the build machine's LAN IPv4 address before starting
      the rehearsal. For example, replace this address with your rig's address:

```sh
export CEREMONY_HOST='192.168.1.20'
```

This selects the Anvil bind address, browser RPC URL, and printed UI preview
command. Leave it unset when the browser runs on the build machine. Use the
machine's actual address, not `0.0.0.0`. Keep the setting for the live stage.
Anvil exposes development RPC methods, so use this only on a trusted network.
Choose the address before starting the fork; do not restart an in-progress
rehearsal just to change it.

- [ ] Run the source, deploy-profile, deployment-tooling, dependency, UI, and fork gates:

```sh
stage check
```

Continue only after it prints `Cold gates GREEN` for the pushed `HEAD`.
This checks the deployment tooling and transaction executor, not market behavior.

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

- [ ] In a second terminal on the build machine, run the exact preview command
      printed by `stage activation`. It includes the selected listening address.
- [ ] Open the printed UI URL on the machine holding your wallet.
- [ ] Connect the expected executor to the printed Anvil RPC URL, chain `31337`.
      The defaults are UI `http://127.0.0.1:4173` and RPC `http://127.0.0.1:8548`;
      LAN mode uses `CEREMONY_HOST` in both URLs.
- [ ] Confirm the digest, fingerprint, executor, and 15-card count.
- [ ] Execute all 15 cards in order. Wait for every receipt and green predicate,
      then click **Export run state**.
- [ ] If the browser is on another machine, copy the exported JSON unchanged
      from its Downloads folder to the build machine, outside tracked source
      paths (for example, that machine's Downloads folder). Use the command
      below in place of bare `stage finalize-activation`:

```sh
RUN_STATE='/path/to/copied/run-state.json' stage finalize-activation
```

Use the same transfer step for the live export. Automatic Downloads discovery
only searches the machine running the stage script.

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

- [ ] Start the preview command printed by the live `stage activation`.
- [ ] Open its UI URL and connect the expected executor to Sepolia.
- [ ] Confirm chain `11155111`, digest, fingerprint, executor, and 15-card
      count.
- [ ] Execute all 15 cards in order. Wait for every receipt and green predicate,
      then click **Export run state**.
- [ ] Verify the export and print final status:

```sh
stage finalize-activation
stage status
```

- [ ] Finalize the template aliases and generate the downstream update handoff:

```sh
stage finalize-inventory
```

The `deployments/sepolia/ceremony-evidence/` session directory retains:

- Verified run-state.
- Preflight and post-activation reports.
- Package identity.
- Operator evidence.

The stage also copies the verified run-state to
`deployments/sepolia/run-state-v2.5.6.json` for inventory and
downstream handoff work.

`finalize-inventory` sends no transactions. It:

- Verifies all 15 receipts and the final template state again.
- Records the three versioned template addresses and updates their template aliases.
- Writes `template-update-v2.5.6.json`, referencing the retained v2.5.5 handoff.
- Reconciles the unchanged factory inventory against Sepolia.
- Creates `deployments/sepolia/ceremony-evidence/wildcat-v2.5.6-evidence-<timestamp>.zip` and its
  `.sha256` checksum. The ZIP preserves the session, reviewed plan and package,
  gate records, finalized deployment records and handoff, with a manifest of
  file hashes and the original ceremony source commit.

- [ ] Commit the ZIP, checksum and finalized deployment records for handoff.
      Session evidence can also be committed. The active-session pointer remains
      ignored. New session evidence does not block the source gate; changes to
      already tracked evidence still do.

If finalization succeeded but archiving did not, create the ZIP without
rerunning finalization or contacting an RPC:

```sh
DEPLOYMENTS_NETWORK=sepolia stage archive-evidence
```

This uses the recorded live session. Set `CEREMONY_EVIDENCE_DIR` to its
repository-relative session directory if the pointer is unavailable. Run the
command on the machine holding the evidence. It accepts the finalized working
files without requiring a clean or pushed checkout. New checksum files use the
ZIP's basename. To check one after moving it together with its checksum, run
`shasum -a 256 -c <zip>.sha256` from their directory.

The predecessor factories retain their registrations and existing indexing policy.

- [ ] Before reopening market creation, verify SDK, subgraph, and app routing
      against the retained v2.5.5 handoff. Wait for all six new registrations and
      six disables to be indexed, then confirm the app selects the new templates
      on both configured factories. The local SDK review found older addresses;
      see the [handoff notes](../../docs/operations/sepolia-v2.5.6.md#handoff-and-remaining-work).

Stop the preview after verification. Do not retire either predecessor factory
in this ceremony.

## Recovery

If the preview or browser closes, restart the exact preview against the same
recorded Anvil or live session. The UI rechecks saved receipts and predicates.
Do not rerun `stage activation` for a partially executed package.

After a failure, preserve the session directory and stop. A revised package
needs a new rehearsal and acceptance record before live execution.

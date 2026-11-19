# Sepolia v2.5.9 activation

Start in the `v2-protocol` checkout on `release/v2.5.9`. Use the v2.5.7
Sepolia handoff as the live baseline. The 27 cards deploy 15 contracts and
make 12 registration and approval calls. [v2.5.7 handoff](../../deployments/sepolia/handoff-v2.5.7.md)

- Deploy four market bytecode stores, the standard and revolving hooks factories,
  three hook template stores, the wrapper factory, the lens and its three helpers,
  and one shared `KYCRoleProvider`.
- Register both new factories with the existing `ArchController` as factories
  and controllers. Register the open, fixed and periodic templates on each.
- Approve the new wrapper factory for nuke protection on each new hooks factory.
  Borrowers opt into the KYC provider on their own hooks.

The ceremony reuses the sanctions sentinel, borrower identity registry, access-list
provider factory and legacy wrapper fallback. Existing factory registrations and
indexing continue through evaluation.

## Freeze the packet

Commit the reviewed KYC source. Set `contractSourceCommit` in the release config
to the full commit hash containing that source and set `kycRoleProvider.administrator`
to the chosen Sepolia wallet. The generator checks the compiled KYC runtime against
the hash pinned in the config. [release config](../../deployments/sepolia/v2.5.9.json)

```sh
export SEPOLIA_REPLACEMENT_CONFIG=deployments/sepolia/v2.5.9.json
node scripts/sepolia-v2-5-fix-rotation.js generate
node scripts/sepolia-v2-5-fix-rotation.js validate
node scripts/sepolia-v2-5-fix-rotation.js generate-rehearsal
```

Review and commit the generated plan, pending inventory, impact report, source
pin and packages. Push the reviewed branch and use a clean checkout for the
operator gates.

## Rehearse and execute

```sh
stage() { bash script/deploy/v2-5/sepolia-v2.5.9-stage.sh "$@"; }
rehearse() { bash script/deploy/v2-5/rehearse-sepolia-v2.5.9.sh "$@"; }
export FORK_RPC_URL=https://rpc.hinterlight.net/11155111
stage check
rehearse --ui
DEPLOYMENTS_NETWORK=anvil stage activation
```

Connect the reviewed executor in the locked UI. Verify the network, package
digest and 27-card count. Sign in order and export the verified run state.
Set `RUN_STATE` to the export from that session and accept the rehearsal with
`DEPLOYMENTS_NETWORK=anvil stage finalize-activation`. Stop the fork with
`rehearse --stop`.

For live execution, use the same stages with `DEPLOYMENTS_NETWORK=sepolia`
and `RPC_URL=https://rpc.hinterlight.net/11155111`. Run `stage activation`,
sign the Sepolia package, export its run state and set `RUN_STATE` to that
file. Run `stage finalize-activation` and then `stage finalize-inventory`.
The finalized handoff records the KYC address, deployment transaction, start
block, initial administrator and runtime hash. Use those receipts for the
subgraph, SDK and app evaluation. Retirement is a later operator decision.

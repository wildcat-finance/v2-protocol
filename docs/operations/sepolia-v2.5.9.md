# Sepolia v2.5.9 activation

## Start the rehearsal

Run this from `v2-protocol` in the terminal you will use for the rehearsal.

```sh
export SEPOLIA_REPLACEMENT_CONFIG=deployments/sepolia/v2.5.9.json
jq -er '.release' "$SEPOLIA_REPLACEMENT_CONFIG"
```

The second line should print `v2.5.9`. Continue at **Run the checks** in
the [ceremony checklist](../../script/deploy/CEREMONY_CHECKLIST.md#2-run-the-checks).

Both packages have 27 cards. The rehearsal fingerprint is `BA82-311D-9C8D`
on Anvil. The live fingerprint is `5506-2E28-5155` on Sepolia.
[Live package digest](../../deployments/sepolia/ceremony-v2.5.9-eoa.digest.txt)

## Deployment scope

The 27 cards deploy 15 contracts and make 12 registration and approval calls.
The live baseline is the [v2.5.7 handoff](../../deployments/sepolia/handoff-v2.5.7.md).

- Deploy four market bytecode stores, the standard and revolving hooks factories,
  three hook template stores, the wrapper factory, the lens and its three helpers,
  and one shared `KYCRoleProvider`.
- Register both new factories with the existing `ArchController` as factories
  and controllers. Register the open, fixed and periodic templates on each.
- Approve the new wrapper factory for nuke protection on each new hooks factory.
  Borrowers opt into the KYC provider on their own hooks.

The ceremony reuses the sanctions sentinel, borrower identity registry, access-list
provider factory and legacy wrapper fallback. Existing factory registrations and
indexing continue through evaluation. The Sepolia executor,
`0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`, is the initial KYC administrator.

The finalized handoff records the KYC address, deployment transaction, start
block, initial administrator and runtime hash. Use those receipts for the
subgraph, SDK and app evaluation. Retirement is a later operator decision.

## Rebuild the packet

Use these commands when preparing a new packet. The generator checks the
compiled KYC runtime against the configured hash.
[Release config](../../deployments/sepolia/v2.5.9.json)

```sh
export SEPOLIA_REPLACEMENT_CONFIG=deployments/sepolia/v2.5.9.json
node scripts/sepolia-v2-5-fix-rotation.js generate
node scripts/sepolia-v2-5-fix-rotation.js validate
node scripts/sepolia-v2-5-fix-rotation.js generate-rehearsal
```

When publishing a rebuilt packet, include the reviewed live plan, plan entries,
pending inventory, impact report, source pin, EOA package and digest in the
release commit. For a newly generated live package, use
`git add -f -- deployments/sepolia/ceremony-v2.5.9-eoa.json` to stage the
ignored file. The Anvil package is generated locally.

# Sepolia V2.5.3 fix-1 factory replacement

This ceremony deploys protocol source version `2.5.3`. It replaces the V2.5
contracts affected by the post-release fixes.
It runs only on Ethereum Sepolia (`11155111`).

It does not rotate authority. The existing ArchController owner, authority
helper, helper authorization set, SphereX engine, SphereX admin, and SphereX
operator must remain unchanged.

## Locked boundary

- Contract source: `6dd6d697b2e381a94a33bfae29dc7945e12b14b8`
- Protocol version: `2.5.3` (`package.json`)
- Executor: `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`
- Authority helper: `0x981f1Fb406bD7a8385f9373c08Ab4c832Ed0d508`
- Plan: `deployments/sepolia/plan-v2-5-sepolia-fix-1.json`
- Ceremony digest: `0x429707c55c4f163eddc33beca3e62671598aa2a6396decb8f3f0d7bf134dd14e`
- Call-time fingerprint: `4297-07C5-5C4F`

The plan contains 12 deployments and 10 activation calls. It replaces the
wrapper factory, both market init-code stores and hooks factories, three hook
template stores, and four lens contracts. It reuses the borrower identity
registry and access-list role-provider factory.

The activation plan registers the replacement factories and templates. It does
not remove a factory, controller, market, authorization, or owner.

## Prepare

From the repository root:

```sh
export FOUNDRY_PROFILE=deploy
export RPC_URL='<reviewed Sepolia RPC URL>'

node scripts/sepolia-v2-5-fix-rotation.js generate
node scripts/sepolia-v2-5-fix-rotation.js validate
node scripts/sepolia-v2-5-fix-rotation.js preflight --rpc-url "$RPC_URL"
```

Confirm the generated digest and fingerprint against the locked boundary above.
The preflight must be green and report `authority.policy` as `fixed`, with no
pending ArchController or SphereX admin transfer.

Rehearse the exact plan against a pinned Sepolia fork:

```sh
FORK_RPC_URL="$RPC_URL" \
  bash script/deploy/v2-5/rehearse-sepolia-fix-1.sh
```

The rehearsal must pass all 22 predicates and receipt-provenance checks. Its
post-activation report must show `authorityChanged: false`, both replacement
factories registered, and both predecessor factories still registered.

## Build the executor

```sh
export REPO_ROOT="$(pwd -P)"
export PACKAGE="$REPO_ROOT/deployments/sepolia/ceremony-v2-5-sepolia-fix-1-eoa.json"

(cd deploy-ui && CEREMONY_PACKAGE="$PACKAGE" npm run build)
(cd deploy-ui && npm test)
(cd deploy-ui && npm run test:fork)
```

Serve `deploy-ui/dist/` locally. The embedded build has no file picker or
editable calldata. Confirm chain `11155111`, executor, full digest, and short
fingerprint before connecting the wallet.

## Execute and verify

Run the preflight again immediately before execution. Stop if its authority
snapshot differs from the reviewed baseline or if the executor nonce changes
after the UI displays it.

Execute the 22 cards in order. Stop on any failed predicate. Do not repair,
skip, or replace a card in the live package.

Export the UI run state unchanged as:

```text
deployments/sepolia/run-state-v2-5-sepolia-fix-1.json
```

Then verify receipts, calldata, deployed bindings, template configuration,
lenses, predecessor registrations, and the unchanged authority snapshot:

```sh
node scripts/sepolia-v2-5-fix-rotation.js verify-activation \
  --rpc-url "$RPC_URL" \
  --run-state deployments/sepolia/run-state-v2-5-sepolia-fix-1.json
```

The command must finish green with `authorityChanged: false` and
`retirementExecuted: false`.

## After activation

Do not retire either predecessor in this ceremony. First deploy and exercise
standard and revolving canary markets, publish the replacement addresses to
downstream consumers, and reconcile the append-only deployment inventory.

Factory retirement is a later, separately generated package. It may remove
only the factory and controller registrations for:

- Standard: `0xbFbDaFc91977eE599a61B30D9e75788565Ad6d18`
- Revolving: `0x190B42942fe9492df9CeA441dA5c43309840E93A`

Existing markets remain registered and indexed.

# RCF V2 Deployment Checklist

Status: operator checklist for current `feat/rcf-v2` deployment scripts
Primary scripts:
- `script/deploy/DeployHooksFactoryRevolving.sol`
- `script/deploy/DeployMarketLens.sol`
- `scripts/rcf-template-sync.js`
- `scripts/generate-rcf-handoff.js`
- `scripts/validate-factory-inventory.js`

Use this as the literal execution checklist. The older narrative runbooks remain useful for background and troubleshooting.

## Target Matrix

| Target | `DEPLOYMENTS_NETWORK` | `RPC_URL` | Owner mode | Broadcast expectations |
| --- | --- | --- | --- | --- |
| Sepolia fork | `sepolia` | local Anvil fork of Sepolia | usually `emit` | safe local rehearsal; may write local metadata into `deployments/sepolia` |
| Sepolia | `sepolia` | real Sepolia RPC | usually `emit` | real broadcast; Sepolia helper reclaim/return may be required |
| Mainnet fork | `mainnet` | local Anvil fork of mainnet | usually `emit` or `require-direct` | safe local rehearsal; use local labels and review metadata |
| Mainnet | `mainnet` | real mainnet RPC | `emit` or multisig-controlled flow | real broadcast; do not assume direct owner EOA |

## 0. Preflight

Check branch and local changes:

```bash
cd /Users/kethcode/wildcat/rcf-v2-mono/v2-protocol
git status --short
```

Compile before any rehearsal or broadcast:

```bash
FOUNDRY_PROFILE=ir forge compile
```

Validate existing factory inventory before changing it:

```bash
node scripts/factory-inventory.js validate --network sepolia --chain-id 11155111
node scripts/factory-inventory.js validate --network mainnet --chain-id 1

node scripts/validate-factory-inventory.js --network sepolia
node scripts/validate-factory-inventory.js --network mainnet
```

## 1. Environment

Set common variables:

```bash
export DEPLOYMENTS_NETWORK="sepolia" # or mainnet
export RPC_URL="https://..."
export FOUNDRY_PROFILE="ir"
export DEPLOYMENT_LABEL="$DEPLOYMENTS_NETWORK-$(date +%Y%m%d-%H%M%S)"
export HOOKS_FACTORY_REVOLVING_DEPLOYMENT_LABEL="$DEPLOYMENT_LABEL"
export MARKET_LENS_DEPLOYMENT_LABEL="$DEPLOYMENT_LABEL"
export ARCH_CONTROLLER_OWNER_MODE="emit" # direct | emit | require-direct
export PVT_KEY="0x..."
```

Optional address overrides:

```bash
export ARCH_CONTROLLER="${ARCH_CONTROLLER:-$(jq -r '.WildcatArchController' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
export SANCTIONS_SENTINEL="${SANCTIONS_SENTINEL:-$(jq -r '.WildcatSanctionsSentinel' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
export DEFAULT_HOOKS_FACTORY="${DEFAULT_HOOKS_FACTORY:-$(jq -r '.HooksFactory' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
```

Optional deployment controls:

```bash
# Force a new deployment for the selected label.
# Prefer a new label on real networks; use this mainly for fresh Anvil forks with stale local addresses.
# export OVERRIDE_EXISTING=true

# Hooks factory canonical alias control. Default is true.
# export UPDATE_HOOKS_FACTORY_REVOLVING_CANONICAL_ALIAS=true

# Inventory controls. Defaults are normal deployment-safe values.
# export UPDATE_FACTORY_INVENTORY=true
# export HOOKS_FACTORY_REVOLVING_INVENTORY_LABEL="revolving-$DEPLOYMENT_LABEL"
# export HOOKS_FACTORY_REVOLVING_START_BLOCK="$(cast block-number --rpc-url "$RPC_URL")"
# export HOOKS_FACTORY_REVOLVING_INDEXED=true
```

Rules:
- Use fresh labels for real network deployments.
- Use `OVERRIDE_EXISTING=true` only when you intentionally want a fresh immutable deployment for the current label.
- Keep `UPDATE_FACTORY_INVENTORY=true` for normal real deployments.
- Do not set `HOOKS_FACTORY_REVOLVING_INDEXED=false` on mainnet for any factory that can have live markets or user funds.
- `DEFAULT_HOOKS_FACTORY` should remain the legacy factory unless intentionally testing a lens default-routing change.

## 2. Optional Fork Setup

Start a Sepolia fork:

```bash
anvil --fork-url https://eth-sep.hinterlight.net/ --host 127.0.0.1 --port 8545
```

Start a mainnet fork:

```bash
anvil --fork-url https://eth-main.hinterlight.net/ --host 127.0.0.1 --port 8545
```

Use the local fork from the deploy terminal:

```bash
export RPC_URL="http://127.0.0.1:8545"
```

After restarting Anvil, either use a fresh label or set `OVERRIDE_EXISTING=true`; otherwise the scripts may reuse addresses from `deployments/<network>/deployments.json` that no longer have code on the new fork.

## 3. Deploy HooksFactoryRevolving

Run:

```bash
forge script script/deploy/DeployHooksFactoryRevolving.sol:DeployHooksFactoryRevolving \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Record:

```bash
export HOOKS_FACTORY_REVOLVING="$(jq -r '.HooksFactoryRevolving' deployments/$DEPLOYMENTS_NETWORK/deployments.json)"
echo "$HOOKS_FACTORY_REVOLVING"
```

Expected completed signals:
- `Did deploy WildcatMarketRevolving init code storage`
- `Did deploy HooksFactoryRevolving`
- `Controller factory registered`
- `Controller registered`
- `Did update factory inventory`

If `Did emit pending admin action: true`, continue through the owner-action section before rerunning the same script.

## 4. Owner-Gated Registration

Owner mode behavior:
- `direct`: script attempts `registerControllerFactory(factory)` inline and fails if broadcaster is not the owner.
- `emit`: script writes a pending admin action artifact when owner registration cannot be performed inline.
- `require-direct`: script fails fast unless the broadcaster is the direct owner when owner registration is required.

Pending artifact path:

```text
deployments/<network>/pending-admin-actions/HooksFactoryRevolving-<factory>-register-controller-factory.json
```

### Sepolia Helper Flow

Use this only when the operator key is authorized by the Sepolia helper:

```bash
export HELPER_OPERATOR_KEY="${HELPER_OPERATOR_KEY:-$PVT_KEY}"
export ARCH_CONTROLLER="${ARCH_CONTROLLER:-$(jq -r '.WildcatArchController' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
export HELPER_OWNER="$(cast call "$ARCH_CONTROLLER" "owner()(address)" --rpc-url "$RPC_URL")"
```

Reclaim direct ownership:

```bash
cast send "$HELPER_OWNER" \
  "returnOwnership()" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"
```

Register the factory:

```bash
cast send "$ARCH_CONTROLLER" \
  "registerControllerFactory(address)" \
  "$HOOKS_FACTORY_REVOLVING" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"
```

Rerun the factory script to finalize `registerWithArchController()`:

```bash
forge script script/deploy/DeployHooksFactoryRevolving.sol:DeployHooksFactoryRevolving \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Do not return ownership to the helper until all owner-gated rollout actions are complete, including template sync apply.

### Mainnet Owner Flow

For mainnet, do not assume a deployer EOA is the owner. Use `ARCH_CONTROLLER_OWNER_MODE=emit` to produce the owner action artifact, execute it through the approved owner/multisig process, then rerun the same script to finalize controller registration.

## 5. Sync Hooks Templates

Run this while the operator can perform owner-gated hooks-template administration on the new factory.

Export from legacy:

```bash
node scripts/rcf-template-sync.js export \
  --rpc-url "$RPC_URL" \
  --legacy-factory "${LEGACY_HOOKS_FACTORY:-$(jq -r '.HooksFactory' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}" \
  --network "$DEPLOYMENTS_NETWORK" \
  --output "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json"
```

Apply to revolving:

```bash
node scripts/rcf-template-sync.js apply \
  --rpc-url "$RPC_URL" \
  --target-factory "$HOOKS_FACTORY_REVOLVING" \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json" \
  --private-key "${HELPER_OPERATOR_KEY:-$PVT_KEY}" \
  --report "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-apply-report.json"
```

Verify:

```bash
node scripts/rcf-template-sync.js verify \
  --rpc-url "$RPC_URL" \
  --target-factory "$HOOKS_FACTORY_REVOLVING" \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json" \
  --report "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-verify-report.json"
```

## 6. Restore Sepolia Helper Ownership

Only for the Sepolia helper flow:

```bash
cast send "$ARCH_CONTROLLER" \
  "transferOwnership(address)" \
  "$HELPER_OWNER" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"

cast call "$ARCH_CONTROLLER" "owner()(address)" --rpc-url "$RPC_URL"
```

Skip or delay this only if there is an explicit follow-up owner-gated operation.

## 7. Deploy MarketLens

Run:

```bash
forge script script/deploy/DeployMarketLens.sol:DeployMarketLens \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Record:

```bash
jq '{MarketLens, MarketLensCore, MarketLensAggregator, MarketLensLive}' \
  deployments/$DEPLOYMENTS_NETWORK/deployments.json
```

`MarketLens` remains the canonical data-access address. The core, aggregator, and live contracts are implementation details behind the facade.

## 8. Validate Inventory and Cross-Stack Metadata

Schema-only inventory validation:

```bash
node scripts/factory-inventory.js validate \
  --network "$DEPLOYMENTS_NETWORK" \
  --chain-id "$(cast chain-id --rpc-url "$RPC_URL")"

node scripts/factory-inventory.js summary \
  --network "$DEPLOYMENTS_NETWORK"
```

Cross-stack validation without RPC:

```bash
node scripts/validate-factory-inventory.js --network "$DEPLOYMENTS_NETWORK"
```

Cross-stack validation with live registration checks:

```bash
node scripts/validate-factory-inventory.js \
  --network "$DEPLOYMENTS_NETWORK" \
  --rpc-url "$RPC_URL"
```

This checks:
- `factory-inventory.json` schema and invariants,
- canonical hooks factory aliases in `deployments.json`,
- indexed hooks factories in `../subgraph/networks.json`,
- SDK canonical routing and indexed non-canonical factory recognition,
- live arch-controller registration when `--rpc-url` is supplied.

## 9. Generate Handoff Artifact

For real networks:

```bash
node scripts/generate-rcf-handoff.js \
  --network "$DEPLOYMENTS_NETWORK" \
  --rpc-url "$RPC_URL" \
  --output "deployments/$DEPLOYMENTS_NETWORK/rcf-v2-handoff.json"

node scripts/validate-rcf-handoff.js \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-v2-handoff.json"
```

For Anvil rehearsals, use a separate output:

```bash
node scripts/generate-rcf-handoff.js \
  --network "$DEPLOYMENTS_NETWORK" \
  --chain-id "$(cast chain-id --rpc-url "$RPC_URL")" \
  --rpc-url "$RPC_URL" \
  --output "deployments/$DEPLOYMENTS_NETWORK/rcf-v2-handoff.anvil.json"
```

## 10. Downstream Handoff

Before subgraph deployment:
- update/render `../subgraph/networks.json` from the deployment metadata,
- ensure every `indexed: true` factory is present,
- ensure factories marked `indexed: false` are absent.

Before SDK release:
- update constants for canonical deploy routing,
- update indexed non-canonical factory recognition,
- run SDK build/tests.

Before app preview:
- update SDK version,
- update subgraph endpoint/version,
- run app lint/build/tests.

## Final Checklist

- New factory deployed or reused intentionally.
- New factory registered as controller factory.
- New factory registered as controller.
- Template sync export/apply/verify completed.
- Sepolia helper ownership restored if applicable.
- MarketLens core, aggregator, live, and facade deployed or reused intentionally.
- MarketLens canonical alias updated.
- `deployments/<network>/factory-inventory.json` reflects canonical and indexed factories.
- `node scripts/validate-factory-inventory.js --network "$DEPLOYMENTS_NETWORK"` passes.
- RPC registration validation passes for real/forked target where available.
- Handoff artifact generated and validated.
- Subgraph, SDK, and app downstream updates are ready to proceed.

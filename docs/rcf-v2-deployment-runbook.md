# RCF V2 Phase 1 Deployment Runbook

This runbook covers `P1-S5`:
- deploy `HooksFactoryRevolving`,
- deploy latest `MarketLens`,
- sync hooks templates from legacy factory to revolving factory,
- generate and validate the machine-readable Phase 1 handoff artifact.

## Prerequisites

- Foundry installed.
- Node.js installed.
- `yarn install` run in `v2-protocol` (required for `scripts/rcf-template-sync.js` which uses `ethers`).
- `ffi=true` and `fs_permissions` already enabled in `foundry.toml` (already true in this repo).
- Deployer key must have authority to:
  - call `WildcatArchController.registerControllerFactory(...)` (owner-only),
  - call template admin methods on `HooksFactoryRevolving` (same owner flow).

## Environment variables

Minimum:

```bash
export RPC_URL="https://..."
export DEPLOYMENTS_NETWORK="sepolia"   # or mainnet / local name
export PVT_KEY="0x..."                 # used by forge scripts unless DEPLOYER_PRIVATE_KEY_VAR is set
```

Optional overrides:

```bash
export DEPLOYER_PRIVATE_KEY_VAR="PVT_KEY"   # default: PVT_KEY
export ARCH_CONTROLLER="0x..."              # fallback: deployments/<network>/deployments.json WildcatArchController
export SANCTIONS_SENTINEL="0x..."           # fallback: deployments/<network>/deployments.json WildcatSanctionsSentinel
export DEFAULT_HOOKS_FACTORY="0x..."        # fallback: deployments/<network>/deployments.json HooksFactory
export LEGACY_HOOKS_FACTORY="0x..."         # used by template sync helper
export REVOLVING_HOOKS_FACTORY="0x..."      # used by template sync helper
```

## 1. Deploy HooksFactoryRevolving

This script:
- deploys (or reuses) `WildcatMarketRevolving` init code storage,
- deploys (or reuses) `HooksFactoryRevolving`,
- performs ArchController registration sequence:
  - `registerControllerFactory(factory)`,
  - `factory.registerWithArchController()`.

```bash
forge script script/DeployHooksFactoryRevolving.sol:DeployHooksFactoryRevolving \
  --rpc-url "$RPC_URL" \
  --broadcast
```

To force redeploy existing entries:

```bash
OVERRIDE_EXISTING=true forge script script/DeployHooksFactoryRevolving.sol:DeployHooksFactoryRevolving \
  --rpc-url "$RPC_URL" \
  --broadcast
```

## 2. Deploy latest MarketLens

`DEFAULT_HOOKS_FACTORY` should remain legacy `HooksFactory` for backward-compatible default behavior.

```bash
forge script script/DeployMarketLens.sol:DeployMarketLens \
  --rpc-url "$RPC_URL" \
  --broadcast
```

## 3. Sync hooks templates (export/apply/verify)

### 3.1 Export from legacy factory

```bash
node scripts/rcf-template-sync.js export \
  --rpc-url "$RPC_URL" \
  --legacy-factory "${LEGACY_HOOKS_FACTORY:-$(jq -r '.HooksFactory' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}" \
  --network "$DEPLOYMENTS_NETWORK" \
  --output "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json"
```

### 3.2 Apply to HooksFactoryRevolving

```bash
node scripts/rcf-template-sync.js apply \
  --rpc-url "$RPC_URL" \
  --target-factory "${REVOLVING_HOOKS_FACTORY:-$(jq -r '.HooksFactoryRevolving' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}" \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json" \
  --private-key "$PVT_KEY" \
  --report "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-apply-report.json"
```

Dry-run mode:

```bash
node scripts/rcf-template-sync.js apply \
  --rpc-url "$RPC_URL" \
  --target-factory "${REVOLVING_HOOKS_FACTORY:-$(jq -r '.HooksFactoryRevolving' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}" \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json" \
  --dry-run
```

### 3.3 Verify parity

```bash
node scripts/rcf-template-sync.js verify \
  --rpc-url "$RPC_URL" \
  --target-factory "${REVOLVING_HOOKS_FACTORY:-$(jq -r '.HooksFactoryRevolving' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}" \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-export.json" \
  --report "deployments/$DEPLOYMENTS_NETWORK/rcf-template-sync-verify-report.json"
```

## 4. Generate Phase 1 handoff artifact

Produces a machine-readable artifact with:
- addresses,
- tx hashes,
- chain metadata,
- canonical factory -> market type map,
- ABI/selector notes required downstream.

```bash
node scripts/generate-rcf-handoff.js \
  --network "$DEPLOYMENTS_NETWORK" \
  --rpc-url "$RPC_URL" \
  --output "deployments/$DEPLOYMENTS_NETWORK/rcf-v2-handoff.json"
```

## 5. Validate handoff artifact

Schema file: `docs/rcf-v2-handoff.schema.json`

```bash
node scripts/validate-rcf-handoff.js \
  --input "deployments/$DEPLOYMENTS_NETWORK/rcf-v2-handoff.json"
```

## Expected outputs

- `deployments/<network>/deployments.json` updated with:
  - `HooksFactoryRevolving`,
  - `WildcatMarketRevolving_initCodeStorage`,
  - latest `MarketLens`.
- `deployments/<network>/rcf-template-sync-export.json`
- `deployments/<network>/rcf-template-sync-apply-report.json`
- `deployments/<network>/rcf-template-sync-verify-report.json`
- `deployments/<network>/rcf-v2-handoff.json`

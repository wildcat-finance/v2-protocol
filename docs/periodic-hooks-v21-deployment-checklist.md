# Periodic Hooks V2.1 Deployment Checklist

Status: operator checklist for the additive v2.1 `PeriodicTermHooks` rollout.

Primary script:

- `script/DeployPeriodicTermHooksV21.sol`

This rollout deploys a new `PeriodicTermHooks` init-code storage contract,
registers it on the existing v2.1 `HooksFactory`, and deploys a new
`MarketLens`. It does not deploy a new hooks factory or new market bytecode.

## Target Matrix

| Target | `DEPLOYMENTS_NETWORK` | `RPC_URL` | Registration mode | Notes |
| --- | --- | --- | --- | --- |
| Sepolia fork | `sepolia-anvil` | local Anvil fork | `auto` or `emit` | Safe rehearsal; copy Sepolia inventory into a throwaway folder. |
| Sepolia | `sepolia` | real Sepolia RPC | `auto`, `direct`, or `emit` | Sepolia helper reclaim/return may be required. |
| Mainnet fork | `mainnet-anvil` | local Anvil fork | `auto` or `emit` | Safe rehearsal; copy mainnet inventory into a throwaway folder. |
| Mainnet | `mainnet` | real mainnet RPC | `emit` | Execute owner action through the approved owner process. |

## 0. Preflight

Check branch and local changes:

```bash
cd ~/v2-protocol
git status --short
```

Use the dedicated `deploy` profile for this deployment. It uses IR with optimizer runs set to 200. The repo's high-run `ir` profile can push the current periodic template storage and lens deployment over the EIP-170 code-size limit.

```bash
export FOUNDRY_PROFILE="deploy"
```

Check contract sizes:

```bash
forge build --sizes script/DeployPeriodicTermHooksV21.sol
```

Expected size margins from the Sepolia fork rehearsal:

| Contract | Runtime size |
| --- | ---: |
| `PeriodicTermHooks` | 17,978 bytes |
| `MarketLens` | 20,766 bytes |

Known tooling note: Solar lint still fails on the existing SphereX `locals`
parser issue after compilation. Treat the size table and `Compiler run
successful` as the relevant deployment-script signals until that third-party
lint issue is resolved.

## 1. Environment

Start from the repo template and fill in network-specific values:

```bash
cp .env.example .env
```

Set common variables:

```bash
export DEPLOYMENTS_NETWORK="sepolia" # or mainnet
export RPC_URL="https://..."
export PVT_KEY="0x..."
export PERIODIC_TEMPLATE_REGISTRATION_MODE="auto" # auto | direct | emit | skip
```

Optional address overrides:

```bash
export ARCH_CONTROLLER="${ARCH_CONTROLLER:-$(jq -r '.WildcatArchController' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
export HOOKS_FACTORY="${HOOKS_FACTORY:-$(jq -r '.HooksFactory' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
```

Optional deployment controls:

```bash
# Force a fresh PeriodicTermHooks init-code storage deployment.
# export OVERRIDE_PERIODIC_TEMPLATE=true

# Force a fresh MarketLens deployment.
# export OVERRIDE_MARKET_LENS=true

# Reuse an explicitly supplied MarketLens address.
# export MARKET_LENS="0x..."

# Skip deploying/updating MarketLens and reuse deployments.json.
# export DEPLOY_MARKET_LENS=false
```

Fee defaults are copied from the existing `OpenTermHooks_initCodeStorage`
template. Override only if the deployment owner has explicitly approved a
different fee configuration:

```bash
# export PERIODIC_TEMPLATE_FEE_SOURCE="0x..."
# export PERIODIC_FEE_RECIPIENT="0x..."
# export PERIODIC_ORIGINATION_FEE_ASSET="0x..."
# export PERIODIC_ORIGINATION_FEE_AMOUNT="0"
# export PERIODIC_PROTOCOL_FEE_BIPS="500"
```

## 2. Optional Fork Setup

Start a Sepolia fork:

```bash
anvil --fork-url https://.../ --host 127.0.0.1 --port 8545
```

Use a throwaway deployment inventory for fork rehearsals:

```bash
rm -rf deployments/sepolia-anvil
mkdir -p deployments/sepolia-anvil
cp deployments/sepolia/deployments.json deployments/sepolia-anvil/deployments.json

export DEPLOYMENTS_NETWORK="sepolia-anvil"
export RPC_URL="http://127.0.0.1:8545"
```

For a mainnet fork, use `deployments/mainnet-anvil` copied from
`deployments/mainnet`.

## 3. Deploy Periodic Hooks And Lens

Run:

```bash
forge script script/DeployPeriodicTermHooksV21.sol:DeployPeriodicTermHooksV21 \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --non-interactive
```

Record:

```bash
jq '{PeriodicTermHooks_initCodeStorage, MarketLens, HooksFactory, WildcatArchController}' \
  deployments/$DEPLOYMENTS_NETWORK/deployments.json
```

Expected completed signals when the broadcaster is not the ArchController owner:

- `Did deploy PeriodicTermHooks init-code storage: true`
- `Did deploy MarketLens: true`
- `Template registered: false`
- `Registration action artifact: deployments/<network>/pending-admin-actions/PeriodicTermHooks-add-template.json`

Expected completed signals after the owner action has been executed and the
script has been rerun:

- `Found PeriodicTermHooks at ...`
- `Found MarketLens at ...`
- `Template registered: true`
- `Did deploy PeriodicTermHooks init-code storage: false`
- `Did deploy MarketLens: false`
- `Warning: No transactions to broadcast.`

## 4. Owner-Gated Registration

`HooksFactory.addHooksTemplate(...)` must be called by the current
`WildcatArchController.owner()`.

Check the current owner:

```bash
export ARCH_CONTROLLER="$(jq -r '.WildcatArchController' deployments/$DEPLOYMENTS_NETWORK/deployments.json)"
export ARCH_CONTROLLER_OWNER="$(cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL")"
echo "$ARCH_CONTROLLER_OWNER"
```

Pending artifact path:

```text
deployments/<network>/pending-admin-actions/PeriodicTermHooks-add-template.json
```

The artifact includes:

- `target`: existing `HooksFactory`,
- `data`: encoded `addHooksTemplate(...)` calldata,
- fee settings,
- ArchController owner,
- broadcaster,
- execution status.

### Fork Impersonation Flow

Use this only on an Anvil fork:

```bash
export ACTION="deployments/$DEPLOYMENTS_NETWORK/pending-admin-actions/PeriodicTermHooks-add-template.json"
export OWNER="$(jq -r '.archControllerOwner' "$ACTION")"
export TARGET="$(jq -r '.target' "$ACTION")"
export DATA="$(jq -r '.data' "$ACTION")"

cast rpc anvil_setBalance "$OWNER" 0x3635C9ADC5DEA00000 --rpc-url "$RPC_URL"
cast rpc anvil_impersonateAccount "$OWNER" --rpc-url "$RPC_URL"

cast send "$TARGET" "$DATA" \
  --from "$OWNER" \
  --unlocked \
  --rpc-url "$RPC_URL"
```

This impersonation flow does not transfer ArchController ownership. No ownership
return transaction is needed, but verify ownership remains unchanged:

```bash
cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
```

### Sepolia Helper Flow

Use this only when the operator key is authorized by the Sepolia helper owner
contract.

```bash
export HELPER_OPERATOR_KEY="${HELPER_OPERATOR_KEY:-$PVT_KEY}"
export HELPER_OWNER="$(cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL")"
export HELPER_OPERATOR_ADDRESS="${HELPER_OPERATOR_ADDRESS:-$(cast wallet address --private-key "$HELPER_OPERATOR_KEY")}"

cast call "$HELPER_OWNER" \
  'authorizedAccounts(address)(bool)' \
  "$HELPER_OPERATOR_ADDRESS" \
  --rpc-url "$RPC_URL"
```

Reclaim direct ownership:

```bash
cast send "$HELPER_OWNER" \
  'returnOwnership()' \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"
```

Register `PeriodicTermHooks` using the generated action artifact:

```bash
export ACTION="deployments/$DEPLOYMENTS_NETWORK/pending-admin-actions/PeriodicTermHooks-add-template.json"
export TARGET="$(jq -r '.target' "$ACTION")"
export DATA="$(jq -r '.data' "$ACTION")"

cast send "$TARGET" "$DATA" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"
```

Return ownership to the helper owner before closeout:

```bash
cast send "$ARCH_CONTROLLER" \
  'transferOwnership(address)' \
  "$HELPER_OWNER" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"

cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL"
```

The final owner must match `$HELPER_OWNER`.

The current Sepolia dev burner that is authorized by the helper owner contract is:

```bash
export HELPER_OPERATOR_ADDRESS="0x..."
```

Do not close out a Sepolia deployment while direct ArchController ownership is
still held by the burner/operator address.

### Mainnet Owner Flow

For mainnet, do not assume a deployer EOA is the owner. Use
`PERIODIC_TEMPLATE_REGISTRATION_MODE=emit`, execute the generated owner action
through the approved owner/multisig process, then rerun the script to finalize
the local rollout summary.

## 5. Verify Registration

```bash
export TEMPLATE="$(jq -r '.PeriodicTermHooks_initCodeStorage' deployments/$DEPLOYMENTS_NETWORK/deployments.json)"
export HOOKS_FACTORY="$(jq -r '.HooksFactory' deployments/$DEPLOYMENTS_NETWORK/deployments.json)"

cast call "$HOOKS_FACTORY" \
  'isHooksTemplate(address)(bool)' \
  "$TEMPLATE" \
  --rpc-url "$RPC_URL"

cast call "$HOOKS_FACTORY" \
  'getHooksTemplateDetails(address)((address,uint80,uint16,bool,bool,uint24,address,string))' \
  "$TEMPLATE" \
  --rpc-url "$RPC_URL"
```

Expected Sepolia fork rehearsal result:

- `isHooksTemplate(...) == true`
- `name == "PeriodicTermHooks"`
- `exists == true`
- `enabled == true`
- `protocolFeeBips == 500`

## 6. Rerun Script For Final Artifacts

After owner registration, rerun the deployment script:

```bash
forge script script/DeployPeriodicTermHooksV21.sol:DeployPeriodicTermHooksV21 \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --non-interactive
```

Review:

```bash
jq '.' deployments/$DEPLOYMENTS_NETWORK/periodic-hooks-v21-rollout.json
jq '.' deployments/$DEPLOYMENTS_NETWORK/pending-admin-actions/PeriodicTermHooks-add-template.json
jq '{PeriodicTermHooks_initCodeStorage, PeriodicTermHooks_MarketLens, MarketLens}' \
  deployments/$DEPLOYMENTS_NETWORK/deployments.json
```

The final rollout summary should show:

- `isTemplateRegistered: true`,
- `wasTemplateRegistered: true` on the final rerun,
- `didDeployPeriodicTemplate: false` on the final rerun,
- `didDeployMarketLens: false` on the final rerun.

The final `deployments.json` should include `PeriodicTermHooks_MarketLens`.
That rollout marker lets future reruns reuse the periodic-aware lens instead of
falling back to the pre-periodic canonical lens.

## 7. Final Checklist

- `FOUNDRY_PROFILE=deploy` was used.
- Contract sizes are under EIP-170.
- `PeriodicTermHooks_initCodeStorage` has code on the target chain.
- `MarketLens` has code on the target chain.
- `PeriodicTermHooks_MarketLens` is present in `deployments.json`.
- `MarketLens.archController()` matches `WildcatArchController`.
- `MarketLens.hooksFactory()` matches `HooksFactory`.
- Generated owner-action artifact was reviewed.
- `HooksFactory.isHooksTemplate(PeriodicTermHooks_initCodeStorage)` is true.
- `getHooksTemplateDetails(...).name` is `PeriodicTermHooks`.
- `getHooksTemplateDetails(...).enabled` is true.
- Sepolia helper ownership was returned if the helper reclaim flow was used.
- Final script rerun is idempotent and broadcasts no transactions.
- `periodic-hooks-v21-rollout.json` is saved for handoff.

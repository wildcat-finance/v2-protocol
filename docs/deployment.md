# v2.5 deployment

> This is the v2.5 process document. It supersedes
> `docs/rcf-v2-deployment-checklist.md`; keep the old checklist as historical
> reference.

For the mandatory clean Sepolia-fork rehearsal, use
[`anvil-v2-5-rehearsal.md`](./anvil-v2-5-rehearsal.md). For the first live
Sepolia run, use
[`sepolia-v2-5-first-deployment.md`](./sepolia-v2-5-first-deployment.md).

## 1. Overview

Create a fresh numbered script set for every release. For v2.5, run `script/deploy/v2-5/01` through `09` in order for activation. Generate retirement later from `script/deploy/v2-5/retirement/`, after activation has been finalized and validated. Do not reuse feature-specific deployment scripts.

Use one executor mode per target:

| Network                                  | Executor                                                                            | Owner mode         |
| ---------------------------------------- | ----------------------------------------------------------------------------------- | ------------------ |
| Ethereum mainnet, Plasma mainnet         | Foundation through the disposable deployment frontend, with the team on a live call | `plan`             |
| Sepolia, Plasma testnet, future testnets | Dev EOA, with temporary helper ownership represented in the plan                   | `plan`             |
| Anvil forks                              | Test EOA for the Sepolia-shaped UI rehearsal; impersonated owner for headless/direct maintenance | `plan` or `direct` |

`DeployScriptBase` enforces an explicit `OWNER_MODE` on Ethereum mainnet and
Plasma mainnet. It defaults to `direct` elsewhere. `plan.js` currently maps only
`mainnet`, `sepolia`, and `anvil` to chain IDs; pass a supported name when
assembling a plan. Plasma owner-mode handling exists in Solidity, but plan
assembly has no Plasma chain-ID mapping.

Activation and retirement are separate public-network ceremonies with separate plans, packages, nonces, review sheets, and run-states. Build a fresh disposable frontend from each package. Have the Foundation execute each Safe transaction while the deployment team verifies the chain, executor, nonce, receipt, and predicates on a live call. Treat the plan schema, not the frontend, as the durable interface.

## 2. Inventory model

Use `deployments/<network>/factory-inventory.json` schema `1.1.0` as the factory
history.

- Append records. Never delete or rewrite a generation away.
- Use `canonical` for the generation selected for new deployments, `live` for a
  superseded generation that remains indexed, and `retired` for an excluded
  generation.
- Keep `canonical`, `indexed`, and `registered` coherent with `lifecycle`.
  Canonical hooks factories are indexed and registered. Retired records are not
  indexed.
- Keep exactly one canonical hooks factory per market type and one canonical
  wrapper factory.
- Keep every wrapper generation in `wrapperFactories`. Link the v2.5 facade to
  the previous generation through `v1Factory`; use `null` only for the first
  generation or a chain with no v1 deployment.
- Use dash-form release tags such as `v2-5`. Do not put dots in labels or JSON
  keys.

Treat release-labelled keys in `deployments.json` as deployment history. Treat
plain keys such as `HooksFactory`, `HooksFactoryRevolving`, `MarketLens`, and
`Wildcat4626WrapperFactory` as canonical aliases. Step 08 moves those aliases to
the resolved v2.5 addresses while it appends the inventory records.

Run `reconcile` before and after a rollout. Its registry-backed half enumerates
ArchController controller factories and controllers and requires corresponding
hooks-factory records. Its configuration-backed half checks each wrapper record
for code and the configured `v1Factory()` link. It also checks canonical aliases,
indexed-record code, and recorded start blocks when chain receipts are
available.

Run `lint` to reject dotted or malformed deployment keys, unallowlisted raw
timestamps, invalid addresses, and canonical-alias drift. Use the tools' help for
arguments and defaults:

```bash
node scripts/factory-inventory.js --help
node scripts/plan.js --help
node scripts/generate-handoff.js --help
```

## 3. Full rollout: testnet plan ceremony

### The two flows, and which one to use

- **Generational activation:** Anything that adds factory generations or moves canonical pointers uses the plan pipeline on every network. Generate 01 through 06 with `OWNER_MODE=plan`, assemble with 07, execute the activation plan, finalize with 08, and generate the handoff. `apply-run` requires receipt provenance for every deployment and will not accept an inline broadcast.
- **Generational retirement:** Generate a separate plan from the finalized post-activation inventory. Retirement removes factory authority only after the new generation has passed the agreed validation window. It has its own execution, verification, run-state, and inventory finalization.
- **Component maintenance:** Redeploying a replaceable component such as the lens or a provider between releases can use the scripts' inline `OWNER_MODE=direct` broadcast. This deliberately does not run step 08 because no generation is being finalized. Regenerate the handoff afterward when downstream consumers need the new address.

Do not attempt a generational rollout through the inline path. It writes concrete-address pending records that `factory-inventory.js apply-run` rejects because generational finalization requires plan references and a verified run-state. This is intentional. Receipt-provenance inventory is the point of step 08.

The script headers define these environments:

| Step | Both modes                                                                                                                                  | Inline `direct`                                                                                                | `plan` generation                                         |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| 01   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG` (default `v2-5`), `ARCH_CONTROLLER`, `SANCTIONS_SENTINEL`, `SKIP_EIP1153_CHECK`               | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>` unless Foundry already has a sender  | `OWNER_MODE=plan`, `RPC_URL`, `EXPECTED_EXECUTOR`; no key |
| 02   | Same as 01                                                                                                                                  | Same as 01                                                                                                     | Same as 01                                     |
| 03   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`, `SKIP_EIP1153_CHECK`; 01 first                                            | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>` unless Foundry already has a sender  | `OWNER_MODE=plan`, `RPC_URL`, `EXPECTED_EXECUTOR`; no key |
| 04   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`, `SKIP_EIP1153_CHECK`; inventory v1 wrapper record or explicit empty array | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>` unless Foundry already has a sender  | `OWNER_MODE=plan`, `RPC_URL`, `EXPECTED_EXECUTOR`; no key |
| 05   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`, `TEMPLATE_FEE_SOURCE_FACTORY`, `TEMPLATE_FEE_RECIPIENT`; 01 through 04 first | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>`; broadcaster is ArchController owner | `OWNER_MODE=plan`, `RPC_URL`, `EXPECTED_EXECUTOR`; no key |
| 06   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`; 05 first                                                                  | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>`                                      | `OWNER_MODE=plan`, `RPC_URL`, `EXPECTED_EXECUTOR`; no key |

The inline commands add `--rpc-url "$RPC_URL" --broadcast` to the Forge
invocations below. They deploy and perform owner calls immediately, but stop at
the finalization constraint above.

### Preflight

Set the deployment profile for every Forge and Node step:

```bash
export FOUNDRY_PROFILE=deploy
```

This is mandatory. The default profile can encounter both EIP-170 and `Stack too deep` failures. The `deploy` profile uses via-IR and optimizer runs `200`, produces the exact creation code consumed by the plan, and currently reports `HooksFactoryRevolving` at 17,786 runtime bytes. Do not substitute a different profile after rehearsal.

Set the testnet execution context:

```bash
export DEPLOYMENTS_NETWORK=sepolia
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<sepolia RPC URL>'
export EXPECTED_EXECUTOR='<dev EOA that temporarily owns the ArchController>'
export PVT_KEY_SEPOLIA='<dev EOA private key>'
```

Before generating anything, validate, lint, and reconcile:

```bash
node scripts/factory-inventory.js validate --network "$DEPLOYMENTS_NETWORK"
node scripts/factory-inventory.js lint --network "$DEPLOYMENTS_NETWORK"
node scripts/factory-inventory.js reconcile \
  --network "$DEPLOYMENTS_NETWORK" \
  --rpc-url "$RPC_URL"
```

### 01: 4626 wrapper facade

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG` (default `v2-5`), `ARCH_CONTROLLER`,
and `SKIP_EIP1153_CHECK`. Ensure the network inventory has exactly one v1
wrapper record, or an explicit empty `wrapperFactories` array for a chain with
no v1. No private key is required while generating.

```bash
forge script \
  script/deploy/v2-5/01-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25 \
  --rpc-url "$RPC_URL"
```

### 02: identity, AccessList provider, and standard hooks factory

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG`, `ARCH_CONTROLLER`,
`SANCTIONS_SENTINEL`, `WRAPPER_FACTORY`, and `SKIP_EIP1153_CHECK`. Run 01 first. This step deploys the borrower identity registry and the default AccessList role-provider factory before the standard market init-code storage and hooks factory.

```bash
forge script \
  script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 \
  --rpc-url "$RPC_URL"
```

### 03: revolving hooks factory

Use the same environment as 02. Run 01 and 02 first. The revolving market creation code is split across two `InitCodeStorage` deployments because one EIP-170 payload is too small. The factory reconstructs the exact creation code before CREATE2, so its full init-code hash and predicted market addresses do not change.

```bash
forge script \
  script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 \
  --rpc-url "$RPC_URL"
```

### 04: MarketLens set

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG`, `ARCH_CONTROLLER`, and
`SKIP_EIP1153_CHECK`. Run 02 first.

```bash
forge script \
  script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 \
  --rpc-url "$RPC_URL"
```

### 05: owner actions and templates

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG`, `ARCH_CONTROLLER`,
`TEMPLATE_FEE_SOURCE_FACTORY`, and `TEMPLATE_FEE_RECIPIENT`. The script reads
`deployments/template-fee-parameters.json`. Run 01 through 04 first.

```bash
forge script \
  script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25 \
  --rpc-url "$RPC_URL"
```

### 06: register new factories

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and `EXPECTED_EXECUTOR`. Accept `RELEASE_TAG` and `ARCH_CONTROLLER`. Run 05 first. This step registers both new v2.5 hooks factories in the ArchController. It does not remove authority from a superseded factory and it never removes a market.

```bash
forge script \
  script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25 \
  --rpc-url "$RPC_URL"
```

### 07: assemble and execute activation

Environment for assembly: require `DEPLOYMENTS_NETWORK`; accept `RELEASE_TAG`
(default `v2-5`). The wrapper exports `FOUNDRY_PROFILE=deploy` itself.

```bash
bash script/deploy/v2-5/07-generate-plan.sh
node scripts/plan.js execute \
  --plan "deployments/$DEPLOYMENTS_NETWORK/plan-$RELEASE_TAG.json" \
  --rpc "$RPC_URL" \
  --private-key "$PVT_KEY_SEPOLIA"
```

Review the summary before execution. Activation has 25 cards on mainnet: 15 deployments and 10 calls. Sepolia's ceremony config adds an ownership reclaim and return, producing 27 cards. The plan must contain six template registrations, two new factory registrations, and no `removeControllerFactory`, `removeController`, or `removeMarket` call. `execute` writes `deployments/<network>/run-state-v2-5.json` after receipts and predicates.

### 08: finalize activation inventory

Environment: require `DEPLOYMENTS_NETWORK` and `RUN_STATE`; accept `RPC_URL`.
The wrapper exports `FOUNDRY_PROFILE=deploy` itself. It rejects any missing,
unknown, non-verified, or malformed run-state entry; appends exactly two hooks factories and one wrapper factory; moves canonical aliases; records the identity registry, AccessList factory, lens, template storage, and revolving two-part init-code storage addresses; leaves superseded factories registered; then reconciles.

```bash
export RUN_STATE="deployments/$DEPLOYMENTS_NETWORK/run-state-$RELEASE_TAG.json"
bash script/deploy/v2-5/08-finalize-inventory.sh
```

### Separate retirement ceremony

Do not generate retirement until activation finalization and reconciliation have completed and the new generation has passed the agreed validation window. Retirement is not an activation cleanup step. Keeping it separate gives the subgraph, SDK, app, and canary checks time to prove the new origination path before old factories lose authority.

Generate retirement from the current post-activation inventory:

```bash
export OWNER_MODE=plan
bash script/deploy/v2-5/retirement/01-generate-plan.sh
```

The script writes `deployments/<network>/plan-v2-5-retirement.json`. For each still-registered superseded factory, it emits `removeControllerFactory(address)` immediately before `removeController(address)`. Sepolia adds its own helper reclaim and return. It emits no deployment, registration, or market-removal call.

Execute this as a distinct EOA or Safe ceremony with its own package and run-state. Then finalize only the independently verified retirement run:

```bash
export RUN_STATE="deployments/$DEPLOYMENTS_NETWORK/run-state-v2-5-retirement.json"
RPC_URL="$RPC_URL" bash script/deploy/v2-5/retirement/02-finalize-inventory.sh

node scripts/factory-inventory.js validate --network "$DEPLOYMENTS_NETWORK"
node scripts/factory-inventory.js lint --network "$DEPLOYMENTS_NETWORK"
node scripts/factory-inventory.js reconcile --network "$DEPLOYMENTS_NETWORK" --rpc-url "$RPC_URL"
```

Retirement target count is live state, not a release constant. The current reconciled inventories produced nine Sepolia targets and one mainnet target during rehearsal. Recheck the addresses and ordering before signing.

### Explorer verification

Verify every deployed contract. Derive each address and artifact name from the
plan and resolved run-state. Preserve the standard JSON input beside the rollout
artifacts:

```bash
forge verify-contract \
  --show-standard-json-input \
  "$ADDRESS" "$ARTIFACT" \
  > "$STANDARD_INPUT_PATH"
```

Submit with the matching explorer. Use `--guess-constructor-args` only after
confirming the recovered arguments match the plan's resolved arguments.

```bash
forge verify-contract \
  "$ADDRESS" "$ARTIFACT" \
  --chain "$CHAIN_ID" \
  --guess-constructor-args \
  --verifier "$VERIFIER" \
  --watch
```

| Network                        | `VERIFIER`   | Required configuration                                                                           |
| ------------------------------ | ------------ | ------------------------------------------------------------------------------------------------ |
| Ethereum mainnet               | `etherscan`  | `ETHERSCAN_API_KEY`                                                                              |
| Sepolia                        | `etherscan`  | `ETHERSCAN_API_KEY`                                                                              |
| Plasma mainnet, Plasma testnet | `blockscout` | Supply the network's `VERIFIER_URL`; this repository does not contain a Plasma explorer endpoint |

Do not mark a public rollout complete while a release contract remains
unverified.

### 09: canary markets

Environment: require `OWNER_MODE=direct`, `DEPLOYMENTS_NETWORK`, `BORROWER`, and
`RPC_URL`. Accept `RELEASE_TAG`, `CANARY_ASSET`, and `PVT_KEY_<NETWORK>`. Without
a key, expose `BORROWER` as an unlocked account. The shell wrapper sets
`CANARY_PHASE=prepare` and then `finalize`, and exports
`FOUNDRY_PROFILE=deploy`.

Register the borrower first. Then run:

```bash
export OWNER_MODE=direct
bash script/deploy/v2-5/09-canary-market.sh
```

The script deploys, funds, queues, and closes one dust market through each v2.5
factory. It refuses Ethereum mainnet and the configured Plasma mainnet chain ID.

Finish with validation, lint, reconcile, and handoff generation:

```bash
node scripts/factory-inventory.js validate --network "$DEPLOYMENTS_NETWORK"
node scripts/factory-inventory.js lint --network "$DEPLOYMENTS_NETWORK"
node scripts/factory-inventory.js reconcile \
  --network "$DEPLOYMENTS_NETWORK" \
  --rpc-url "$RPC_URL"
node scripts/generate-handoff.js \
  --network "$DEPLOYMENTS_NETWORK" \
  --release "$RELEASE_TAG"
node scripts/generate-handoff.js \
  --network "$DEPLOYMENTS_NETWORK" \
  --release "$RELEASE_TAG" \
  --check
```

## 4. Full rollout: mainnet Safe ceremonies

The Ethereum mainnet ArchController owner is the Foundation Safe at `0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`. The current rehearsal read Safe version 1.4.1 and threshold 3. Confirm both values again at release freeze.

### Generate activation

```bash
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=mainnet
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<mainnet RPC URL>'
export EXPECTED_EXECUTOR=0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae

forge script script/deploy/v2-5/01-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/02-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/03-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/04-deploy-market-lens.s.sol:DeployMarketLensV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25 --rpc-url "$RPC_URL"
forge script script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25 --rpc-url "$RPC_URL"
bash script/deploy/v2-5/07-generate-plan.sh
```

The activation plan must have 25 cards: 15 deployments and 10 calls. It must register six templates and both new factories. It must not remove any factory role or market.

### Bundle and simulate activation

`plan.js bundle` compiles the cards into atomic Safe transactions. Each transaction is a `MultiSend` delegatecall, and deployments use the canonical `CreateCall` library with CREATE2. Addresses are precomputed from the Safe, salt, and init-code hash. The Safe envelopes pin consecutive nonces so the reviewed EIP-712 hashes cannot drift.

```bash
SAFE_NONCE='<current on-chain Safe nonce>'
node scripts/plan.js bundle \
  --plan deployments/mainnet/plan-v2-5.json \
  --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae \
  --start-nonce "$SAFE_NONCE"

node scripts/plan.js bundle-simulate \
  --plan deployments/mainnet/plan-v2-5.json \
  --bundles deployments/mainnet/bundles-v2-5 \
  --rpc '<pinned mainnet fork RPC>' \
  --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae
```

The current plan fits into three activation bundles. The exact Safe rehearsal used 17,561,801, 18,107,377, and 14,771,586 gas. These numbers are evidence for the current source, not release constants. Every bundle must be regenerated and simulated against the current Safe nonce and remain below the 20,000,000 gas ceiling.

Any plan change or intervening Safe transaction invalidates the package. Read the nonce again, regenerate, and repeat the simulation.

### Build and execute activation

```bash
node scripts/plan.js ceremony-package \
  --plan deployments/mainnet/plan-v2-5.json \
  --mode safe \
  --bundles deployments/mainnet/bundles-v2-5

cd deploy-ui
CEREMONY_PACKAGE=../deployments/mainnet/ceremony-v2-5-safe.json npm run build
```

Record the full digest and short fingerprint in the independent signer channel before hosting `dist/`. The release site opens with the package embedded. Foundation operators do not select a plan file and no private key is handed to the deployment team.

Safe Transaction Builder cannot propose these transactions because its import path drops `operation: 1`. Its JSON output is review-only. Propose through the locked deployment UI and Safe SDK.

For each of the three activation bundles:

1. The operator proposes with `operation: 1`.
2. Signers review the bundle and its plain-English inner cards, compare the nonce, addresses, calldata, and predicates, then approve the Safe transaction.
3. At threshold, the operator executes. The UI checks every inner predicate before advancing. Any failed predicate stops the ceremony.

The 25 cards are not 25 signer transactions. They are inner review actions inside three Safe bundles. With threshold 3, activation requires three approvals from each participating signer. If the same three signers participate, that is nine signatures total.

Export or derive the activation run-state, verify it independently, and finalize it:

```bash
export RUN_STATE=deployments/mainnet/run-state-v2-5.json
bash script/deploy/v2-5/08-finalize-inventory.sh

node scripts/generate-handoff.js --network mainnet --release v2-5
node scripts/generate-handoff.js --network mainnet --release v2-5 --check
```

Complete explorer verification and downstream validation while the superseded factory remains registered.

### Generate and execute retirement later

After the validation window, reconcile the finalized inventory and generate retirement fresh:

```bash
cd /Users/kethcode/wildcat/mono/v2-protocol
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=mainnet
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<mainnet RPC URL>'
export EXPECTED_EXECUTOR=0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae

node scripts/factory-inventory.js reconcile --network mainnet --rpc-url "$RPC_URL"
bash script/deploy/v2-5/retirement/01-generate-plan.sh
```

Review every retirement target. The current rehearsal inventory produced one superseded factory, so its plan contained two calls in order: `removeControllerFactory(address)` and then `removeController(address)`. The count is state-dependent and must be reviewed again at release time. No market is removed.

Read the Safe nonce again and package retirement independently:

```bash
RETIREMENT_SAFE_NONCE='<current on-chain Safe nonce>'
node scripts/plan.js bundle \
  --plan deployments/mainnet/plan-v2-5-retirement.json \
  --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae \
  --start-nonce "$RETIREMENT_SAFE_NONCE"

node scripts/plan.js bundle-simulate \
  --plan deployments/mainnet/plan-v2-5-retirement.json \
  --bundles deployments/mainnet/bundles-v2-5-retirement \
  --rpc '<pinned mainnet fork RPC>' \
  --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae

node scripts/plan.js ceremony-package \
  --plan deployments/mainnet/plan-v2-5-retirement.json \
  --mode safe \
  --bundles deployments/mainnet/bundles-v2-5-retirement
```

The rehearsed two-call retirement fits into one Safe bundle and used 94,042 gas. Run it as a separate signer session. Each threshold signer approves once. After execution, derive or export `run-state-v2-5-retirement.json`, verify it, and finalize:

```bash
export RUN_STATE=deployments/mainnet/run-state-v2-5-retirement.json
RPC_URL="$RPC_URL" bash script/deploy/v2-5/retirement/02-finalize-inventory.sh
node scripts/factory-inventory.js reconcile --network mainnet --rpc-url "$RPC_URL"
```

Across the current activation and retirement shapes, the Foundation handles four Safe transactions. If the same three signers approve all four, that is four approvals per signer and 12 signatures total.

## 5. Fork rehearsal

The canonical Sepolia-shaped EOA procedure is
[`anvil-v2-5-rehearsal.md`](./anvil-v2-5-rehearsal.md). It deliberately uses
`rehearse.sh` only for fork setup and plan generation, then packages the fresh
plan into the same locked production UI shape used for the live ceremony.

`rehearse.sh --full` remains a useful headless engine check, but it does not
exercise wallet connection, package fingerprint review, card UX, checkpoint
export, or browser resume. It is therefore supplementary, not a replacement
for the locked-UI release gate.

Every fork rehearsal must preserve these invariants:

- require one explicitly selected archive RPC, pin one fork block, and prove
  the endpoint can serve historical storage before deleting or creating local
  rehearsal state; never introduce an external RPC implicitly, and treat any
  explicitly supplied second URL as active round-robin rather than failover;
- poll the local RPC until it actually serves chain `31337`; on bounded startup
  timeout, terminate the launcher-owned process instead of reporting an
  ambiguous failure while it continues starting in the background;
- persist Anvil state at a short interval, retain its log/PID/fork-block
  metadata, and use `rehearse.sh --resume` rather than reseeding after a
  recoverable node crash;
- seed both `deployments.json` and `factory-inventory.json`, then rewrite only
  the copied inventory identity to network `anvil`, chain ID `31337`;
- generate the plan from the source revision under review with
  `FOUNDRY_PROFILE=deploy` rather than reusing generated output;
- for the Sepolia-shaped UI path, authorize a disposable Anvil EOA in the helper and keep reclaim and return as the first and final cards of each ceremony;
- require 15 activation deployments, six template registrations, two new factory registrations, and no factory or market removal;
- finalize activation only from its unedited, independently verified run-state, then generate retirement from the resulting reconciled inventory;
- require each retirement target to lose its controller-factory role before its controller role, with no market removal;
- finalize retirement only from its own unedited, independently verified run-state;
- treat browser progress as stored but unverified until the connected chain
  rechecks receipts and predicates; only Anvil packages expose the destructive
  new-rehearsal reset;
- keep historical indexing flags while marking retired factories unregistered; and
- preserve exact logs/artifacts and kill only the Anvil PID owned by the run.

For a mainnet fork, the Foundation Safe/bundle path has separate nonce,
CREATE2, delegatecall, signature, and gas-ceiling requirements in section 4.
On mainnet forks, deploy a mock asset before the canary because mainnet
`deployments.json` has no mock token.

## 6. Adding a market type

1. Write the factory contract and its interface. Define the market init-code
   artifact, constructor inputs, registration predicates, and market-specific ABI
   surface.
2. Copy the 01/02 script shape. Give every plan entry a unique dot-free ID, ordered sequence, output, envelope, dependency, description, and on-chain predicate. Emit one pending init-code-storage record when creation code fits a single EIP-170 payload. Use the reviewed two-part storage pattern when it does not. Emit one pending factory record with every storage address needed to reconstruct the exact creation code.
3. Add the market type to inventory validation. Append the factory record. Move
   one canonical pointer for that market type; keep older live generations and
   retired exclusions.
4. Add the template registrations and reviewed fees to
   `deployments/template-fee-parameters.json`. State which templates apply to the
   new factory.
5. Add the factory artifact, market artifact, ABI delta, indexing policy, and
   routing rule to `scripts/generate-handoff.js`.
6. Rehearse activation and retirement on both target-network forks. Require plan validation, all predicates, receipt-derived start blocks, inventory validation, lint, reconciliation, canary closure, handoff generation, and handoff `--check`.

Do not add a deployment framework. Extend the numbered release pattern.

## 7. Sepolia temporary-owner flow

`deployments/sepolia/ceremony-config.json` makes the existing `MockArchControllerOwner` reclaim, act, and return sequence part of every generated owner-action plan. Activation and retirement each reclaim and return independently. Do not leave the developer EOA holding ownership between them. The first card calls `returnOwnership()`, and the last card calls `transferOwnership(helper)`. Resume rechecks the temporary-owner predicate until that compensating final card is verified, then treats it as historical.

Before starting, resolve the helper and operator key and confirm the EOA is
authorized by the helper:

```bash
export HELPER_OPERATOR_KEY="${HELPER_OPERATOR_KEY:-$PVT_KEY_SEPOLIA}"
export ARCH_CONTROLLER="${ARCH_CONTROLLER:-$(jq -r '.WildcatArchController' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
export HELPER_OWNER="$(cast call "$ARCH_CONTROLLER" "owner()(address)" --rpc-url "$RPC_URL")"
cast call "$HELPER_OWNER" "authorizedAccounts(address)(bool)" \
  "$EXPECTED_EXECUTOR" --rpc-url "$RPC_URL"
```

If the ceremony halts after reclaim and before the final compensation, preserve
the run-state and return ownership with the reviewed recovery command before
ending the session:

```bash
cast send "$ARCH_CONTROLLER" \
  "transferOwnership(address)" \
  "$HELPER_OWNER" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"

cast call "$ARCH_CONTROLLER" "owner()(address)" --rpc-url "$RPC_URL"
```

Do not delay the return for a possible retirement. Retirement has its own reclaim and return sequence.

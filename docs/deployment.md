# v2.5 deployment

> This is the v2.5 process document. It supersedes
> `docs/rcf-v2-deployment-checklist.md`; keep the old checklist as historical
> reference.

## 1. Overview

Create a fresh numbered script set for every release. For v2.5, run
`script/deploy/v2-5/01` through `09` in order. Do not reuse feature-specific
deployment scripts.

Use one executor mode per target:

| Network                                  | Executor                                                                            | Owner mode         |
| ---------------------------------------- | ----------------------------------------------------------------------------------- | ------------------ |
| Ethereum mainnet, Plasma mainnet         | Foundation through the disposable deployment frontend, with the team on a live call | `plan`             |
| Sepolia, Plasma testnet, future testnets | Dev EOA, with `MockArchControllerOwner` ownership reclaimed while owner calls run   | `direct`           |
| Anvil forks                              | Impersonated owner of the forked ArchController                                     | `plan` or `direct` |

`DeployScriptBase` enforces an explicit `OWNER_MODE` on Ethereum mainnet and
Plasma mainnet. It defaults to `direct` elsewhere. `plan.js` currently maps only
`mainnet`, `sepolia`, and `anvil` to chain IDs; pass a supported name when
assembling a plan. Plasma owner-mode handling exists in Solidity, but plan
assembly has no Plasma chain-ID mapping.

For the Foundation ceremony, generate one ordered plan artifact. Build a fresh,
disposable frontend that renders that artifact. Have the Foundation execute it
while the deployment team verifies the chain, executor, nonce, receipt, and
predicate on a live call. Treat the plan schema, not the frontend, as the durable
interface.

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

## 3. Full rollout: testnet, direct executor

### The two flows, and which one to use

- **Generational rollouts** — anything that adds factory generations or moves
  canonical pointers — use the **plan pipeline on every network**: generate
  01–06 with `OWNER_MODE=plan`, assemble (07), execute the plan
  (`plan.js execute --private-key` with a dev EOA on testnets; the Foundation
  ceremony on mainnet), finalize (08), handoff. One artifact, one executor,
  two signers. Only this flow reaches step 08: `apply-run` requires the
  run-state's receipt provenance (tx hashes, receipt blocks for
  `startBlock`s), which only `plan.js execute` records.
- **Component maintenance** — redeploying a replaceable component (lens,
  provider) between releases — uses the scripts' inline
  `OWNER_MODE=direct` broadcast: one script, one command, no plan assembly.
  This deliberately does not run 08; there are no generational records to
  add, and the canonical-alias helper keeps `deployments.json` and
  factory-inventory coherent. Regenerate the handoff afterwards if
  downstream needs the new address.

Do not attempt a generational rollout through the inline path: it broadcasts
fine but writes concrete-address pending records that
`factory-inventory.js apply-run` rejects (it requires plan `$ref` records
plus a verified run-state), so `08-finalize-inventory.sh` will refuse to
finalize it. This is a fence, not a gap — receipt-provenance inventory is
the point of step 08.

The script headers define these environments:

| Step | Both modes                                                                                                                                  | Inline `direct`                                                                                                | `plan` generation                              |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| 01   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG` (default `v2-5`), `ARCH_CONTROLLER`, `SANCTIONS_SENTINEL`, `SKIP_EIP1153_CHECK`               | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>` unless Foundry already has a sender  | `OWNER_MODE=plan`, `EXPECTED_EXECUTOR`; no key |
| 02   | Same as 01                                                                                                                                  | Same as 01                                                                                                     | Same as 01                                     |
| 03   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`, `SKIP_EIP1153_CHECK`; 01 first                                            | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>` unless Foundry already has a sender  | `OWNER_MODE=plan`, `EXPECTED_EXECUTOR`; no key |
| 04   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`, `SKIP_EIP1153_CHECK`; inventory v1 wrapper record or explicit empty array | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>` unless Foundry already has a sender  | `OWNER_MODE=plan`, `EXPECTED_EXECUTOR`; no key |
| 05   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`, `TEMPLATE_FEE_SOURCE_FACTORY`, `TEMPLATE_FEE_RECIPIENT`; 01–04 first      | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>`; broadcaster is ArchController owner | `OWNER_MODE=plan`, `EXPECTED_EXECUTOR`; no key |
| 06   | `DEPLOYMENTS_NETWORK`; optional `RELEASE_TAG`, `ARCH_CONTROLLER`; 05 first                                                                  | `OWNER_MODE=direct` (default off mainnet), `RPC_URL`, `PVT_KEY_<NETWORK>`                                      | `OWNER_MODE=plan`, `EXPECTED_EXECUTOR`; no key |

The inline commands add `--rpc-url "$RPC_URL" --broadcast` to the Forge
invocations below. They deploy and perform owner calls immediately, but stop at
the finalization constraint above.

### Preflight

Set the deployment profile for every Forge and Node step:

```bash
export FOUNDRY_PROFILE=deploy
```

This is mandatory. A targeted default-profile size build reports
`HooksFactoryRevolving` at 24,767 runtime bytes, 191 bytes above EIP-170; a full
default-profile build also encounters `Stack too deep`. The `deploy` profile
uses via-IR and optimizer runs `200`, produces the creation code consumed by the
plan, and reports `HooksFactoryRevolving` at 14,609 runtime bytes. Do not
substitute the default or high-run IR profile.

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

### 01 — standard hooks factory

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG` (default `v2-5`), `ARCH_CONTROLLER`,
`SANCTIONS_SENTINEL`, and `SKIP_EIP1153_CHECK`. No private key is required while
generating.

```bash
forge script \
  script/deploy/v2-5/01-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25
```

### 02 — revolving hooks factory

Use the same environment as 01.

```bash
forge script \
  script/deploy/v2-5/02-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25
```

### 03 — MarketLens set

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG`, `ARCH_CONTROLLER`, and
`SKIP_EIP1153_CHECK`. Run 01 first.

```bash
forge script \
  script/deploy/v2-5/03-deploy-market-lens.s.sol:DeployMarketLensV25
```

### 04 — 4626 wrapper facade

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG`, `ARCH_CONTROLLER`, and
`SKIP_EIP1153_CHECK`. Ensure the network inventory has exactly one v1 wrapper
record, or an explicit empty `wrapperFactories` array for a chain with no v1.

```bash
forge script \
  script/deploy/v2-5/04-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25
```

### 05 — owner actions and templates

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG`, `ARCH_CONTROLLER`,
`TEMPLATE_FEE_SOURCE_FACTORY`, and `TEMPLATE_FEE_RECIPIENT`. The script reads
`deployments/template-fee-parameters.json`. Run 01–04 first.

```bash
forge script \
  script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25
```

### 06 — register both factories as controllers

Environment: require `DEPLOYMENTS_NETWORK`, `OWNER_MODE=plan`, and
`EXPECTED_EXECUTOR`. Accept `RELEASE_TAG` and `ARCH_CONTROLLER`. Run 05 first.

```bash
forge script \
  script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25
```

### 07 — assemble and execute

Environment for assembly: require `DEPLOYMENTS_NETWORK`; accept `RELEASE_TAG`
(default `v2-5`). The wrapper exports `FOUNDRY_PROFILE=deploy` itself.

```bash
bash script/deploy/v2-5/07-generate-plan.sh
node scripts/plan.js execute \
  --plan "deployments/$DEPLOYMENTS_NETWORK/plan-$RELEASE_TAG.json" \
  --rpc "$RPC_URL" \
  --private-key "$PVT_KEY_SEPOLIA"
```

Review the summary before execution. The current v2.5 scripts produce 21
transactions: 12 deployments and 9 calls. `execute` writes
`deployments/<network>/run-state-v2-5.json` after receipts and predicates.

### 08 — finalize inventory

Environment: require `DEPLOYMENTS_NETWORK` and `RUN_STATE`; accept `RPC_URL`.
The wrapper exports `FOUNDRY_PROFILE=deploy` itself. It rejects any missing,
unknown, non-verified, or malformed run-state entry; appends exactly two hooks
factories and one wrapper factory; moves canonical aliases; then reconciles.

```bash
export RUN_STATE="deployments/$DEPLOYMENTS_NETWORK/run-state-$RELEASE_TAG.json"
bash script/deploy/v2-5/08-finalize-inventory.sh
```

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

### 09 — canary markets

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

## 4. Full rollout: mainnet plan ceremony

The Ethereum mainnet ArchController owner is the Foundation Safe
`0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`. Mainnet RPC reads on 2026-07-10
returned Safe `VERSION()` `1.4.1` and threshold `3`.

### Generate 01→06 and assemble 07

```bash
export FOUNDRY_PROFILE=deploy
export DEPLOYMENTS_NETWORK=mainnet
export RELEASE_TAG=v2-5
export OWNER_MODE=plan
export RPC_URL='<mainnet RPC URL>'
export EXPECTED_EXECUTOR=0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae

forge script script/deploy/v2-5/01-deploy-hooks-factory-standard.s.sol:DeployHooksFactoryStandardV25
forge script script/deploy/v2-5/02-deploy-hooks-factory-revolving.s.sol:DeployHooksFactoryRevolvingV25
forge script script/deploy/v2-5/03-deploy-market-lens.s.sol:DeployMarketLensV25
forge script script/deploy/v2-5/04-deploy-wrapper-factory.s.sol:DeployWrapperFactoryV25
forge script script/deploy/v2-5/05-owner-actions.s.sol:OwnerActionsV25
forge script script/deploy/v2-5/06-register-factories.s.sol:RegisterFactoriesV25
bash script/deploy/v2-5/07-generate-plan.sh
```

Hand these inputs to the disposable frontend build:

- `deployments/mainnet/plan-v2-5.json`;
- the `deploy-out` artifacts named by every deploy transaction's
  `artifactName`;
- the contract and interface ABIs listed by `abiArtifactName` in
  `scripts/generate-handoff.js`'s `RELEASE_CONTRACTS` data;
- the run-state field contract used by `plan.js`: transaction ID → `txHash`,
  `blockNumber`, `status`, and `resolvedAddress` for deployments.

Do not hand over a private key. The Safe executes every transaction.

### Bundle the plan (the ceremony format)

The ceremony does not execute 21 transactions one by one. `plan.js bundle`
compiles the plan into a minimal set of atomic Safe transactions (3 for
v2-5), each a `MultiSend` **delegatecall** whose deployments run through the
canonical `CreateCall` library as CREATE2 — every address is precomputed at
bundle time from `(safe, salt, initCodeHash)`, all `$ref`s resolve
statically, and nothing depends on nonces or mid-ceremony state.

```bash
node scripts/plan.js bundle \
  --plan deployments/mainnet/plan-v2-5.json \
  --safe 0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae
# outputs: deployments/mainnet/bundles-v2-5/
#   bundle-N.txbuilder.json   (review-only import; see warning below)
#   bundle-N.manifest.json    (the frontend's data source)
#   expected-addresses.json   (pre-fills the handoff)
#   review-v2-5.md            (the signers' review sheet)
```

Rehearse before signing: `plan.js bundle-simulate` executes every bundle
through the real Safe on an anvil mainnet fork and reports per-bundle gas
(v2-5: ~15.8M / 17.3M / 9.8M against a 20M ceiling) and all predicates.

**Safe Transaction Builder cannot propose these.** Its import model drops
the transaction's `operation`; an imported row submits as CALL and the
delegatecall reverts. Proposals must carry `operation: 1` — the deploy-ui
frontend does this via the Safe SDK; the txbuilder.json files are for
review only.

### Live-call ceremony (deploy-ui, Safe mode)

Host `deploy-ui/dist` statically (see `deploy-ui/README.md`), load the plan
and bundle manifests, and confirm on the call: chain ID `1`, Safe address
and version, threshold, **plan and bundle hashes against the review sheet**
(everyone must be looking at identical bytes), and the per-bundle gas
figures from simulation.

Per bundle (3 total):

1. The operator proposes through the page (Safe SDK, `operation: 1`); the
   page shows signature progress against the threshold.
2. Signers review the bundle card — plain-English inner transactions,
   precomputed addresses — and sign from their own Safe apps (or in-page).
3. At threshold, the operator executes. The page verifies every inner
   predicate against the precomputed addresses and shows the green board
   before advancing. A predicate failure is a full stop; bundles are atomic,
   so there is no partial-bundle state to recover.

Signer click budget for the whole rollout: connect, review, three
signatures. After bundle 3: export the run-state from the page (or derive
it with `plan.js bundle-verify`) and proceed to 08.

### Finalize, verify, and hand off

Finalize only with the completed resolved run-state:

```bash
export RUN_STATE=deployments/mainnet/run-state-v2-5.json
bash script/deploy/v2-5/08-finalize-inventory.sh
```

Run the Etherscan verification procedure from section 3. Then generate and check
the handoff:

```bash
node scripts/generate-handoff.js --network mainnet --release v2-5
node scripts/generate-handoff.js --network mainnet --release v2-5 --check
```

Deliver `handoff-v2-5.json` and `handoff-v2-5.md` with the verified ABIs to the
subgraph and SDK owners.

Operator-reported rehearsal record: both the Sepolia fork and mainnet fork
completed end to end with a 21-transaction plan, all predicates passing,
reconcile green, and both canary markets closed. No checked-in plan, run-state,
or canary receipt currently proves that historical result; retain the rehearsal
logs with the live rollout artifacts.

## 5. Fork rehearsal

These are setup requirements, not optional cleanup:

- Seed `deployments/anvil/` from the forked network: `cp deployments.json` AND
  `factory-inventory.json`, then rewrite the seeded inventory's
  `network` → `anvil`, `chainId` → `31337` (`apply-run` enforces identity).
- Start Anvil with `--auto-impersonate`; fund the impersonated owner through
  `anvil_setBalance` before executing. The Sepolia owner is the
  `MockArchControllerOwner` contract; the mainnet owner is the Foundation Safe.
  Both work as impersonated senders on Anvil.
- Set `EXPECTED_EXECUTOR` to `archController.owner()` read off the fork.
- Satisfy canary prerequisites: call `registerBorrower` through the impersonated
  owner. On mainnet forks, also deploy a `MockERC20` and pass `CANARY_ASSET`;
  mainnet `deployments.json` has no mock token.
- Clean up `deployments/anvil/` and the rehearsal's `broadcast`/`deploy-cache`
  artifacts afterward.

Seed and rewrite:

```bash
export FORK_NETWORK=sepolia # or mainnet
mkdir -p deployments/anvil
cp "deployments/$FORK_NETWORK/deployments.json" deployments/anvil/deployments.json
cp "deployments/$FORK_NETWORK/factory-inventory.json" deployments/anvil/factory-inventory.json
jq '.network = "anvil" | .chainId = 31337' \
  deployments/anvil/factory-inventory.json \
  > deployments/anvil/factory-inventory.json.tmp
mv deployments/anvil/factory-inventory.json.tmp deployments/anvil/factory-inventory.json
```

Start the fork:

```bash
anvil --fork-url "$FORK_RPC_URL" --auto-impersonate
```

Read and fund the executor:

```bash
export ARCH_CONTROLLER="$(jq -r '.WildcatArchController' deployments/anvil/deployments.json)"
export EXPECTED_EXECUTOR="$(cast call "$ARCH_CONTROLLER" 'owner()(address)' --rpc-url "$RPC_URL")"
cast rpc anvil_setBalance "$EXPECTED_EXECUTOR" 0x3635C9ADC5DEA00000 --rpc-url "$RPC_URL"
```

Register the canary borrower:

```bash
cast send "$ARCH_CONTROLLER" \
  'registerBorrower(address)' \
  "$BORROWER" \
  --from "$EXPECTED_EXECUTOR" \
  --unlocked \
  --rpc-url "$RPC_URL"
```

For a mainnet fork, deploy `script/mock/MockERC20.sol:MockERC20` from a funded,
unlocked account and export the returned address as `CANARY_ASSET` before step 09.

Remove only artifacts created by the rehearsal. Do not remove another
operator's concurrent broadcast directory.

## 6. Adding a market type

1. Write the factory contract and its interface. Define the market init-code
   artifact, constructor inputs, registration predicates, and market-specific ABI
   surface.
2. Copy the 01/02 script shape. Give every plan entry a unique dot-free ID,
   ordered sequence, output, envelope, dependency, description, and on-chain
   predicate. Emit one pending init-code-storage record and one pending factory
   record.
3. Add the market type to inventory validation. Append the factory record. Move
   one canonical pointer for that market type; keep older live generations and
   retired exclusions.
4. Add the template registrations and reviewed fees to
   `deployments/template-fee-parameters.json`. State which templates apply to the
   new factory.
5. Add the factory artifact, market artifact, ABI delta, indexing policy, and
   routing rule to `scripts/generate-handoff.js`.
6. Rehearse 01→09 on both target-network forks. Require plan validation, all
   predicates, receipt-derived start blocks, inventory validation, lint,
   reconcile, canary closure, handoff generation, and handoff `--check`.

Do not add a deployment framework. Extend the numbered release pattern.

## 7. Sepolia direct-owner flow

Use the existing `MockArchControllerOwner` reclaim → act → return sequence. Keep
ownership until every owner-gated step is complete.

Resolve the helper and operator key:

```bash
export HELPER_OPERATOR_KEY="${HELPER_OPERATOR_KEY:-$PVT_KEY_SEPOLIA}"
export ARCH_CONTROLLER="${ARCH_CONTROLLER:-$(jq -r '.WildcatArchController' deployments/$DEPLOYMENTS_NETWORK/deployments.json)}"
export HELPER_OWNER="$(cast call "$ARCH_CONTROLLER" "owner()(address)" --rpc-url "$RPC_URL")"
```

Reclaim ownership using the checklist's command:

```bash
cast send "$HELPER_OWNER" \
  "returnOwnership()" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"
```

Confirm that the EOA is now `owner()`. Generate and execute steps 01→07 as in
section 3. Steps 05 and 06 are the owner-gated actions. Finalize 08 while the
resolved run-state is intact.

Return ownership using the checklist's command:

```bash
cast send "$ARCH_CONTROLLER" \
  "transferOwnership(address)" \
  "$HELPER_OWNER" \
  --rpc-url "$RPC_URL" \
  --private-key "$HELPER_OPERATOR_KEY"

cast call "$ARCH_CONTROLLER" "owner()(address)" --rpc-url "$RPC_URL"
```

Delay the return only for an explicit follow-up owner action.

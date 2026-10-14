# Ink deployment checklist

fresh deployment: [Anvil rehearsal](#anvil-rehearsal) or [live Ink Sepolia](#live-ink-sepolia). the live path is standalone; don't run the Anvil steps against a public chain.

already stopped at sanctions seeding? go straight to [the live continuation](#continuation-defer-rejected-sanctions-seeding), not the fresh-deployment steps.

## Anvil rehearsal

run from the `release/ink` repo root, one block at a time. stop on errors. this sends transactions only to local Anvil; don't load a real private key.

this first pass uses the shipped two-address sanctions fixture. it tests the real mirror contracts, not the source subgraph or keeper. no snapshot export is needed for this pass.

already prepared before these script changes? keep that evidence and make a new run at step 4. if it sent any transactions, restart the fork at step 1 first.

keep these values in the repo-root `.env`; keep your existing values if already set. `.env` is Git-ignored. edit the file, not the commands below:

```dotenv
INK_RPC_TOKEN=
INK_DEPLOYER=
INK_FEE_RECIPIENT=
# optional Blockscout key; unused on Anvil
INK_BLOCKSCOUT_API_KEY=
```

### 1. start the fork — terminal A

- [ ] load `.env` and fork the latest Ink Sepolia block; leave this terminal running:

```sh
set -a
source .env
set +a
anvil --host 127.0.0.1 --port 8548 --network optimism --chain-id 763373 \
  --fork-url https://rpc.wildcat.finance/763373 \
  --fork-header "Authorization: Bearer ${INK_RPC_TOKEN:?set INK_RPC_TOKEN in .env}"
```

check: Anvil is listening on `127.0.0.1:8548`. the bearer is for the upstream gateway, not local Anvil. no block number to choose. leave code-size and gas limits alone; don't add `--hardfork cancun`.

### 2. connect and check tools — terminal B

use this terminal for everything below. requires Node 22+, `jq`, Foundry with solc 0.8.25, and initialized pinned submodules.

- [ ] load `.env` in this terminal too, select the local fork and run the checks. `set -a` exports the file's variables for Node and Foundry:

```sh
set -a
source .env
set +a
export FOUNDRY_PROFILE=ink
export INK_RPC_URL=http://127.0.0.1:8548
cast chain-id --rpc-url "$INK_RPC_URL"
cast rpc web3_clientVersion --rpc-url "$INK_RPC_URL"
node script/ink/ink.mjs check
node --test test/ink/*.test.mjs
```

check: chain `763373`, client contains `anvil`, build/size checks succeed, all inventory/verification tests pass.

### 3. unlock and fund the deployer

- [ ] use the accounts from `.env`; unlock/fund the deployer **on the fork only**:

```sh
: "${INK_DEPLOYER:?set INK_DEPLOYER in .env}"
: "${INK_FEE_RECIPIENT:?set INK_FEE_RECIPIENT in .env}"
cast rpc anvil_impersonateAccount "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL"
cast rpc anvil_setBalance "$INK_DEPLOYER" "$(cast to-hex "$(cast to-wei 10 ether)")" --rpc-url "$INK_RPC_URL"
cast balance "$INK_DEPLOYER" --ether --rpc-url "$INK_RPC_URL"
```

check: `anvil_impersonateAccount` and `anvil_setBalance` return `null` on success; balance is `10` ETH. this changes no live balance and needs no keystore. the fee address needn't have Safe code for the Sepolia bootstrap; the mainnet handoff below does require it.

### 4. make the rehearsal config

- [ ] generate a fresh config: `500` protocol fee bps, `deployFeeRecipient: false`. fees accrue in markets; the collection job calls `collectFees()` to send available fees directly to `INK_FEE_RECIPIENT`. no extra recipient contract is needed for that flow.

```sh
export INK_RUN="deployments/ink/runs/rehearsal-$(date -u +%Y%m%dT%H%M%SZ)"
export INK_CONFIG="deployments/ink/config/$(basename "$INK_RUN").json"
mkdir -p deployments/ink/config
(
  set -C
  jq --arg deployer "$INK_DEPLOYER" --arg recipient "$INK_FEE_RECIPIENT" \
    --argjson chain "$(cast chain-id --rpc-url "$INK_RPC_URL")" \
    --argjson nonce "$(cast nonce "$INK_DEPLOYER" --block pending --rpc-url "$INK_RPC_URL")" \
    '.chainId = $chain | .deployer = $deployer | .feeRecipient = $recipient |
     .expectedNonce = $nonce | .deployFeeRecipient = false | .protocolFeeBips = 500' \
    script/ink/fixtures/testnet-rehearsal.json > "$INK_CONFIG"
)
jq . "$INK_CONFIG"
```

check: your addresses, chain `763373`, `mode: "rehearsal"`, the fork's nonce, your fee settings, and `script/ink/fixtures/sanctions.json`. don't replace the nonce with zero.

### 5. deploy and collect

- [ ] run each command only after the previous one succeeds:

```sh
node script/ink/ink.mjs prepare "$INK_CONFIG" "$INK_RUN"
node script/ink/ink.mjs run "$INK_RUN" --broadcast --unlocked
node script/ink/ink.mjs collect "$INK_RUN"
```

don't edit source/config/snapshot or send other deployer transactions between `prepare` and `collect`.

- [ ] inspect the result:

```sh
jq '{status, mode, chainId, contracts: (.contracts | length), testnetOwnerSource, authorities}' "$INK_RUN/inventory.json"
```

check: `confirmed-bootstrap`, `rehearsal`, `763373`, **13 contracts** (14 with a fee forwarder). `archOwner` is the testnet helper, `testnetOwnerVersion` is `"2"`, and `testnetOwnerAuthorizedAccounts` contains only your deployer. sanctions owners and SphereX admin/operator are still the deployer. `collect` checks receipts, code, bindings, fees and initial sanctions membership.

`collect` also writes `verification-*.json`: expect `skipped-rehearsal` here. no explorer requests are made for Anvil. on live Ink/Sepolia it submits source verification to Blockscout automatically.

if broadcast was interrupted, keep Anvil running and preserve the run, source/config and Forge cache. **only if `transaction-plan.json` exists**, try:

```sh
node script/ink/ink.mjs resume "$INK_RUN" --broadcast --unlocked
node script/ink/ink.mjs collect "$INK_RUN"
```

otherwise stop and reconcile; don't restart `run` over a partial deployment. an intentional fresh attempt needs a fresh Anvil fork and a new config/run. keep the old evidence.

### 6. smoke checks — after collection

- [ ] run the isolated contract-flow tests against the fork:

```sh
forge test --offline --fork-url "$INK_RPC_URL" --match-path 'test/ink/*.t.sol' -vv
```

check: **all tests pass**. these deploy isolated test contracts for open/fixed markets, wrappers, sanctions, helper administration and role transfers; they don't create demo markets in your collected deployment. the known Solar `unresolved symbol locals` diagnostic can appear despite passing tests.

- [ ] clear and restore one fixture sanction on the actual deployment:

```sh
ink_address() { jq -er --arg name "$1" '.contracts[] | select(.name == $name) | .address' "$INK_RUN/inventory.json"; }
export INK_SANCTIONS_LIST="$(ink_address SanctionsList)"
export INK_SANCTIONS_ADAPTER="$(ink_address SanctionsAdapter)"
export INK_FLAGGED="$(jq -r '.addresses[0]' script/ink/fixtures/sanctions.json)"
cast call "$INK_SANCTIONS_ADAPTER" 'isSanctioned(address)(bool)' "$INK_FLAGGED" --rpc-url "$INK_RPC_URL"
cast send "$INK_SANCTIONS_LIST" 'removeFromSanctionsList(address[])' "[$INK_FLAGGED]" --from "$INK_DEPLOYER" --unlocked --rpc-url "$INK_RPC_URL"
cast call "$INK_SANCTIONS_ADAPTER" 'isSanctioned(address)(bool)' "$INK_FLAGGED" --rpc-url "$INK_RPC_URL"
cast send "$INK_SANCTIONS_LIST" 'addToSanctionsList(address[])' "[$INK_FLAGGED]" --from "$INK_DEPLOYER" --unlocked --rpc-url "$INK_RPC_URL"
cast call "$INK_SANCTIONS_ADAPTER" 'isSanctioned(address)(bool)' "$INK_FLAGGED" --rpc-url "$INK_RPC_URL"
```

check: reads return **true → false → true**; both transactions succeed. keep the run directory and `broadcast/DeployInk.s.sol/763373/` evidence. the Sepolia bootstrap rehearsal ends here; the Safe handoff script rejects this chain.

### 7. later: mainnet-fork handoff rehearsal

- [ ] stop Anvil with Ctrl-C. repeat steps 1–6 with `57073` in both the fork URL and `--chain-id`; read the chain checks and evidence path as `57073` too. keep port `8548`; use a fresh config/run. expect **12 contracts** (13 with a forwarder), no testnet helper, and the EOA as initial `archOwner`.
- [ ] add `INK_FOUNDATION_SAFE` to `.env`, reload it, and check that the Safe exists on this fork with the expected owners/threshold:

```sh
set -a
source .env
set +a
: "${INK_FOUNDATION_SAFE:?set INK_FOUNDATION_SAFE in .env}"
cast code "$INK_FOUNDATION_SAFE" --rpc-url "$INK_RPC_URL"
cast call "$INK_FOUNDATION_SAFE" 'getOwners()(address[])' --rpc-url "$INK_RPC_URL"
cast call "$INK_FOUNDATION_SAFE" 'getThreshold()(uint256)' --rpc-url "$INK_RPC_URL"
```

check: code isn't `0x`; owners/threshold match. funding an address doesn't deploy a Safe. stop here if it isn't deployed. this rehearsal impersonates the Safe; it doesn't test collecting real Safe signatures.

- [ ] nominate, advance the local clock, accept as the Safe, then finish. park list ownership with the Safe until a keeper is selected:

```sh
export INK_CANDIDATE="$INK_RUN/candidate.json"
export INK_SANCTIONS_UPDATER="$INK_FOUNDATION_SAFE"
export INK_TREASURY_RECIPIENT="$INK_FEE_RECIPIENT"
export INK_ARCH="$(ink_address WildcatArchController)"
export INK_ENGINE="$(ink_address SphereXEngine)"
forge script script/ink/HandoffInk.s.sol:HandoffInk --sig 'nominate()' --offline --rpc-url "$INK_RPC_URL" --sender "$INK_DEPLOYER" --unlocked --broadcast --slow
cast rpc evm_increaseTime 3601 --rpc-url "$INK_RPC_URL"
cast rpc evm_mine --rpc-url "$INK_RPC_URL"
cast rpc anvil_impersonateAccount "$INK_FOUNDATION_SAFE" --rpc-url "$INK_RPC_URL"
cast rpc anvil_setBalance "$INK_FOUNDATION_SAFE" "$(cast to-hex "$(cast to-wei 10 ether)")" --rpc-url "$INK_RPC_URL"
cast send "$INK_ARCH" 'acceptSphereXAdminRole()' --from "$INK_FOUNDATION_SAFE" --unlocked --rpc-url "$INK_RPC_URL"
cast send "$INK_ARCH" 'changeSphereXOperator(address)' "$INK_FOUNDATION_SAFE" --from "$INK_FOUNDATION_SAFE" --unlocked --rpc-url "$INK_RPC_URL"
cast send "$INK_ENGINE" 'acceptDefaultAdminTransfer()' --from "$INK_FOUNDATION_SAFE" --unlocked --rpc-url "$INK_RPC_URL"
forge script script/ink/HandoffInk.s.sol:HandoffInk --sig 'finish()' --offline --rpc-url "$INK_RPC_URL" --sender "$INK_DEPLOYER" --unlocked --broadcast --slow
cast call "$INK_ARCH" 'owner()(address)' --rpc-url "$INK_RPC_URL"
cast call "$INK_SANCTIONS_LIST" 'owner()(address)' --rpc-url "$INK_RPC_URL"
```

check: both owners are the Safe. `finish()` must succeed; it also checks the SphereX handoff, deployer operator removal, adapter ownership and fee destination. archive handoff receipts separately; bootstrap inventory isn't rewritten.

## live Ink Sepolia

**real transactions on chain `763373`.** run from the `release/ink` repo root. use one terminal for the relay, one for deployment. run blocks in order; stop on any error. no impersonation, balance overrides, or mainnet Safe handoff.

### 1. prepare inputs

- [ ] keep existing values and add the missing fields to repo-root `.env`:

```dotenv
INK_RPC_TOKEN=
INK_DEPLOYER=
INK_FEE_RECIPIENT=
INK_ACCOUNT=
INK_SANCTIONS_SNAPSHOT=
# optional explorer key
INK_BLOCKSCOUT_API_KEY=
# optional extra testnet executor in step 6; EOA or deployed Safe
INK_FOUNDATION_SAFE=
```

`INK_ACCOUNT`: Foundry keystore alias, not an address/key. `INK_SANCTIONS_SNAPSHOT`: path inside this repo to a reviewed snapshot JSON; store it under ignored `deployments/ink/config/`.

- [ ] snapshot ready: `schemaVersion: 1`, `sourceChainId: 1`, `fixture: false`, actual `sourceOracle`, `sourceBlockNumber`, `sourceBlockHash`, and `addresses` (1–10,000 sorted, unique, nonzero addresses). confirm source, completeness and freshness. don't relabel the rehearsal fixture or seed from the retired Chainalysis feed. **no approved snapshot yet? stop here.** the source subgraph URL alone isn't a snapshot.
- [ ] keep the deployment settings: **500 bps**, fees paid directly to `INK_FEE_RECIPIENT`, no fee-forwarder contract. deployer funded with real Ink Sepolia ETH.
- [ ] commit the reviewed deployment changes before preparing a live run:

```sh
(
  set -e
  git add -- foundry.toml script/ink script/mock/MockArchControllerOwner.sol test/ink
  git diff --cached --stat
  git commit -m "Prepare Ink deployment and live Sepolia checklist"
)
```

skip this block if already committed. don't commit `.env`, snapshots, runs or broadcast/cache files.

### 2. start authenticated RPC — terminal A

```sh
set -a
source .env
set +a
node script/ink/rpc-relay.mjs 763373
```

check: **`LIVE Ink RPC relay`**, port `8549`, chain `763373`. leave it running. it adds the bearer token to `https://rpc.wildcat.finance/763373`; **this is not Anvil**. it has no signer and only forwards already-signed transactions.

### 3. connect and check signer — terminal B

```sh
set -a
source .env
set +a
export FOUNDRY_PROFILE=ink
export INK_RPC_URL=http://127.0.0.1:8549
: "${INK_ACCOUNT:?set INK_ACCOUNT in .env}"
: "${INK_DEPLOYER:?set INK_DEPLOYER in .env}"
: "${INK_FEE_RECIPIENT:?set INK_FEE_RECIPIENT in .env}"
: "${INK_SANCTIONS_SNAPSHOT:?set INK_SANCTIONS_SNAPSHOT in .env}"
cast chain-id --rpc-url "$INK_RPC_URL"
cast rpc web3_clientVersion --rpc-url "$INK_RPC_URL"
cast balance "$INK_DEPLOYER" --ether --rpc-url "$INK_RPC_URL"
```

check: chain `763373`, client **does not contain `anvil`**, funded deployer. local relay address is expected.

- [ ] if the keystore alias doesn't exist yet, import once using hidden prompts. never paste the key into `.env` or a command argument:

```sh
cast wallet import "$INK_ACCOUNT" --interactive
```

- [ ] check the signer and inputs; this sends no transactions:

```sh
(
  set -e
  INK_SIGNER="$(cast wallet address --account "$INK_ACCOUNT")"
  export INK_SIGNER
  node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readJson, validateConfig, rpcClient, checkEndpoint } from './script/ink/inventory.mjs';
await checkEndpoint({ mode: 'live', chainId: 763373 }, rpcClient(process.env.INK_RPC_URL), process.env.INK_RPC_URL);
assert.equal(process.env.INK_SIGNER.toLowerCase(), process.env.INK_DEPLOYER.toLowerCase(), 'wrong keystore');
validateConfig({ ...readJson('script/ink/fixtures/testnet-rehearsal.json').value,
  mode: 'live', deployer: process.env.INK_DEPLOYER, feeRecipient: process.env.INK_FEE_RECIPIENT,
  sanctionsSnapshot: process.env.INK_SANCTIONS_SNAPSHOT }, readJson(process.env.INK_SANCTIONS_SNAPSHOT).value);
assert.equal(execFileSync('git', ['status', '--porcelain', '--untracked-files=all', '--', 'src', 'script/ink',
  'script/mock/MockArchControllerOwner.sol', 'test/ink', 'foundry.toml', '.gitmodules'], { encoding: 'utf8' }).trim(), '', 'commit deployment changes first');
console.log('signer and snapshot checks passed');
NODE
  node script/ink/ink.mjs check
  node --test test/ink/*.test.mjs
)
```

check: signer/snapshot checks, build/size checks and all Node tests pass. these checks validate snapshot format, not the source's accuracy.

### 4. make a fresh live config

```sh
export INK_RUN="deployments/ink/runs/sepolia-live-$(date -u +%Y%m%dT%H%M%SZ)"
export INK_CONFIG="deployments/ink/config/$(basename "$INK_RUN").json"
mkdir -p deployments/ink/config
(
  set -eC
  test "$(cast chain-id --rpc-url "$INK_RPC_URL")" = 763373
  ink_nonce="$(cast nonce "$INK_DEPLOYER" --block pending --rpc-url "$INK_RPC_URL")"
  test "$ink_nonce" = "$(cast nonce "$INK_DEPLOYER" --block latest --rpc-url "$INK_RPC_URL")"
  jq --arg deployer "$INK_DEPLOYER" --arg recipient "$INK_FEE_RECIPIENT" \
    --arg snapshot "$INK_SANCTIONS_SNAPSHOT" --argjson nonce "$ink_nonce" \
    '.mode = "live" | .deployer = $deployer | .feeRecipient = $recipient |
     .expectedNonce = $nonce | .deployFeeRecipient = false | .protocolFeeBips = 500 |
     .sanctionsSnapshot = $snapshot' script/ink/fixtures/testnet-rehearsal.json > "$INK_CONFIG"
  jq . "$INK_CONFIG"
)
```

check: `live`, `763373`, correct deployer/fee recipient, `500`, forwarder `false`, approved snapshot path. a pending transaction makes this block stop; let it settle first. keep `INK_RUN`/`INK_CONFIG` values for recovery. don't send other deployer transactions until step 5 finishes.

### 5. deploy, collect and verify

- [ ] run **each command separately**, only after the previous one succeeds. `run` prompts for the keystore password and broadcasts:

```sh
node script/ink/ink.mjs prepare "$INK_CONFIG" "$INK_RUN"
```

```sh
node script/ink/ink.mjs run "$INK_RUN" --broadcast --account "$INK_ACCOUNT"
```

```sh
node script/ink/ink.mjs collect "$INK_RUN"
```

don't edit source/config/snapshot between these commands. if `collect` says `insufficient confirmations`, wait for 12 blocks including the last receipt block, then retry **only `collect`**.

- [ ] check the saved results:

```sh
jq '{status, mode, chainId, contracts: (.contracts | length), authorities}' "$INK_RUN/inventory.json"
jq -s 'sort_by(.finishedAt) | last | {status, counts, error}' "$INK_RUN"/verification-*.json
```

check: inventory `confirmed-bootstrap`, `live`, `763373`, **13 contracts**; ArchController owner is the helper, version `"2"`, sole executor is the deployer. explorer report: `complete`, **10 verified**, **0 failed**, **3 bytecode-only** stores. SphereX and sanctions owners remain the deployer.

- [ ] archive the run directory and `broadcast/DeployInk.s.sol/763373/` privately. bootstrap is complete, not app/keeper launch readiness.

**recovery — don't redeploy:**

- explorer failed and `inventory.json` exists: `node script/ink/ink.mjs verify "$INK_RUN"`. then repeat the result checks. don't rerun `collect`.
- broadcast interrupted and `transaction-plan.json` exists: `node script/ink/ink.mjs resume "$INK_RUN" --broadcast --account "$INK_ACCOUNT"`, then `collect`. keep the original run, source/config, signer and Forge cache.
- missing plan, reverted transaction, nonce drift or changed source: stop and reconcile. never start a fresh deployment over a partial broadcast.

### continuation: defer rejected sanctions seeding

only for Ink Sepolia stopped after the first three CREATEs. this keeps all other calls, including the helper handoff and public borrower registration. the list stays empty; the 137-address snapshot remains a pending task, not a successful seed.

- [ ] use the original `v2-protocol-ink` checkout on `release/ink`, not the diagnostic clone. rehearse the continuation first; commit the reviewed changes before live preparation.
- [ ] keep the old run, broadcast and cache. don't resume the old seeding plan after starting this continuation.
- [ ] reuse the live relay on port `8549` (start it with step 2 if needed). leave Anvil alone. load this checkout's `.env` and select the interrupted live run explicitly:

```sh
set -a
source .env
set +a
export FOUNDRY_PROFILE=ink
export INK_RPC_URL=http://127.0.0.1:8549
export INK_PARENT_RUN=deployments/ink/runs/sepolia-live-20261013T234116Z
export INK_RUN="deployments/ink/runs/sepolia-continuation-$(date -u +%Y%m%dT%H%M%SZ)"
export INK_CONFIG="deployments/ink/config/$(basename "$INK_RUN").json"
(
  set -eC
  test "$(git branch --show-current)" = release/ink
  : "${INK_ACCOUNT:?set INK_ACCOUNT in .env}"
  jq -e '.mode == "live" and .chainId == 763373 and .expectedNonce == 1' \
    "$INK_PARENT_RUN/config.original.json" > /dev/null
  jq --arg snapshot "$INK_PARENT_RUN/snapshot.original.json" \
    '.expectedNonce += 3 | .sanctionsSnapshot = $snapshot' \
    "$INK_PARENT_RUN/config.original.json" > "$INK_CONFIG"
)
```

- [ ] run separately, stopping on any failure. preparation checks the live endpoint, three existing contracts and nonce `4`; `run` broadcasts the remaining **21 transactions**:

```sh
node script/ink/ink.mjs prepare-continuation "$INK_CONFIG" "$INK_RUN" "$INK_PARENT_RUN"
```

```sh
node script/ink/ink.mjs run "$INK_RUN" --broadcast --account "$INK_ACCOUNT"
```

```sh
node script/ink/ink.mjs collect "$INK_RUN"
```

if `collect` says `insufficient confirmations`, wait for 12 blocks including the last receipt block, then retry only `collect`.

- [ ] check the results:

```sh
jq '{status, sanctions, contracts: (.contracts | length), receipts: (.receipts | length), endNonce, authorities}' "$INK_RUN/inventory.json"
jq -s 'sort_by(.finishedAt) | last | {status, counts, error}' "$INK_RUN"/verification-*.json
```

check: `confirmed-contracts-sanctions-pending`, `sanctions.observedCount: 0`, helper owns ArchController. without the fee forwarder: **13 contracts, 24 receipts, end nonce 25**. explorer report: `complete`, **10 verified**, **0 failed**, **3 bytecode-only** stores.

- [ ] check `address-changes.json`: first three reused; all ten later addresses changed. use this inventory for downstream configuration.

recovery: interrupted broadcast → `node script/ink/ink.mjs resume "$INK_RUN" --broadcast --account "$INK_ACCOUNT"`, then `collect`. explorer failure with inventory saved → `node script/ink/ink.mjs verify "$INK_RUN"`. keep this continuation's RPC/cache; don't repeat preparation or resume the parent run.

an empty list makes the protocol report everyone unsanctioned. Forta screening is external; this script does not verify its coverage or treat it as a replacement for the protocol's sanctions/escrow behavior. resolve the operator review before attempting the deferred seed.

### 6. optional: authorize the handoff address on testnet

only after collection and verification succeed, including for a continuation. set `INK_FOUNDATION_SAFE` in `.env` to the intended EOA or deployed Safe. this adds a peer executor; **it can administer the helper and remove other executors**. it doesn't transfer helper ownership—the helper has no owner—and doesn't move SphereX/sanctions roles. keep the deployer authorized.

```sh
(
  set -eC
  set -a
  source .env
  set +a
  : "${INK_FOUNDATION_SAFE:?set INK_FOUNDATION_SAFE in .env}"
  test "$(cast chain-id --rpc-url http://127.0.0.1:8549)" = 763373
  export INK_RPC_URL=http://127.0.0.1:8549
  jq -e '.mode == "live" and .chainId == 763373 and (.status == "confirmed-bootstrap" or .status == "confirmed-contracts-sanctions-pending")' "$INK_RUN/inventory.json"
  ink_owner="$(jq -er '.contracts[] | select(.name == "MockArchControllerOwner") | .address' "$INK_RUN/inventory.json")"
  if [ "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_FOUNDATION_SAFE" --rpc-url "$INK_RPC_URL")" != true ]; then
    cast send "$ink_owner" 'authorizeAccount(address)' "$INK_FOUNDATION_SAFE" \
      --account "$INK_ACCOUNT" --from "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL" --json > "$INK_RUN/testnet-executor-authorization-$(date -u +%Y%m%dT%H%M%SZ).json"
  fi
  test "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_FOUNDATION_SAFE" --rpc-url "$INK_RPC_URL")" = true
  test "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL")" = true
  cast call "$ink_owner" 'getAuthorizedAccounts()(address[])' --rpc-url "$INK_RPC_URL"
)
```

check: executor list contains deployer and handoff address. save the authorization receipt with the run; bootstrap inventory deliberately stays unchanged. a deployed Safe must make calls through Safe transactions, not an owner EOA calling directly. don't use `returnOwnership()`; it removes the helper from the ArchController ownership path and breaks public testnet registration.

before app/market rollout: exercise real market/wrapper flows and wire the sanctions keeper, protocol subgraph, SDK and app. those are separate from this deployment.

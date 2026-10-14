# Ink deployment checklist

run from the `release/ink` repo root. stop on a failed command. existing Sepolia deployment is complete; use its saved run for later administration, not the fresh-deployment steps below.

<a id="live-ink-sepolia"></a>

## 1. inputs

- [ ] set `.env`; keep existing credentials. chain: `763373` Sepolia or `57073` mainnet. mode: `rehearsal` or `live`.

```dotenv
INK_CHAIN_ID=763373
INK_MODE=rehearsal
INK_DEPLOYER=
INK_FEE_RECIPIENT=
INK_RPC_TOKEN=
INK_ACCOUNT=
INK_SANCTIONS_SNAPSHOT=
# live verification: Blockscout Pro key
INK_BLOCKSCOUT_API_KEY=
# Sepolia handoff: destination address and its keystore alias
INK_HANDOFF_ADDRESS=
INK_HANDOFF_ACCOUNT=
```

`INK_ACCOUNT` is the deployer's keystore alias. import missing keystores with `cast wallet import ALIAS --interactive`. the handoff wallet needs its own alias.

rehearsal snapshot: `script/ink/fixtures/sanctions.json`, or the reviewed real snapshot to exercise its actual size. live: reviewed non-fixture JSON under `deployments/ink/config/`; never seed from the retired Chainalysis feed. [snapshot format](./fixtures/sanctions.json).

- [ ] load inputs and run local checks. commit reviewed source before live preparation.

```sh
set -a
source .env
set +a
export FOUNDRY_PROFILE=ink
node script/ink/ink.mjs check
node --test test/ink/*.test.mjs
forge test --offline
git status --short
```

check: tests/build/size checks pass. keep `.env`, keystores, snapshots and run data out of the commit.

## 2. RPC

- [ ] terminal A — choose one. **rehearsal** forks latest:

```sh
set -a; source .env; set +a
anvil --host 127.0.0.1 --port 8548 --network optimism --chain-id "$INK_CHAIN_ID" \
  --fork-url "https://rpc.wildcat.finance/$INK_CHAIN_ID" \
  --fork-header "Authorization: Bearer ${INK_RPC_TOKEN:?set INK_RPC_TOKEN}"
```

**live** starts the authenticated relay:

```sh
set -a; source .env; set +a
node script/ink/rpc-relay.mjs "$INK_CHAIN_ID"
```

- [ ] terminal B — connect and check the chain/client:

```sh
set -a; source .env; set +a
export FOUNDRY_PROFILE=ink
case "$INK_MODE" in
  rehearsal) export INK_RPC_URL=http://127.0.0.1:8548 ;;
  live) export INK_RPC_URL=http://127.0.0.1:8549 ;;
  *) return 1 ;;
esac
test "$(cast chain-id --rpc-url "$INK_RPC_URL")" = "$INK_CHAIN_ID"
cast rpc web3_clientVersion --rpc-url "$INK_RPC_URL"
```

check: `anvil` only for rehearsal. the live relay prints `LIVE Ink RPC relay` and uses port `8549`.

- [ ] rehearsal only — impersonate/fund the deployer on Anvil:

```sh
cast rpc anvil_impersonateAccount "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL"
cast rpc anvil_setBalance "$INK_DEPLOYER" 0x8ac7230489e80000 --rpc-url "$INK_RPC_URL"
```

live only: `cast wallet address --account "$INK_ACCOUNT"` must match `INK_DEPLOYER`; check its balance with `cast balance "$INK_DEPLOYER" --ether --rpc-url "$INK_RPC_URL"`.

## 3. fresh config

- [ ] create a new run/config. defaults: **500 bps, direct fee receipt, no forwarder**.

```sh
export INK_RUN="deployments/ink/runs/$INK_MODE-$INK_CHAIN_ID-$(date -u +%Y%m%dT%H%M%SZ)"
export INK_CONFIG="deployments/ink/config/$(basename "$INK_RUN").json"
mkdir -p deployments/ink/config
(
  set -eC
  ink_nonce="$(cast nonce "$INK_DEPLOYER" --block pending --rpc-url "$INK_RPC_URL")"
  test "$ink_nonce" = "$(cast nonce "$INK_DEPLOYER" --block latest --rpc-url "$INK_RPC_URL")"
  jq --arg mode "$INK_MODE" --argjson chain "$INK_CHAIN_ID" --argjson nonce "$ink_nonce" \
    --arg deployer "$INK_DEPLOYER" --arg recipient "$INK_FEE_RECIPIENT" --arg snapshot "$INK_SANCTIONS_SNAPSHOT" \
    '.mode=$mode | .chainId=$chain | .expectedNonce=$nonce | .deployer=$deployer |
     .feeRecipient=$recipient | .sanctionsSnapshot=$snapshot | .protocolFeeBips=500 | .deployFeeRecipient=false' \
    script/ink/fixtures/testnet-rehearsal.json > "$INK_CONFIG"
  jq . "$INK_CONFIG"
)
```

check: intended mode/chain, signer, fee recipient and snapshot. keep `INK_RUN`/`INK_CONFIG`; don't edit source/config or use the deployer elsewhere until collection finishes.

## 4. prepare

```sh
node script/ink/ink.mjs prepare "$INK_CONFIG" "$INK_RUN"
```

## 5. deploy and collect

- [ ] broadcast with the matching signer:

```sh
case "$INK_MODE" in
  rehearsal) node script/ink/ink.mjs run "$INK_RUN" --broadcast --unlocked ;;
  live) node script/ink/ink.mjs run "$INK_RUN" --broadcast --account "$INK_ACCOUNT" ;;
  *) return 1 ;;
esac
```

- [ ] collect, then inspect:

```sh
node script/ink/ink.mjs collect "$INK_RUN"
jq '{status, mode, chainId, contracts: (.contracts|length), authorities}' "$INK_RUN/inventory.json"
jq -s 'sort_by(.finishedAt)|last|{status, counts, error}' "$INK_RUN"/verification-*.json
```

check: `confirmed-bootstrap`; 13 contracts on Sepolia or 12 on mainnet. Sepolia's helper owns ArchController and initially authorizes only the deployer. live verification: `complete`, zero failed, three `bytecode-only`; Anvil: `skipped-rehearsal`. wait/retry `collect` if confirmations are insufficient. archive the run, broadcast and cache privately.

- [ ] rehearsal: exercise market/wrapper flows and the real sanctions payload. the deployment creates no sample markets. repeat this checklist with `57073` before mainnet deployment.

## 6. testnet executor handoff

use the collected run. `INK_HANDOFF_ADDRESS` is the destination EOA; `INK_HANDOFF_ACCOUNT` is its keystore alias. this keeps ArchController owned by the helper and retains the deployer for now.

- [ ] authorize from the deployer, then sign the control proof from the destination. the proof reasserts the existing owner.

```sh
(
  set -eC
  set -a; source .env; set +a
  export INK_RPC_URL=http://127.0.0.1:8549
  : "${INK_HANDOFF_ADDRESS:?set destination address}" "${INK_HANDOFF_ACCOUNT:?set destination keystore alias}"
  test "$(cast chain-id --rpc-url "$INK_RPC_URL")" = 763373
  test "$(cast to-check-sum-address "$INK_HANDOFF_ADDRESS")" != "$(cast to-check-sum-address "$INK_DEPLOYER")"
  test "$(cast code "$INK_HANDOFF_ADDRESS" --rpc-url "$INK_RPC_URL")" = 0x
  jq -e '.mode=="live" and .chainId==763373' "$INK_RUN/inventory.json"
  ink_owner="$(jq -er '.contracts[]|select(.name=="MockArchControllerOwner")|.address' "$INK_RUN/inventory.json")"
  ink_arch="$(jq -er '.contracts[]|select(.name=="WildcatArchController")|.address' "$INK_RUN/inventory.json")"
  test "$(cast call "$ink_arch" 'owner()(address)' --rpc-url "$INK_RPC_URL")" = "$ink_owner"
  test "$(cast call "$ink_owner" 'archController()(address)' --rpc-url "$INK_RPC_URL")" = "$ink_arch"
  if [ "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_HANDOFF_ADDRESS" --rpc-url "$INK_RPC_URL")" != true ]; then
    cast send "$ink_owner" 'authorizeAccount(address)' "$INK_HANDOFF_ADDRESS" --account "$INK_ACCOUNT" \
      --from "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL" --json > "$INK_RUN/testnet-executor-authorization-$(date -u +%Y%m%dT%H%M%SZ).json"
  fi
  ink_proof="$(cast calldata 'transferOwnership(address)' "$ink_owner")"
  ink_receipt="$INK_RUN/testnet-executor-proof-$(date -u +%Y%m%dT%H%M%SZ).json"
  cast send "$ink_owner" 'executeProtocolAction(address,bytes)' "$ink_arch" "$ink_proof" \
    --account "$INK_HANDOFF_ACCOUNT" --from "$INK_HANDOFF_ADDRESS" --rpc-url "$INK_RPC_URL" --json > "$ink_receipt"
  jq -e '.status=="0x1"' "$ink_receipt"
  test "$(cast call "$ink_arch" 'owner()(address)' --rpc-url "$INK_RPC_URL")" = "$ink_owner"
  test "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL")" = true
  cast call "$ink_owner" 'getAuthorizedAccounts()(address[])' --rpc-url "$INK_RPC_URL"
)
```

check: successful proof, both executors, helper still owns ArchController. a Safe destination must execute through its Safe transaction instead of the EOA command above.

later, only when retiring the deployer's helper access:

```sh
(
  set -eC
  set -a; source .env; set +a
  export INK_RPC_URL=http://127.0.0.1:8549
  : "${INK_HANDOFF_ADDRESS:?set destination address}" "${INK_HANDOFF_ACCOUNT:?set destination keystore alias}"
  test "$(cast chain-id --rpc-url "$INK_RPC_URL")" = 763373
  test "$(cast to-check-sum-address "$INK_HANDOFF_ADDRESS")" != "$(cast to-check-sum-address "$INK_DEPLOYER")"
  ink_owner="$(jq -er '.contracts[]|select(.name=="MockArchControllerOwner")|.address' "$INK_RUN/inventory.json")"
  ink_arch="$(jq -er '.contracts[]|select(.name=="WildcatArchController")|.address' "$INK_RUN/inventory.json")"
  test "$(cast call "$ink_arch" 'owner()(address)' --rpc-url "$INK_RPC_URL")" = "$ink_owner"
  test "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_HANDOFF_ADDRESS" --rpc-url "$INK_RPC_URL")" = true
  cast send "$ink_owner" 'deauthorizeAccount(address)' "$INK_DEPLOYER" --account "$INK_HANDOFF_ACCOUNT" \
    --from "$INK_HANDOFF_ADDRESS" --rpc-url "$INK_RPC_URL" --json > "$INK_RUN/testnet-executor-removal-$(date -u +%Y%m%dT%H%M%SZ).json"
  test "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL")" = false
  test "$(cast call "$ink_owner" 'authorizedAccounts(address)(bool)' "$INK_HANDOFF_ADDRESS" --rpc-url "$INK_RPC_URL")" = true
)
```

this only removes helper access; SphereX and sanctions roles need separate transfer before retiring the EOA entirely.

normal admin calls use `executeProtocolAction`. legacy scripts can still take ownership with `returnOwnership()` and restore it with `ArchController.transferOwnership(helper)`; public registration pauses until restoration.

## 7. mainnet Safe handoff

- [ ] select the collected mainnet run/config. add `INK_FOUNDATION_SAFE`, `INK_SANCTIONS_UPDATER` and `INK_TREASURY_RECIPIENT` to `.env`, then reload. check the Safe's implementation, owners, threshold and modules. an independent updater may retain list ownership.

```sh
set -a; source .env; set +a
export FOUNDRY_PROFILE=ink INK_CANDIDATE="$INK_RUN/candidate.json"
cast call "$INK_FOUNDATION_SAFE" 'getOwners()(address[])' --rpc-url "$INK_RPC_URL"
cast call "$INK_FOUNDATION_SAFE" 'getThreshold()(uint256)' --rpc-url "$INK_RPC_URL"
```

- [ ] simulate nomination, then broadcast the same command with the original deployer signer:

```sh
forge script script/ink/HandoffInk.s.sol:HandoffInk --sig 'nominate()' --offline \
  --rpc-url "$INK_RPC_URL" --sender "$INK_DEPLOYER" --account "$INK_ACCOUNT"
```

after checking the simulation:

```sh
forge script script/ink/HandoffInk.s.sol:HandoffInk --sig 'nominate()' --offline \
  --rpc-url "$INK_RPC_URL" --sender "$INK_DEPLOYER" --account "$INK_ACCOUNT" --broadcast --slow
```

- [ ] after the engine's pending admin timestamp, execute the printed calls from the Safe: ArchController `acceptSphereXAdminRole()`, `changeSphereXOperator(safe)`, then engine `acceptDefaultAdminTransfer()`.
- [ ] simulate `finish()`, then repeat with `--broadcast --slow`:

```sh
forge script script/ink/HandoffInk.s.sol:HandoffInk --sig 'finish()' --offline \
  --rpc-url "$INK_RPC_URL" --sender "$INK_DEPLOYER" --account "$INK_ACCOUNT"
```

```sh
forge script script/ink/HandoffInk.s.sol:HandoffInk --sig 'finish()' --offline \
  --rpc-url "$INK_RPC_URL" --sender "$INK_DEPLOYER" --account "$INK_ACCOUNT" --broadcast --slow
```

check: `finish()` succeeds; Safe owns ArchController/adapter and both SphereX admin/operator roles; old engine operator is removed; ArchController retains sender-adder; mirror owner is the chosen updater. direct fee recipients cannot be changed here. archive handoff receipts.

on an Anvil rehearsal only: impersonate/fund the Safe, use `--unlocked` instead of `--account`, and advance time past the one-hour delay. real Safe signatures still need a separate test.

## recovery

- explorer failure after inventory exists: `node script/ink/ink.mjs verify "$INK_RUN"`.
- interrupted broadcast with saved plan: `node script/ink/ink.mjs resume "$INK_RUN" --broadcast --account "$INK_ACCOUNT"`, then `collect`. rehearsal uses `--unlocked`.
- changed source, missing plan/cache, reverted transactions or nonce drift: reconcile before continuing. preserve the original run and RPC endpoint.

### continuation: defer rejected sanctions seeding

only for Sepolia stopped after the first three CREATEs. rehearse first. set `INK_PARENT_RUN` to that interrupted run; keep its original source evidence, broadcast and cache.

```sh
export INK_RUN="deployments/ink/runs/sepolia-continuation-$(date -u +%Y%m%dT%H%M%SZ)"
export INK_CONFIG="deployments/ink/config/$(basename "$INK_RUN").json"
(
  set -eC
  : "${INK_PARENT_RUN:?set the interrupted run}"
  jq --arg snapshot "$INK_PARENT_RUN/snapshot.original.json" \
    '.expectedNonce+=3 | .sanctionsSnapshot=$snapshot' "$INK_PARENT_RUN/config.original.json" > "$INK_CONFIG"
)
node script/ink/ink.mjs prepare-continuation "$INK_CONFIG" "$INK_RUN" "$INK_PARENT_RUN"
```

then use step 5 to broadcast and collect. check `confirmed-contracts-sanctions-pending`, count `0`, and `address-changes.json`. the known 137-address run used 21 new transactions: 13 contracts, 24 combined receipts, end nonce 25. the original snapshot remains pending. never resume the parent after starting its continuation.

before application launch: seed and maintain the sanctions mirror, exercise user flows, and finish subgraph/SDK/app integration. transaction screening is not a substitute for the protocol's sanctions state.

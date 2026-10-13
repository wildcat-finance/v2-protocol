# Ink rehearsal checklist

run from the `release/ink` repo root, one block at a time. stop on errors. this sends transactions only to local Anvil; don't load a real private key.

this first pass uses the shipped two-address sanctions fixture. it tests the real mirror contracts, not the source subgraph or keeper. no snapshot export is needed for this pass.

## 1. start the fork — terminal A

- [ ] fork the latest Ink Sepolia block; leave this terminal running:

```sh
anvil --host 127.0.0.1 --port 8548 --network optimism --chain-id 763373 \
  --fork-url https://rpc.wildcat.finance/763373
```

check: Anvil is listening on `127.0.0.1:8548`. no block number to choose. leave code-size and gas limits alone; don't add `--hardfork cancun`.

## 2. connect and check tools — terminal B

use this terminal for everything below. requires Node 22+, `jq`, Foundry with solc 0.8.25, and initialized pinned submodules.

- [ ] select the local fork and run the checks:

```sh
export FOUNDRY_PROFILE=ink
export INK_RPC_URL=http://127.0.0.1:8548
cast chain-id --rpc-url "$INK_RPC_URL"
cast rpc web3_clientVersion --rpc-url "$INK_RPC_URL"
node script/ink/ink.mjs check
node --test test/ink/inventory.test.mjs
```

check: chain `763373`, client contains `anvil`, build/size checks succeed, nine inventory tests pass. the known `fuzz_runs` warning isn't a failed build.

## 3. choose the accounts

- [ ] fill in your deployment EOA and fee destination / Safe, then unlock/fund the deployer **on the fork only**:

```sh
export INK_DEPLOYER=''
export INK_FEE_RECIPIENT=''
: "${INK_DEPLOYER:?fill in the deployer address}"
: "${INK_FEE_RECIPIENT:?fill in the fee recipient address}"
cast rpc anvil_impersonateAccount "$INK_DEPLOYER" --rpc-url "$INK_RPC_URL"
cast rpc anvil_setBalance "$INK_DEPLOYER" "$(cast to-hex "$(cast to-wei 10 ether)")" --rpc-url "$INK_RPC_URL"
cast balance "$INK_DEPLOYER" --ether --rpc-url "$INK_RPC_URL"
```

check: balance is `10` ETH. this changes no live balance and needs no keystore. the fee address needn't have Safe code for the Sepolia bootstrap; the mainnet handoff below does require it.

## 4. make the rehearsal config

- [ ] generate a fresh config. edit the two fee settings in this command if needed: `false` pays the destination directly; `true` adds the fee forwarder. `1000` bps is a **rehearsal value**, not an approved live fee.

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
     .expectedNonce = $nonce | .deployFeeRecipient = false | .protocolFeeBips = 1000' \
    script/ink/fixtures/testnet-rehearsal.json > "$INK_CONFIG"
)
jq . "$INK_CONFIG"
```

check: your addresses, chain `763373`, `mode: "rehearsal"`, the fork's nonce, your fee settings, and `script/ink/fixtures/sanctions.json`. don't replace the nonce with zero.

## 5. deploy and collect

- [ ] run each command only after the previous one succeeds:

```sh
node script/ink/ink.mjs prepare "$INK_CONFIG" "$INK_RUN"
node script/ink/ink.mjs run "$INK_RUN" --broadcast --unlocked
node script/ink/ink.mjs collect "$INK_RUN"
```

don't edit source/config/snapshot or send other deployer transactions between `prepare` and `collect`.

- [ ] inspect the result:

```sh
jq '{status, mode, chainId, contracts: (.contracts | length), authorities}' "$INK_RUN/inventory.json"
```

check: `confirmed-bootstrap`, `rehearsal`, `763373`, **13 contracts** (14 with a fee forwarder). `archOwner` is the testnet helper, not the EOA/Safe. sanctions owners and SphereX admin/operator are still the deployer. `collect` checks receipts, deployed code, bindings, fees and initial sanctions membership.

if broadcast was interrupted, keep Anvil running and preserve the run, source/config and Forge cache. **only if `transaction-plan.json` exists**, try:

```sh
node script/ink/ink.mjs resume "$INK_RUN" --broadcast --unlocked
node script/ink/ink.mjs collect "$INK_RUN"
```

otherwise stop and reconcile; don't restart `run` over a partial deployment. an intentional fresh attempt needs a fresh Anvil fork and a new config/run. keep the old evidence.

## 6. smoke checks — after collection

- [ ] run the isolated contract-flow tests against the fork:

```sh
forge test --offline --fork-url "$INK_RPC_URL" --match-path 'test/ink/*.t.sol' -vv
```

check: **11 tests pass**. these deploy isolated test contracts for open/fixed markets, wrappers, sanctions and role transfers; they don't create demo markets in your collected deployment. the known Solar `unresolved symbol locals` diagnostic can appear despite passing tests.

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

## 7. later: mainnet-fork handoff rehearsal

- [ ] stop Anvil with Ctrl-C. repeat steps 1–6 with `57073` in both the fork URL and `--chain-id`; read the chain checks and evidence path as `57073` too. keep port `8548`; use a fresh config/run. expect **12 contracts** (13 with a forwarder), no testnet helper, and the EOA as initial `archOwner`.
- [ ] fill in the Foundation Safe; check that it exists on this fork and has the expected owners/threshold:

```sh
export INK_FOUNDATION_SAFE=''
: "${INK_FOUNDATION_SAFE:?fill in the Safe address}"
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

## not a live deployment checklist

- [ ] before any public-chain deployment: approve fees, export/verify a complete replacement-source sanctions snapshot, commit the reviewed source, and use `mode: live` with a keystore/hardware signer. no impersonation or fixture data.
- [ ] before opening markets: verify real market/wrapper flows, explorer sources, keeper synchronization, protocol subgraphs, SDK and app. a source subgraph alone doesn't update the onchain mirror.

# Ink v2.0 deployment runbook

start with the [standalone checklist](./CHECKLIST.md) for a fresh Anvil rehearsal or live Ink Sepolia deployment. already stopped at sanctions seeding? use [the live continuation section](./CHECKLIST.md#continuation-defer-rejected-sanctions-seeding) directly. this runbook covers the deployment model and background details.

deploys a fresh v2.0 protocol and v2.1 ERC-4626 wrapper factory on Ink and Ink Sepolia. [InkDeployment.sol](./InkDeployment.sol) is the deployment helper; [DeployInk.s.sol](./DeployInk.s.sol) has two thin entrypoints.

an interrupted Ink Sepolia bootstrap can explicitly defer seeding after its first three CREATEs. `prepare-continuation CONFIG RUN PARENT` archives the parent evidence and checks its current receipts, code and nonce. [ContinueInk.s.sol](./ContinueInk.s.sol) reuses those contracts, regenerates the remaining deployment from the next nonce, and keeps the normal helper handoff/public registration. the [checklist continuation section](./CHECKLIST.md#continuation-defer-rejected-sanctions-seeding) covers execution.

this is a new plan, not an edit to the old broadcast. it has a separate Forge cache, records changed addresses, and collects both old and new receipts. its status is `confirmed-contracts-sanctions-pending`, never `confirmed-bootstrap`; the original snapshot is retained for later seeding. it doesn't enable a mainnet empty-list mode or relax ordinary resume checks. explorer verification accepts the receipt-backed pending inventory without claiming sanctions were loaded.

## source and build boundary

| Component | Pinned source |
| --- | --- |
| Core, hooks, lens, wrapper | `v2.1.0`, `c7be4039f8f383a9dda4e45f63331c17d63f9ed9` |
| Testnet owner helper, version `2` | Verbatim from `release/v2.5`, `05165ad4c4020c1400048680b85b3585f84e8527` |
| SphereX engine/interface, sanctions adapter/mirror, open-access provider, 130 SphereX patterns | Plasma `1bc514b1b0b903b1e94ca8046741fa8c9d367294` |
| Optional fee forwarder | `wildcat-finance/fee-recipient-contract@ac73bda3642c9a7c8de64e39856b31af53f06068`, `src/WildcatFeeRecipient.sol` |
| Compiler | Solidity 0.8.25, Cancun, via IR, optimizer 50,000 runs, metadata bytecode hash disabled |

all pre-existing `src/` files match v2.1. the Plasma imports keep their source and names, including `ChainalysisProxy` and `WildcatCopyOfChainalysisList`. the fee forwarder uses the protocol's existing `LibERC20`; the methods it calls match the original library. don't import Plasma's 730-day fixed-term change or its lens changes. V2.1 keeps the 365-day maximum.

use `FOUNDRY_PROFILE=ink`. the script checks the tag, core source, dependency gitlinks, Plasma imports, the helper's pinned SHA-256, compiler settings, contract sizes, initcode-store sizes, and SphereX storage layout. it doesn't update dependencies. initialize the pinned submodules, including OpenZeppelin's ERC-4626 test submodule. the explicit remapping uses that copy because v2.1's top-level ERC-4626 test dependency is unpopulated.

the engine is unchanged. verification reads its private rules/sender/pattern mappings through Foundry, using slots checked against the compiler artifact. changing the engine/OZ pins means revisiting that.

Forge 1.7.1 can print a Solar parser diagnostic about the existing `locals` return variable in `SphereXProtectedRegisteredBase.sol`. solc builds and focused tests pass despite it. Ink build-time lint is disabled; this is fine.

the pinned ERC-4626 harness has two inherited `testFail_*` cases. Forge 1.7.1 rejects those names before running them. the remaining wrapper tests pass with those two excluded; the harness and contracts are unchanged. this is fine.

## contracts and authority

both profiles deploy an ArchController, SphereX engine, populated sanctions mirror, sanctions adapter, sentinel, three initcode stores, HooksFactory, MarketLens, wrapper factory, and OpenAccessRoleProvider: 12 deployments, or 13 with the fee forwarder. Ink Sepolia adds `MockArchControllerOwner`.

initcode stores contain `STOP || creation bytecode`, not market or hook instances. bootstrap doesn't deploy markets, borrower hooks, per-market wrappers, escrows, or test tokens.

| Authority | Immediately after bootstrap | Later handoff |
| --- | --- | --- |
| ArchController owner | deployer on mainnet; helper on testnet | Foundation Safe on mainnet |
| ArchController SphereX admin/operator | deployer | separate nomination/acceptance and operator assignment |
| Engine default admin/operator | deployer | one-hour delayed admin acceptance, operator grant, deployer renunciation |
| Engine sender-adder | ArchController | must remain ArchController |
| Adapter owner / mirror updater | deployer / deployer | Safe / explicitly selected updater |
| Fee forwarder owner / recipient | deployer / configured recipient | Safe / explicitly selected treasury |

the testnet helper permits public single/batch borrower registration. its constructor takes `(archController, [deployer])`; the deployer is the sole initial executor. verification checks version `2`, the controller binding, and that exact executor list. localhost and chain ID 31337 don't select it; the target profile does. both profiles use the same real sanctions mirror and enabled engine, with no default mock/disabled sanctions mode.

after collection, an executor can call `authorizeAccount(handoffAddress)` to add an EOA or Safe as a peer executor. it can administer protocol targets and add/remove executors; it isn't an ArchController-registered controller. the helper has no transferable owner. keep ArchController owned by the helper for public testnet registration. this delegation doesn't transfer SphereX or sanctions roles; save its receipt separately from bootstrap inventory.

bootstrap adds both templates before transferring ArchController ownership to the helper. later template changes require an executor to call `executeProtocolAction(hooksFactory, encodedHooksFactoryCall)`, encoding the factory's `addHooksTemplate`, `updateHooksTemplateFees`, or `disableHooksTemplate` call. the helper no longer exposes those three selectors directly, and template addition is no longer public. borrower registration calls are unchanged.

executors can `authorizeAccount` / `deauthorizeAccount`; the final executor can't be removed. `returnOwnership()` returns ArchController ownership to the calling executor for recovery. neither operation moves SphereX roles, sanctions ownership, or the fee destination. keep the helper as testnet owner for public registration; `HandoffInk` remains mainnet-only.

`ChainalysisProxy` uses ordinary calls, not delegatecall. its owner can replace or unset the backend; an unset backend returns false. the list owner can add/remove entries. the script checks the nonempty initial snapshot and backend binding. this is still an owner-managed offchain mirror, not an immutable or trustless cross-chain oracle. the core sentinel's adapter address is immutable.

the fee destination is mandatory; `protocolFeeBips` defaults to `500` in the checklist and rehearsal fixtures. fees accrue in markets until `collectFees()` sends available fees to each market's immutable `feeRecipient`.

- `deployFeeRecipient: false`: use the configured address directly. the periodic collection job sends fees from markets to that address; no extra contract or withdrawal is needed.
- `deployFeeRecipient: true`: deploy `WildcatFeeRecipient` and make it the markets' recipient. after collection, its owner or recipient must call `releaseERC20Fees(asset)` to move tokens to the configured destination. this isn't automatic forwarding or a collection scheduler. its owner can change that final destination without changing the markets.

the checklist uses `false`. **existing markets' fee recipients don't follow ArchController ownership.** choose a stable destination before creating markets.

## configuration and sanctions input

[mainnet](./fixtures/mainnet-rehearsal.json) and [testnet](./fixtures/testnet-rehearsal.json) fixtures are rehearsal-only. both use `500` protocol fee bps and exercise the optional fee forwarder; the checklist selects direct receipt instead. their accounts and sanctions entries are test data, not live inputs. keep real configuration under ignored `deployments/ink/config/`.

required fields: `schemaVersion`, `chainId`, `mode` (`rehearsal` or `live`), `deployer`, `expectedNonce`, `deployFeeRecipient`, `feeRecipient`, `protocolFeeBips`, and `sanctionsSnapshot`. paths are relative to the repository. unknown or missing fields are rejected.

the [snapshot schema](./fixtures/sanctions.json) records the Ethereum oracle, source block number/hash, a `fixture` flag, and sorted, unique, nonzero addresses. live mode rejects fixtures. seeding uses batches of 100, with a 10,000-entry input cap. don't truncate a larger list to pass the guard; review the seeding plan. no origination fee is configured.

the operator supplies the provenance fields. the tool doesn't prove the source block or reconstruct the oracle's list. check completeness, removals, source policy, and freshness before signing. RedStone's `isSanctioned(address)` compatibility doesn't establish identical list semantics or events. don't seed from the deprecated Chainalysis feed.

collect bootstrap inventory before transferring mirror ownership to a dedicated updater. that transfer can happen before the Safe exists; the later Safe handoff can leave the updater in place. don't run the worker with the deployment/governance key.

## local checks and offline simulations

use Node 22+ and Foundry with Solidity 0.8.25 already installed. no new npm packages.

preparation checks on 2026-10-13: 25 deployment/helper integration tests and 26 inventory/relay/verification tests pass. both deployment entrypoints complete offline Forge simulation. the helper matches its pinned source byte-for-byte; 14 non-helper creation/runtime bytecodes are unchanged. all 14 possible deployment artifacts pass the code/initcode-size gate; MarketLens is 24,385 bytes, only 191 below EIP-170. the earlier wrapper run passed 96 tests with the two unsupported `testFail_*` cases excluded. none of this proves an RPC-backed broadcast or explorer submission succeeded. the relay's request handler is tested; a socket-backed relay test is blocked by the sandbox's `EPERM` on localhost listeners.

```sh
node script/ink/ink.mjs check
FOUNDRY_PROFILE=ink forge test --offline -vv
node --test test/ink/*.test.mjs
node script/ink/ink.mjs simulate script/ink/fixtures/mainnet-rehearsal.json deployments/ink/runs/mainnet-offline
node script/ink/ink.mjs simulate script/ink/fixtures/testnet-rehearsal.json deployments/ink/runs/testnet-offline
```

run the legacy wrapper check separately:

```sh
FOUNDRY_PROFILE=ink FOUNDRY_TEST=test/vault FOUNDRY_OUT=ir-out FOUNDRY_CACHE_PATH=ir-cache \
  forge test --offline --no-match-test '^testFail_'
```

use a new run directory for every attempt. offline simulation produces an unconfirmed candidate, not deployment inventory. it doesn't replace a fork, gas/fee estimation, or receipt collection.

## pinned fork rehearsals

Ink uses chain ID 57073; Ink Sepolia uses 763373. the public RPCs below come from the [official network information](https://docs.inkonchain.com/general/network-information).

the checklist forks latest. to repeat a specific run instead, set its block number and start the matching fork in its own terminal:

```sh
anvil --host 127.0.0.1 --network optimism --chain-id 57073 --port 8547 \
  --fork-url https://rpc-gel.inkonchain.com \
  --fork-block-number "${INK_MAINNET_FORK_BLOCK:?set a reviewed block}"

anvil --host 127.0.0.1 --network optimism --chain-id 763373 --port 8548 \
  --fork-url https://rpc-gel-sepolia.inkonchain.com \
  --fork-block-number "${INK_TESTNET_FORK_BLOCK:?set a reviewed block}"
```

keep code-size, transaction-gas, and block-gas limits enabled. Cancun is the Solidity build target; Optimism's Anvil hardfork names differ. don't pass `--hardfork cancun` with `--network optimism`.

copy the relevant fixture into the ignored config directory. set `expectedNonce` from the local fork deployer's pending nonce; a common Anvil account may already have transactions on the forked chain. use local test accounts, never a production private key.

```sh
export INK_RPC_URL=http://127.0.0.1:8547
node script/ink/ink.mjs prepare deployments/ink/config/mainnet-rehearsal.json deployments/ink/runs/mainnet-fork
node script/ink/ink.mjs run deployments/ink/runs/mainnet-fork --broadcast --unlocked
node script/ink/ink.mjs collect deployments/ink/runs/mainnet-fork
```

repeat with port 8548 and the testnet profile. `prepare` requires loopback Anvil in rehearsal mode; live mode rejects Anvil. running on Anvil doesn't change the target chain's contracts or ownership rules.

exercise open/fixed market creation, wrapper flows, sanctions hit/clear, and the Safe handoff on the forks. the Solidity tests use the real enabled engine, but bootstrap creates no sample markets. test the other intended borrower/lender flows before accepting the imported pattern set for launch.

## broadcast and inventory

`prepare` freezes source-file hashes, dependency/build commitments, config/snapshot hashes, tool version, nonce, and chain checkpoint. it also archives the original config/snapshot bytes. `run` refuses changed source/config or an existing candidate. Forge simulates before broadcasting; `--slow` sends sequentially. without `--broadcast`, it only simulates.

commit the reviewed deployment source before live preparation; dirty or uncommitted source is rejected. select `mode: live`, real signer/fee inputs, and a verified non-fixture snapshot. use a keystore alias (`--account ALIAS`), Ledger, or Trezor. unlocked accounts are local-rehearsal only. keep private keys and RPC credentials out of JSON and Git.

the live checklist starts `rpc-relay.mjs` on `127.0.0.1:8549`, forwarding to the chosen Ink gateway chain with `INK_RPC_TOKEN`. this is an authenticated live RPC relay, not a fork or signer. it rejects browser requests and unlocked sends. Node, Cast and Forge all use that endpoint; neither credentials nor an extra proxy configuration belong in the run JSON. Forge 1.7.1's [script providers](https://github.com/foundry-rs/foundry/blob/4072e48705af9d93e3c0f6e29e93b5e9a40caed8/crates/script/src/providers.rs) don't consistently carry custom headers, so setting `ETH_RPC_HEADERS` alone isn't sufficient for the whole deployment path.

`collect` requires successful canonical receipts and enough confirmations. it checks every planned transaction against RPC data, nonce continuity, CREATE inputs/addresses, and runtime code hashes, then runs Solidity binding/authority checks at a pinned block. only then does it write `inventory.json`. default depth: 12 blocks for live runs, one for rehearsals. confirmations don't establish L1 finality.

don't use the deployer for other transactions until collection finishes. an unexpected confirmed nonce causes rejection because additional admin actions could invalidate the bootstrap authority snapshot. if other transactions were sent, archive the evidence and reconcile it.

inventory records contract/artifact kinds, constructor arguments, creation/runtime hashes, transaction hashes/blocks, bootstrap authorities, sanctions checkpoint, and source/build commitments. testnet inventory also records the helper source pin, version, and verified executor list. `launchReady` stays false: these checks don't cover worker freshness or consumer rollout. a candidate, dry-run output, Git tag, or address alone doesn't prove deployment.

Git ignores run data. review and archive the complete run directory and relevant Forge broadcast/cache evidence in a private release store. the tool doesn't commit/publish inventory or send SDK/app updates; live source verification publishes contract source to Blockscout. keep RPC URLs out of shared evidence.

## Blockscout source verification

live `collect` saves receipt-backed inventory, then verifies every ordinary deployed contract on the matching [Ink Blockscout explorer](https://docs.inkonchain.com/tools/block-explorers). rehearsal runs write `skipped-rehearsal` and make no explorer requests. source verification is separate from the script's onchain binding/authority checks.

the per-instance endpoints are `https://explorer.inkonchain.com/api/` and `https://explorer-sepolia.inkonchain.com/api/`. [Blockscout supports keyless verification](https://docs.blockscout.com/devs/verification/foundry-verification); an exported `INK_BLOCKSCOUT_API_KEY` is optional. the script passes it through the environment, not command arguments, and redacts it from saved Forge output. no signer is needed for verification.

verification uses recorded constructor bytes, the exact local creation payload, and the Ink compiler settings. it rechecks deployed code and canonical creation receipts before submitting `forge verify-contract --watch`. all contracts are attempted even if one submission fails. each attempt writes a separate `verification-*.json` with the inventory hash, explorer links, output, and per-address results. it doesn't rewrite bootstrap inventory or claim `launchReady`.

the three initcode stores are `STOP || creation bytecode`, not running `WildcatMarket`/hook instances. they are checked against local artifacts and onchain hashes, recorded as `bytecode-only`, and aren't submitted as ordinary Solidity contracts. borrower markets, hook instances, wrappers, and escrows created later aren't part of bootstrap verification.

require report status `complete`, zero failed contracts, and exactly three bytecode-only stores. an explorer outage/indexing delay leaves the deployment and inventory intact, but makes `collect` exit nonzero. retry verification only:

```sh
set -a
source .env
set +a
node script/ink/ink.mjs verify "$INK_RUN"
```

use the deployed chain's `INK_RPC_URL`. this also works for already-collected Ink deployments, after handoff or keeper updates; it doesn't require the deployer's nonce or bootstrap authorities to remain unchanged. use the original contract source/compiler build: changed docs/scripts are fine, changed creation bytecode isn't. keep previous reports. a candidate or offline simulation isn't enough, and neither `run` nor `resume` is a verification retry.

local tests cover arguments, artifact/constructor matching, receipt/code checks, failures/retries, key redaction, and the Anvil skip. actual explorer submission remains untested here: this sandbox can't resolve the compiler-version service used by `forge verify-contract`, even for standard-JSON export.

## interrupted broadcasts

prepared runs from before the helper backport can't use the new source. preserve their evidence and prepare a fresh run. if any transactions were already sent on a rehearsal fork, restart Anvil and generate a fresh config too; don't resume old transactions with new code.

don't rerun deployment after a partial broadcast. if the wrapper saved `transaction-plan.json`, resume with the same run, source/config, Forge cache, signer, and network:

```sh
node script/ink/ink.mjs resume deployments/ink/runs/mainnet-fork --broadcast --unlocked
node script/ink/ink.mjs collect deployments/ink/runs/mainnet-fork
```

for live runs, use the original keystore/hardware signer instead of `--unlocked`. resume checks the candidate and saved transaction-plan hash against Forge's current `run-latest.json`, then uses the cached transactions. it doesn't resimulate or repair state. while a run is pending, don't use the deployer elsewhere or start another deployment on the same entrypoint/chain.

**stop and reconcile receipts and remaining transactions manually** if the process died before saving the plan, the cache was overwritten, a transaction reverted, the nonce changed, or state was altered. the tool can't recover from an old JSON address alone. unit tests cover inventory rejection/recollection after interruption; the actual Forge broadcast/resume path still needs an Anvil rehearsal.

## Foundation Safe handoff

[HandoffInk.s.sol](./HandoffInk.s.sol) is mainnet-only and separate from deployment. review the Safe address, implementation, owners, threshold, and modules. the script's `getThreshold` check only establishes structure; it doesn't authenticate the Safe.

set `FOUNDRY_PROFILE=ink`, `INK_CONFIG`, `INK_CANDIDATE`, and `INK_FOUNDATION_SAFE`. keep the archived config/snapshot unchanged; onchain list membership can change.

1. the EOA calls `HandoffInk.nominate()`: nominate the Safe as ArchController SphereX admin and engine default admin, and grant its engine operator role. the EOA keeps ownership until completion.
2. after the engine's one-hour delay, the Safe calls ArchController `acceptSphereXAdminRole()`, ArchController `changeSphereXOperator(safe)`, and engine `acceptDefaultAdminTransfer()`. nomination prints targets and calldata. read the pending schedule; exactly 3,600 seconds isn't enough at the boundary.
3. set `INK_SANCTIONS_UPDATER` and `INK_TREASURY_RECIPIENT` explicitly. the EOA calls `HandoffInk.finish()` to transfer ArchController/adapter ownership, rotate the updater if the deployer still holds it, update the optional fee forwarder, and renounce the EOA's engine operator role.

run Foundry without `--broadcast` first, then use the reviewed original EOA signer and `--broadcast --slow` for each EOA phase. the Safe must execute its own acceptance calls; never impersonate it on a live chain. this helper can't rotate a direct external fee destination. if an independent updater is already installed, name that updater; only its own authorized action can rotate it.

save handoff receipts. check final/pending owners, both SphereX admin/operator layers, the ArchController sender-adder role, updater, and treasury recipient. bootstrap inventory records the earlier state; handoff doesn't rewrite it or treat a pending role as accepted.

## remaining release gates

- run real broadcasts, interruption/resume, and both Ink fork rehearsals with normal chain constraints. check source publication, gas/fee behavior, SphereX flow coverage, and operator custody.
- approve the live deployer, treasury mode/address, template fee policy, independently checked sanctions snapshot, and dedicated updater custody. fixtures approve none of these.
- implement and monitor the RedStone source indexer/worker: add/remove events, reorg handling, source/list checkpoints, reconciliation, freshness alerts, and recovery. seeding the mirror doesn't make it a live sanctions service.
- finish protocol subgraphs, SDK, app, and operational rollout before opening markets. those consumer changes aren't included here.
- keep existing-chain sanctions migration separate. no interim Ethereum V2.0/V2.1 factories solely for sanctions; V2.5 is the chosen new-market cutover. existing Ethereum markets stay pinned to the old sentinel/oracle. Plasma's mirror source needs its own update.

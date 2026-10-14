# Ink V2 deployment

deploys V2.0 plus the V2.1 ERC-4626 wrapper factory. use [CHECKLIST.md](./CHECKLIST.md) for rehearsal, deployment, recovery and handoff commands.

## current state

Ink Sepolia: deployed and source-verified; both Foundation EOAs are authorized on the testnet helper. the sanctions mirror is empty, with the original snapshot retained for later seeding. SphereX and sanctions administration remain with the deployer. mainnet deployment and consumer rollout are pending.

the local run directory is the address/receipt record. its bootstrap inventory is immutable; later verification and executor-handoff receipts sit alongside it. `launchReady: false` remains intentional until sanctions and consumers are ready.

## source and build

| Component | Source |
| --- | --- |
| Core, hooks, lens, wrapper | `v2.1.0` / `c7be4039` |
| Testnet helper, version `2` | `release/v2.5` / `05165ad4`, verbatim |
| SphereX, sanctions mirror/adapter, open-access provider, 130 patterns | Plasma / `1bc514b1` |
| Optional fee forwarder | `fee-recipient-contract` / `ac73bda3` |

`FOUNDRY_PROFILE=ink`: Solidity 0.8.25, Cancun, via IR, 50,000 optimizer runs, metadata bytecode hash disabled. its formatter follows the V2.5 style; verbatim imports retain their layout. `ink.mjs check` enforces source/dependency pins, compiler settings, sizes and SphereX storage slots. keep submodules at their pinned commits, including OpenZeppelin's ERC-4626 test dependency.

existing V2.1 source and imported contracts keep their original names and behavior. Plasma's unrelated lens and 730-day fixed-term changes are excluded. MarketLens has only 191 bytes of EIP-170 headroom.

## deployed contracts

both chains get ArchController, SphereX engine, sanctions mirror/adapter/sentinel, three initcode stores, HooksFactory and its templates, MarketLens, the wrapper factory and OpenAccessRoleProvider. Sepolia also gets `MockArchControllerOwner`.

without the optional fee forwarder: 12 deployments on mainnet, 13 on Sepolia. the three stores contain `STOP || creation bytecode`; they are recorded as `bytecode-only`. markets, borrower hooks, wrappers and escrows are created later.

## authority and fees

| Authority | After bootstrap | Handoff |
| --- | --- | --- |
| ArchController owner | EOA on mainnet; helper on Sepolia | Safe on mainnet; helper stays on Sepolia |
| Helper executors | deployer | authorize additional EOA/Safe; later remove deployer |
| ArchController SphereX admin/operator | deployer | nominate/accept admin; assign operator |
| Engine admin/operator | deployer | delayed admin acceptance; grant operator and remove deployer |
| Engine sender-adder | ArchController | retain |
| Sanctions adapter / mirror owner | deployer / deployer | governance / selected updater |
| Optional fee-forwarder owner / recipient | deployer / configured treasury | governance / selected treasury |

the replacement helper forwards owner-only calls through `executeProtocolAction(target, calldata)`, including factory registration and hooks-template administration. public borrower registration stays available while the helper owns ArchController. legacy scripts may still use `returnOwnership()` and restore ownership afterward; public registration pauses during that interval. executor removal alone does not retire the deployer's other roles.

fees default to 500 bps; the factory accepts 0–1,000. with `deployFeeRecipient: false`, periodic `collectFees()` calls pay markets' immutable fee recipient directly. with `true`, the forwarder receives those funds and its owner/recipient calls `releaseERC20Fees(asset)`. changing ownership does not redirect existing markets' fees.

## sanctions

both chains use the Plasma-style owner-managed mirror. its adapter can change the backend; the sentinel's adapter address is immutable. snapshots require Ethereum source provenance and 1–10,000 sorted, unique, nonzero addresses. live deployment rejects fixtures. the operator must verify completeness and freshness; the script checks format and commitments, not the source oracle.

fresh deployments seed batches of 100. the Sepolia continuation can reuse the first three CREATEs and defer only seeding. it keeps the original snapshot, changes later deployment addresses and records `confirmed-contracts-sanctions-pending`. mainnet has no empty-list continuation.

the RedStone source/worker and deferred seed remain follow-up work. Ink transaction screening does not replace the protocol's sanctions checks. existing Ethereum markets remain bound to their old oracle until the chosen V2.5 cutover; Plasma's mirror feed also needs updating.

## evidence and recovery

`prepare` freezes source, build, config, snapshot and nonce commitments. `run` simulates then broadcasts sequentially. `collect` checks canonical receipts, transaction bodies, deployed code and bootstrap bindings before writing inventory: 12 confirmations live, one on Anvil. later administration belongs in separate receipts.

`collect` also submits source verification through Blockscout Pro. set `INK_BLOCKSCOUT_API_KEY` in `.env` (`proapi_...`); an exported value wins. reports are append-only. retry explorer failures with `verify`, interrupted broadcasts with `resume`; keep the original source, cache and RPC endpoint for resume. completed inventories can be re-verified after script/docs changes if contract creation bytecode still matches.

the localhost relay adds gateway authentication. it has no signer. RPC reads use fresh connections so synchronous Forge work cannot leave Node reusing an expired socket. archive the run, broadcast and relevant cache evidence privately; `.env`, keys and run data stay out of Git.

## checks

Node 22+, Foundry and Solidity 0.8.25 are required. run before preparing a new deployment:

```sh
node script/ink/ink.mjs check
node --test test/ink/*.test.mjs
FOUNDRY_PROFILE=ink forge test --offline
FOUNDRY_PROFILE=ink FOUNDRY_TEST=test/vault FOUNDRY_OUT=ir-out FOUNDRY_CACHE_PATH=ir-cache \
  forge test --offline --no-match-test '^testFail_'
```

Forge may emit the existing SphereX `locals` lint diagnostic despite successful solc compilation. two legacy wrapper `testFail_*` names are incompatible with current Forge and excluded above. local tests cover deployment, helper rotation, mainnet handoff, inventory/recovery and verification transport; real Safe signing and application flows need their own checks.

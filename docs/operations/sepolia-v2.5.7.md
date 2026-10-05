# Sepolia v2.5.7 activation

This packet prepares V2.5.7 on Sepolia (`11155111`). Contract source is
`85b963d767ac295bfff32f6e69d734dd616da248` on `feat/sepolia-v2.5.6`.
It adds the current borrower's sanctions check to delegated `transferFrom`
calls on market tokens and ERC-4626 wrapper shares. Existing immutable markets
and wrappers retain their deployed behavior.

The packet is prepared, not deployed. Use the
[ceremony checklist](../../script/deploy/CEREMONY_CHECKLIST.md) for the clean,
pushed source gate, real-wallet fork rehearsal, live execution and evidence ZIP.

## Scope

The plan contains **21 cards: 11 deployments and 10 calls**.

| Deployment | Count | Reason |
| --- | ---: | --- |
| ERC-4626 wrapper factory | 1 | Embeds the changed wrapper creation code |
| Standard and revolving market storage | 4 | Changed market code; two storage chunks per implementation |
| Standard and revolving hooks factories | 2 | Bind the new market stores and wrapper factory |
| Lens facade and three helpers | 4 | Bind the new standard factory and replacement helpers |

The calls register both factories as controller factories, register the three
templates on each, and register both factories as controllers. Fees remain
500 protocol-fee bips with no origination fee. Executor and fee recipient remain
`0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`.

The three V2.5.6 hook-template stores and V2.5.5 AccessList role-provider factory
are reused. Their creation bytes are unchanged. Validation binds their addresses,
original receipts and code hashes to the pinned handoffs; preflight checks the
deployed runtime hashes. This saves four deployment cards. The shared borrower
identity registry and V1 wrapper fallback are also retained.

All existing factory registrations, template states, authority and SphereX roles
are retained. Older factories can still create markets on-chain. Consumer
creation routes must adopt the new canonical factories to receive this fix.
Factory retirement is a separate ceremony.

## Source and baseline

- Configuration: [`v2.5.7.json`](../../deployments/sepolia/v2.5.7.json).
- Contract source: `85b963d767ac295bfff32f6e69d734dd616da248`.
- Inventory baseline: `1fbbacb318046c53822a70c2808fbc55372d5a3a`.
- Retained evidence: [`handoff-v2.5.5.json`](../../deployments/sepolia/handoff-v2.5.5.json)
  and [`template-update-v2.5.6.json`](../../deployments/sepolia/template-update-v2.5.6.json).
- Compiler: frozen `deploy` profile; settings and submodules are captured in
  [`source-v2.5.7.txt`](../../deployments/sepolia/source-v2.5.7.txt).

Only `WildcatMarketToken.sol` and `Wildcat4626Wrapper.sol` changed under `src/`
from the V2.5.6 contract source. The standard market runtime is 23,985 bytes;
the revolving runtime is 24,541 bytes, leaving 35 bytes below EIP-170. Factory
and lens constructor bindings require fresh deployments even though their own
source is unchanged. No new event or external function signature is introduced.

## Prepare and review

From the repository root:

```sh
export SEPOLIA_REPLACEMENT_CONFIG=deployments/sepolia/v2.5.7.json
node scripts/sepolia-v2-5-fix-rotation.js generate
node scripts/sepolia-v2-5-fix-rotation.js validate
node scripts/sepolia-v2-5-fix-rotation.js generate-rehearsal
```

Review `plan-v2.5.7.json`, `plan-entries-v2.5.7/`,
`inventory-pending-v2.5.7/`, `impact-v2.5.7.json`, and the generated package
digest in `deployments/sepolia/`. Commit and push the reviewed packet before
operator gates. Do not regenerate a packet after execution starts.

The wrappers select this release despite the branch's historical name:

```sh
bash script/deploy/v2-5/sepolia-v2.5.7-stage.sh check
FORK_RPC_URL=https://eth-sep.hinterlight.net \
  bash script/deploy/v2-5/rehearse-sepolia-v2.5.7.sh --ui
DEPLOYMENTS_NETWORK=anvil bash script/deploy/v2-5/sepolia-v2.5.7-stage.sh activation
```

Follow the checklist for wallet connection, receipt export, rehearsal acceptance,
live activation and finalization. The non-UI rehearsal also tests inventory
and handoff generation in an isolated evidence directory. It does not establish
real-wallet acceptance or modify the canonical deployment files.

## Finalization and downstream work

After verified live execution, `stage finalize-inventory` appends the two hooks
factories and wrapper factory, updates canonical aliases, and writes
`handoff-v2.5.7.json` with its Markdown companion. Reused components retain
their **original deployment transaction and start block**, with explicit source
handoff and plan hashes. Their new release aliases do not imply a new deployment.
All previously indexed generations and explicit exclusions remain in the inventory.

Finalization reconciles the inventory, then creates the evidence ZIP and checksum
under `deployments/sepolia/ceremony-evidence/`. The archive includes original
handoffs and plans needed to interpret reused deployments. If ZIP creation fails
after finalization, `stage archive-evidence` retries offline without replaying
transactions or inventory changes.

Once actual receipts are available, update the subgraph's factory inventory and
wrapper data sources, then update SDK canonical factories, wrapper and lens
addresses. The existing V2.5 event surface is unchanged; address/configuration
adoption and indexing of the new generations are required. Publish the SDK,
update the app dependency and verify new-market and wrapper behavior. Preserve
the completed lifecycle feature work and historical-market routing.

Preparation evidence and check results are recorded in
[`preparation-v2.5.7.json`](../../deployments/sepolia/preparation-v2.5.7.json).
Operator cold gates, real-wallet rehearsal, live transactions and downstream
adoption remain outstanding until separately recorded.

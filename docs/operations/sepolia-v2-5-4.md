# Sepolia V2.5.4 replacement

Status: prepared for rehearsal; V2.5.4 has not been deployed to Sepolia.
Scope: `v2-protocol` only. The package contains **12 deployments and 10
activation calls**. All predecessor factories remain registered. Authority
and SphereX roles remain fixed.

## Source and deployed baseline

| Input | Pin |
| --- | --- |
| New protocol package | `2.5.4` |
| New production Solidity | `bea503c2736d47de7fd34130c64f10783dc35b39` |
| Last deployed package | `2.5.3`, ceremony `v2-5-sepolia-fix-1` |
| Last deployed production Solidity | `6dd6d697b2e381a94a33bfae29dc7945e12b14b8` |
| Deployment tag | `v2.5.3-sepolia` at `9362cac0e5bf49d13806937d4e758516b88c197a` |
| Network / executor | Sepolia `11155111` / `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7` |
| Compiler | Foundry `1.7.1`, Solidity `0.8.25`, Cancun, via IR, optimizer 44, no appended CBOR |

The tag has the same `src/`, `lib/`, and compiler configuration as the deployed
Solidity pin. The deployment packet's version is distinct from the older
package version at that Solidity pin. The live transaction range is
`11581359`–`11581384`, on August 28, 2026 UTC.

[Baseline verification](../../deployments/sepolia/baseline-v2-5-4.json)
records 22 successful live receipts, their exact calldata, 18 deployed code
hashes, and reused-runtime comparison at block `11641455`. The five stored
initcode contracts also match the predecessor plan byte for byte.
The receipt-backed baseline is newer than the original August V2.5 activation.

## Changes since 2.5.3

Ten production source files have executable changes. The remaining source
diff is documentation. The relevant merged fixes are:

| Commit | Result | Deployment consequence |
| --- | --- | --- |
| `64662c7` | Reclassify delinquency after expired-batch settlement, including the view path | Both market stores |
| `a1575b1` | Settle the expiry boundary against checkpointed assets and preserve the checkpoint across state writes | Both market stores |
| `66dc10d` | Check withdrawal-expiry conversion to `uint32` | Both market stores |
| `b670553` | Explicit repayments reduce revolving drawn principal; raw donations do not silently repay it | Revolving market store |
| `62ddcea` | New markets obtain their SphereX engine from the current ArchController | Both factories |
| `dcb1204` | Enforce market-token recipient policy in wrapper `deposit` and `mint` | Wrapper factory, which embeds wrapper creation code |
| `00bddcb` | Admit the exact market-registered wrapper through recipient checks and transfer callbacks | Open, fixed, and periodic hook stores |

No production Solidity is changed by this ceremony update. Market `version()`
continues to return `"2.5"`; `2.5.4` identifies the release, not a new onchain
compatibility marker.

## Deployment set

| Component | Count | Creation bytecode vs 2.5.3 | Why deploy |
| --- | ---: | --- | --- |
| Standard/revolving market initcode stores | 2 | Changed | Embed the accounting and expiry fixes |
| Standard/revolving `HooksFactory` | 2 | Changed | SphereX fix plus immutable new market-store and wrapper bindings |
| `Wildcat4626WrapperFactory` | 1 | Changed | Embed the corrected wrapper implementation |
| Open/fixed/periodic hook initcode stores | 3 | Changed | Canonical-wrapper access fixes |
| `MarketLensCore`, `MarketLensAggregator`, `MarketLensLive`, `MarketLens` | 4 | Identical | Each binds the standard factory immutably; the facade also binds its three helpers |

Reuse the existing borrower identity registry
`0xc2cF90781595203D1e75c28246b306C95d4b8b21` and access-list provider factory
`0x92995EA2ba572E4Cb8bB41E30f813BeB77FD4974`. Their creation bytecode is
identical, and their deployed runtime matches current artifacts after binding
the registry's ArchController immutable.

Also retain the existing ArchController, sanctions sentinel and escrow path,
authority helper, SphereX engine/admin/operator, and V1 wrapper factory.
See the [config](../../deployments/sepolia/v2-5-4.json) for exact addresses and
the [impact report](../../deployments/sepolia/impact-v2-5-4.json) for all hashes.

The smallest deployment-size margin is the revolving market initcode store:
`23,644` runtime bytes (`STOP` plus `23,643` creation-code bytes), leaving
`932` bytes below EIP-170. The generator checks this separately from ordinary
contract runtime sizes.

## Activation and continuity

The 22 cards deploy the 12 components, register both controller factories,
add all three templates to each factory, and register both factories as
controllers. All eight owner-only activation calls are forwarded through the
existing helper; the final two factory self-registration calls are direct.

Template fees retain the reviewed predecessor values: recipient
`0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`, zero origination fee, and
`500` protocol-fee bips. Preflight verifies the live predecessor values.

The predecessors for this release are:

- Standard: `0x89797b782cA5b4BBFC975146B98ba3941Fe26C56`.
- Revolving: `0xb3FBD4FBeb1EE4BEE7afdbC4A75C7c4E97CF105C`.

Deployment does not patch existing markets, hook instances, or wrappers.
Exercise fresh markets with the new factories **and new hook instances** to
test these fixes. Old factories can still originate old-code markets until a
separate retirement ceremony. Even retirement does not change existing code.

Inventory finalization appends the new generations, promotes their aliases,
and retains historical indexing and registrations. Subgraph, SDK, app, and
other consumer changes are deferred. Their existing routing remains on the
previous generation until that separate cutover.

## Prepare and rehearse

Generate only the new packet; never regenerate or resume the completed
`v2-5-sepolia-fix-1` packet using current source.

```sh
export FOUNDRY_PROFILE=deploy
node scripts/sepolia-v2-5-fix-rotation.js generate \
  --config deployments/sepolia/v2-5-4.json
node scripts/sepolia-v2-5-fix-rotation.js validate \
  --config deployments/sepolia/v2-5-4.json
node --test scripts/sepolia-v2-5-fix-rotation.test.js
```

The plan, plan entries, pending inventory, impact report, source pin, and digest
are reviewable release inputs. Commit and push the reviewed packet before
running the operator stages; the stages enforce a clean, pushed checkout.
Ceremony packages and rehearsal/run-state evidence are generated locally.
No new live handoff or deployment alias is written during preparation.

For a headless rehearsal before the wallet ceremony:

```sh
FORK_RPC_URL=https://eth-sep.hinterlight.net \
  bash script/deploy/v2-5/rehearse-sepolia-v2-5-4.sh
```

Then follow the [operator checklist](../../script/deploy/CEREMONY_CHECKLIST.md)
for the clean-source cold gates, real-wallet Anvil rehearsal, acceptance,
live Sepolia activation, receipt verification, and inventory finalization.
The V2.5.4 entry points are:

```sh
bash script/deploy/v2-5/sepolia-v2-5-4-stage.sh check
bash script/deploy/v2-5/rehearse-sepolia-v2-5-4.sh --ui
bash script/deploy/v2-5/sepolia-v2-5-4-stage.sh activation
```

The latter stages default to Anvil `31337`. Live preparation requires
`DEPLOYMENTS_NETWORK=sepolia` and accepted real-wallet rehearsal evidence for
this exact live plan and package. A headless pass does not create that
acceptance record. Re-run preflight immediately before live execution.

The live plan is `deployments/sepolia/plan-v2-5-4.json`; its package is
`deployments/sepolia/ceremony-v2-5-4-eoa.json`. Match the full digest and
fingerprint printed by the stage to the embedded UI. Preserve each new browser
export unchanged; the stable live export is `run-state-v2-5-4.json`.

## Preparation verification

The headless rehearsal passed all 22 predicates and all 22 receipt/calldata
provenance checks on a fork pinned to `11641455`. Post-activation verification
confirmed all factory, template, wrapper, and lens bindings, unchanged
authority, and both predecessors still registered. Evidence is retained in
`deployments/anvil/v2-5-4-rehearsal.uCJ3sX/`.

The deployable-source size gate, five ceremony regression tests, 38 deployment
UI unit tests, the Sepolia-fork UI executor test, the dependency audit (zero
findings), and locked Sepolia UI build passed. The broad size command also
includes oversized test/script harnesses; the cold gate now uses
`FOUNDRY_PROFILE=deploy forge build --sizes src`. The first two Solidity suite
commands explicitly use the default profile before the separate deploy-profile
suite.

Live package digest:
`0xd9e498e00f5e50d6d07a8b60ba043ccd538a723298d267ae69d7ada77e44a7e7`.
Fingerprint: `D9E4-98E0-0F5E`. The Anvil package has its own digest because its
chain ID and release label differ.

These preparation checks do not mark the real-wallet rehearsal accepted or
the pushed-source cold gate complete. Run the operator checklist after
reviewing, committing, and pushing this packet.

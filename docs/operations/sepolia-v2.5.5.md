# Sepolia v2.5.5 activation

This is an additive deployment of `v2.5.5` on Sepolia (`11155111`). The plan
is prepared, not deployed. Use the existing
[ceremony checklist](../../script/deploy/CEREMONY_CHECKLIST.md) for the
real-wallet rehearsal, live activation, and receipt-backed finalization.

## Scope

The generated plan contains 30 cards: 20 deployments and 10 activation calls.

| Deployments | Count |
| --- | ---: |
| Wrapper factory | 1 |
| Standard and revolving market stores, two chunks each | 4 |
| Standard and revolving hooks factories | 2 |
| Open, fixed, and periodic hook template stores | 3 |
| AccessList, Merkle, ERC20, ERC721, ERC1155, and ERC4626Assets provider factories | 6 |
| Lens facade and three helpers | 4 |

The activation calls register both factories, install all three templates on
each with their creation-code hashes, and register both factories as controllers.
Every provider factory is fresh; instances created through these factories use
the v2.5.5 source. The shared borrower identity registry is reused to retain its
existing account mappings. The new wrapper facade retains its V1 fallback.

No factory, controller, market, template, authorization, or owner is removed or
disabled. V1, predecessor deployments, and the old no-code registration are
untouched. Authority helper and SphereX roles remain fixed. Existing factories
can still be called on-chain; canonical aliases select v2.5.5 for downstream
creation flows, not an on-chain shutdown of older generations.

Market behavior testing, SDK/subgraph changes, backfill experiments, and legacy
cleanup are separate follow-ups. Rehearsal verifies this deployment package and
its configuration; it is not a protocol regression suite.

## Reviewed inputs

- Configuration: [`v2.5.5.json`](../../deployments/sepolia/v2.5.5.json).
- Contract source: `05165ad4c4020c1400048680b85b3585f84e8527` from `release/v2.5`.
- Compiler: the frozen `deploy` profile in `foundry.toml`; full settings are
  retained in `deployments/sepolia/source-v2.5.5.txt`.
- Executor and fee recipient: `0xCa7007a75296b532Ce1606d9e130eAa849800Ca7`.
- Template fees: 500 protocol-fee bips, no origination fee.
- Reused bindings: explicit in the configuration.

The operator confirmed the executor, fee recipient, and template fees on
2026-10-02.

`deployments.json` and `factory-inventory.json` were restored byte-for-byte from
`1263de7ef41ba7f3b4ca2aa6d614640ad31113ef`, the preserved deployment records
containing the latest deployed generation. This prevents the next handoff from
silently dropping it. Receipt hashes and start blocks retain their original
provenance; restoring those files is not a new deployment or fresh observation.
No v2.5.5 address becomes canonical until verified live receipts are finalized.

## Prepare the packet

From the repository root:

```sh
export SEPOLIA_REPLACEMENT_CONFIG=deployments/sepolia/v2.5.5.json
node scripts/sepolia-v2-5-fix-rotation.js generate
node scripts/sepolia-v2-5-fix-rotation.js validate
node scripts/sepolia-v2-5-fix-rotation.js generate-rehearsal
```

These commands compile and prepare local artifacts. They do not sign, broadcast,
or change live aliases. The generator reuses the existing fixed-authority flow;
the historical fix-1 packet remains unchanged.

Review `plan-v2.5.5.json`, `plan-entries-v2.5.5/`,
`inventory-pending-v2.5.5/`, `impact-v2.5.5.json`, and the generated digest in
`deployments/sepolia/`. The impact file records deployment scope, not a claim of
bytecode identity with an earlier release. The checklist derives and displays
the final package identity; do not maintain a second digest in this runbook.

Commit and push the reviewed packet before operator gates. Those gates require
a clean checkout with `HEAD` matching its upstream, including no untracked files.
Preserve local notes elsewhere or use a clean checkout; do not delete them to
force the gate through. Stop generating packets once execution has started.

## Handoff and indexing

After live receipt verification, `stage finalize-inventory` appends the two new
hooks factories and wrapper factory, updates creation aliases, and generates
`handoff-v2.5.5.json` plus its Markdown companion. It includes all six provider
factories, both chunks of each split market store, ABI artifact paths, and
receipt-derived addresses and start blocks for new deployments. The reused
identity registry has no new deployment receipt.

The handoff preserves every recorded generation and its indexing flag. Previously
indexed history stays indexed. The four excluded test generations stay explicit
exclusions pending a separate backfill decision; this packet does not promise
their recovery. V1 indexing is not configured by this hooks-factory inventory
and must remain unchanged downstream.

SDK and application creation routes should use only the new canonical factories
and templates after adopting the handoff. Historical reads still use the
subgraph's retained generations. Source ABI descriptions are integration pointers,
not permission to apply the newest decoder to every historical event version.

## Preparation status

Local checks on 2026-10-02 passed: 51 deployment-tooling tests, 44 UI tests,
inventory fixtures, deploy-profile build and sizes, and the locked UI build.
Read-only Sepolia preflight passed at blocks `11828028` and `11830628`. The operator stage
reruns preflight; this result is not rehearsal or deployment acceptance.

The deployment UI now pins Vitest `4.1.11`, resolving `GHSA-82fw-gwwq-j7x9`.
On 2026-10-02, its `npm audit` reported zero vulnerabilities after a clean
install with lifecycle scripts disabled; all 44 UI tests and the locked build
passed. Only Vitest and its companion dependency versions changed in `deploy-ui`.

The root now pins Solhint `6.2.4`, with its network update check disabled. Its
54 newly resolved package versions passed tarball integrity and registry-signature
checks on 2026-10-02. `yarn audit` reported zero known vulnerabilities, and
`yarn lint:check` passed with zero errors and the same 43 warnings as Solhint
`3.6.2`. Solhint brings its own optional Prettier 3 dependency; the project's
Prettier 2, Solidity formatter plugin, and direct inventory parser are unchanged.
Forge handles formatting, and the Prettier/Solhint bridge remains removed.

The [JavaScript toolchain and install policy](../../CONTRIBUTING.md#javascript-toolchain)
are pinned. The cold gate reinstalls both dependency trees from their lockfiles
with lifecycle scripts disabled. Clean installs passed all 51 deployment-tooling
tests, all 44 UI tests, and the locked UI build. The input review reproduced
both live and rehearsal ceremony packages byte-for-byte.

These checks are not malware clearance or a substitute for the cold gates.
No wallet rehearsal or live transaction has run during preparation.

- [x] Branch from `release/v2.5` and pin contract source.
- [x] Prepare the activation plan, pending inventory, and compiler pin.
- [x] Support dotted release labels and all six provider factories in finalization.
- [x] Review fees, reused bindings, plan, and package identity.
- [x] Resolve the root and deployment UI dependency audit findings.
- [ ] Commit and push the reviewed packet; run the checklist's cold gates.
- [ ] Complete and accept the real-wallet fork rehearsal.
- [ ] Execute and verify live Sepolia activation.
- [ ] Finalize inventory and publish the downstream handoff.
- [ ] Update subgraph and SDK, then test the deployed behavior separately.

# v2.5 Deployment Tooling — Status

As of 2026-07-17. Companion to [deployment.md](./deployment.md) (the process
runbook). This records what is built, what is proven, and what remains.

## Built and verified

**Inventory** (committed): `factory-inventory.json` schema 1.1 — lifecycle
(`canonical | live | retired`), append-only records, `wrapperFactories[]`
with the v1 link; `lint` and two-half `reconcile` (registry-backed hooks
factories via the ArchController, configuration-backed wrapper factories);
the one-time repair of both networks' inventories (Sepolia canonical
history corrected against on-chain creation blocks; mainnet backfilled from
chain enumeration). The rollout selects every hooks factory whose reconciled
inventory state is `registered: true`, removes its controller-factory role
before its controller role, and finalization records it unregistered without
changing historical indexing. Reconcile is green against live Sepolia and
mainnet.

**Plan engine** (committed): `scripts/plan.js` — a deployment release
compiles to a single plan artifact (`plan-<release>.json`): ordered
transactions with plain-English descriptions, decoded args, `$ref`
placeholders for not-yet-deployed addresses, execution envelopes, and an
on-chain verification predicate per transaction. Subcommands: assemble /
validate / execute (with halt-on-predicate-failure and verified resume) /
verify / render-safe. Known network names are rejected if their plan chain ID
does not match, preventing a plan generated without the target RPC from being
assembled as a release artifact.

**Numbered scripts** (committed): `script/deploy/v2-5/01–09`. Dual-mode:
`OWNER_MODE=plan` generates plan entries (no key, no broadcast);
`OWNER_MODE=direct` broadcasts inline for component maintenance. Two-flow
rule (see deployment.md §3): generational rollouts go through the plan
pipeline on every network; inline direct is for between-release maintenance
and deliberately cannot reach step 08. Step 06 registers the two new factories
and disables every superseded inventory factory in both ArchController roles;
it never removes markets.

**Bundle mode** (staged): `scripts/plan-bundle.js` — compiles a plan into a
minimal set of atomic Safe transactions (3 for v2-5): `MultiSend`
delegatecall, deployments via the canonical `CreateCall` as CREATE2, every
address precomputed at bundle time, all `$ref`s resolved statically.
Outputs per bundle: Safe TX Builder JSON (review-only — the Builder's
import model drops `operation`, so proposals must carry `operation: 1` via
the Safe SDK), a frontend manifest, expected addresses, and one combined
review sheet. `bundle-simulate` executes through the real Safe on a fork;
`bundle-verify` derives the run-state that step 08 consumes unchanged.

**Frontend** (staged): `deploy-ui/` — self-contained static SPA
(vite/react/viem/wagmi/Safe SDK; own dependency tree, root untouched). Two
modes: EOA card-walk for testnets (mirrors `plan.js execute`, localStorage
resume, run-state export) and Safe bundle ceremony for mainnet (propose
with `operation: 1`, signature-progress polling, execute, per-bundle
predicate board). Release builds embed one digest-bound ceremony package and
lock the mode, so operators do not locate or load plan/bundle files. Rails:
chainId hard-check, package/plan hash display for call-time byte verification, predicate failure is a full stop, no
editable or manifest-trusted calldata; the browser independently reconstructs
the exact calldata from the plan. Engine modules are React-free and
fork-tested headlessly; EOA run-state is verified byte-compatible with
`plan.js verify`.

**Docs** (staged): `deployment.md` — the runbook for both flows, the fork
rehearsal recipe (every friction from real rehearsals), the bundle
ceremony, the guided Sepolia helper-owner compensation, "adding a market type".
`generate-handoff.js` — the subgraph/SDK touch-point document generated
from inventory: all factory generations with index-all flags and
startBlocks, routing prose, the v2.5 ABI-delta list.

## Proven by rehearsal (anvil forks, not checked in)

- Sepolia fork, current full pipeline: 38-transaction plan generated and
  executed through the temporary helper-owner flow as a dev EOA, including
  ownership reclaim and restoration plus paired removal of all seven
  superseded hooks factories; 38/38 predicates verified, inventory finalized
  with historical `indexed` flags preserved, and reconcile green. An earlier
  direct-owner rehearsal also deployed, exercised, and closed the standard and
  revolving canary markets.
- Mainnet fork, current 24-transaction pipeline executed as the
  impersonated Foundation Safe
  (`0xC15bE5214978d1fc509ECdd4f9D5BC067C94D9Ae`, v1.4.1, threshold 3), including
  paired removal of the one superseded hooks factory; 24/24 predicates
  verified, historical indexing preserved, inventory finalized, and reconcile
  green.
- The earlier five-registration mainnet bundle ceremony used 3 bundles at
  ~15.8M / 17.3M / 9.8M gas. Those bundle artifacts and gas figures are stale;
  regenerate and re-simulate the corrected six-registration plan before
  mainnet signing.
- Sepolia fork, true signing path: fresh 1-of-1 Safe via canonical v1.4.1
  ProxyFactory, real EIP-712 signature, all bundles and predicates green.
- Frontend engines: headless fork tests for both modes, including the actual
  Sepolia helper reclaim/restore sequence and the 1-of-1 Safe EIP-712 path.

## Ceremony shape (the deliverable UX)

Mainnet: host the package-specific `deploy-ui/dist`, confirm its fingerprint on
the call, then per bundle: operator proposes, signers review the card and sign
(three threshold signatures per generated bundle), operator executes, predicate
board goes green. Export run-state → step 08 → reconcile → handoff.

Testnets: same page in locked EOA mode with a dev key. Sepolia's first and last
cards perform the helper-owner reclaim and return; each card signs immediately.

## Remaining

1. **Live Sepolia rollout through deploy-ui (EOA mode)** — the real test
   drive: mints the v2.5 canonical generation on Sepolia, exercises the
   page against a live network, produces the first real handoff. Gates the
   legacy sweep.
2. **Legacy sweep** (after the live rehearsal): old deploy scripts →
   `script/legacy/`, retire superseded env conventions, supersede the RCF
   checklist.
3. **Mainnet ceremony** when the release is blessed: generate and simulate the
   corrected Safe bundles, then use the resulting package with Foundation
   signers on a call.
4. Deferred: Plasma explorer verification config (`VERIFIER_URL`) when
   those chains onboard; subgraph/SDK/app updates consume the generated
   handoff.

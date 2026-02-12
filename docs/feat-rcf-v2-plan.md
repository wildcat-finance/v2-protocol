# feat/rcf-v2 implementation plan

Date: 2026-02-09  
Status: Draft for review  
Branch target: `feat/rcf-v2`

## Goal
Implement the functional intent of `feat/rcf` with significantly lower protocol disruption by:
- preserving `MarketState` ABI and hook calldata shape,
- keeping legacy deployment and behavior on existing `HooksFactory`,
- adding revolving behavior via a dedicated new factory and market contract.

## Non-goals
- No migration of already deployed markets.
- No forced app/backend cutover in the same PR as protocol changes.
- No expansion of `IHooks`/`HooksConfig` unless absolutely required.
- No multi-market-type routing inside a single factory in this rollout.

## Current decisions (agreed)
1. Keep existing `HooksFactory` as the canonical legacy deploy factory.
2. Introduce `HooksFactoryRevolving` (a.k.a. `HooksFactoryRCF`) as a separate deployment that only deploys revolving markets.
3. Canonical deployment policy is one factory per market type: legacy -> old `HooksFactory`, revolving -> `HooksFactoryRevolving`.
4. New revolving variables live in market contract storage, not `MarketState`.
5. Preserve `MarketState` and existing hooks ABI for the initial revolving rollout.
6. Use Option B for initializing `commitmentFeeBips`: additive deploy methods carry separate `marketData`, while `hooksData` remains hook-owned and is forwarded unchanged.
7. `HooksFactoryRevolving` must reject legacy/incompatible deploy payloads and malformed `marketData`.
8. Deployment event policy: emit only legacy `MarketDeployed` from the new factory in this rollout (no additional typed deployment event).
9. Market discovery/read policy: subgraph-first for normal app/sdk queries, with `ArchController` as canonical source of truth for parity checks and fallback.
10. Phase boundaries are repo-scoped: each phase targets one primary repo/PR with independent review, test deployment, and rollout validation.
11. Rollout sequencing is staged and integration-first: protocol -> SDK -> subgraph -> app on shared local infrastructure before testnet promotion.
12. Environment documentation strategy is repo-local: each repo owns its own `.env.example` plus supporting docs; no monolithic cross-repo env file.
13. Naming convention for this rollout is `HooksFactoryRevolving` / `IHooksFactoryRevolving` / `WildcatMarketRevolving`.
14. Hooks templates remain generic and borrower-selected; no template-type policy gates are imposed by protocol (open/whitelist templates are valid for revolving where technically compatible).
15. Revolving-only fields are in-scope for full production visibility (protocol lens + SDK + app), not an MVP deferment.
16. SDK deploy routing remains backward-compatible: when market type is omitted, route to legacy by default; revolving deployment requires explicit market-type selection.
17. Canonical read endpoint policy: SDK/app point to the latest lens deployment per network; that lens must expose visibility across all supported market types.
18. Lens architecture policy: no lens-to-lens delegation/chaining; each lens version reads markets/factories directly.
19. Market type identification is derived from factory context/mapping (onchain `market.factory()`, subgraph datasource/factory map), not from a new typed deployment event.
20. Deployment workflow includes one-time template registry sync support from legacy factory to `HooksFactoryRevolving` (scripted export/apply/verify), so template reuse remains available.
21. Unified lens exposes both borrower/template read modes: explicit factory-parameterized endpoints (granular) and aggregated cross-factory endpoints (convenience UX).

## Decision log
| ID | Decision | Status | Notes |
|---|---|---|---|
| D1 | Factory model is per-market-type (legacy factory + revolving factory) | Decided | Avoids same market type being deployable from multiple active factories |
| D2 | No multi-type routing in a single new factory | Decided | Reduces protocol complexity and implementation risk |
| D3 | `IHooks` unchanged for v2 rollout | Decided | Avoids hook/config blast radius |
| D4 | Revolving state stored outside `MarketState` | Decided | Preserves ABI/encoding stability |
| D5 | Lens support for mixed market populations via optional getters | Decided | Additive V2 lens reads use low-level `staticcall` with explicit presence flags |
| D6 | `commitmentFeeBips` initialization via separate `marketData` bytes | Decided | Avoids changing existing `hooksData` parsing assumptions |
| D7 | `HooksFactoryRevolving` enforces revolving-only deploy rules | Decided | Reject invalid legacy/incompatible deploy calls early and deterministically |
| D8 | Emit legacy `MarketDeployed` only for this rollout | Decided | Preserve existing listeners and avoid typed-event rollout overhead |
| D9 | Subgraph-first discovery with `ArchController` truth/parity model | Decided | Keeps UX/perf stable while preventing mixed-factory blind spots |
| D10 | Repo-scoped rollout phases (one primary repo per PR phase) | Decided | Reduces cross-repo coupling and simplifies staged validation |
| D11 | Final sequencing: local anvil-fork + local graph integration across all 4 repos before testnet | Decided | Ensures end-to-end validation before shared-environment activation |
| D12 | Environment template strategy is per-repo `.env.example` files | Decided | Keeps ownership clear across non-monorepo repos and avoids cross-repo drift |
| D13 | Naming uses `HooksFactoryRevolving` over generic `HooksFactoryV2` | Decided | Makes the market-type scope explicit |
| D14 | Hooks templates remain generic (no protocol-level template-type gating) | Decided | Borrower/template choice stays permissionless within technical constraints |
| D15 | Revolving-only fields are production-scope in this rollout | Decided | No MVP-only deferment for visibility surfaces |
| D16 | SDK deploy default remains legacy when market type is unspecified | Decided | Preserves backward compatibility while enabling explicit revolving opt-in |
| D17 | Canonical onchain read endpoint is latest unified lens per network | Decided | SDK/app use newest lens address for all supported market types |
| D18 | No lens-to-lens delegation | Decided | Avoids dependency chains and compounding operational complexity |
| D19 | Derive market type from factory context instead of typed deploy event | Decided | Minimizes protocol/subgraph churn while preserving market-type visibility |
| D20 | Template registry sync is handled as deploy/runbook scripting, not protocol auto-mirroring | Decided | Keeps protocol simple while preserving cross-factory template reuse |
| D21 | Unified lens supports both aggregated and factory-parameterized borrower/template reads | Decided | Balances UX convenience with explicit granular control |

## Open questions
None remaining.

## Deferred external inputs
1. Foundry version pin:
- pending confirmation after SphereX compatibility review.
- until confirmed, treat toolchain pinning as a pre-implementation gate for protocol coding work.

## Captured findings (current state and impact)
1. Market discovery in app/sdk is currently subgraph-driven.
- SDK query wrappers: `wildcat.ts/src/gql/getMarketsWithEvents.ts` and `wildcat.ts/src/gql/getMarketsForBorrower.ts`.
- App hooks call those wrappers: `wildcat-app-v2/src/app/[locale]/borrower/hooks/getMaketsHooks/useGetBorrowerMarkets.ts` and `wildcat-app-v2/src/app/[locale]/borrower/hooks/getMaketsHooks/useGetOthersMarkets.ts`.

2. Onchain calls are used mainly for writes, tx result decoding, and state refresh on known market ids.
- Post-query refresh path: `wildcat-app-v2/src/app/[locale]/borrower/hooks/getMaketsHooks/updateMarkets.ts`.
- Deploy-time event decode path: `wildcat.ts/src/controller.ts` and `wildcat-app-v2/src/app/[locale]/borrower/create-market/hooks/useDeployV2Market.ts`.

3. Single-factory assumptions exist today and are the main dual-factory effort driver.
- SDK factory accessor currently resolves one deployment address: `wildcat.ts/src/constants.ts`.
- Hooks template wrappers hardcode `HooksFactory`: `wildcat.ts/src/access/access-control.ts` and `wildcat.ts/src/access/fixed-term.ts`.
- Lens hooks-data calls are factory-bound through one immutable factory address in the lens contract path: `v2-protocol/src/lens/MarketLens.sol`.

4. `ArchController` already exposes canonical market registry APIs.
- `getRegisteredMarkets`, paginated `getRegisteredMarkets(start,end)`, and count are available and suitable for parity checks/fallback: `v2-protocol/src/interfaces/IWildcatArchController.sol`.

5. Practical effort estimate from current state.
- Protocol complexity drops vs multi-type single-factory design.
- SDK/subgraph/app mixed-factory work remains medium due to permanent coexistence of legacy and revolving markets.

## Integration workflow (agreed execution order)
1. Protocol phase (`v2-protocol`):
- complete protocol PR,
- run protocol test suite,
- deploy local contracts on an anvil fork using deployment scripts.

2. SDK phase (`wildcat.ts`):
- implement SDK dual-factory updates,
- test SDK directly against the same anvil-fork deployment from Phase 1.

3. Subgraph phase (subgraph repo + generated clients):
- update subgraph indexing for mixed factory deployments,
- run local graph node/server and index from the same anvil-fork chain,
- validate subgraph query parity versus onchain (`ArchController` checks).

4. App phase (`wildcat-app-v2`):
- integrate SDK/subgraph updates in app,
- point app at local anvil + local graph stack,
- run borrower/lender smoke tests across mixed factory paths.

5. Promotion gate:
- proceed to testnet deployment only after all 4 phases pass local integration validation.

## Phase handoff artifacts
1. Phase 1 -> Phase 2:
- publish a machine-readable handoff artifact (JSON),
- include deployed addresses (legacy factory, `HooksFactoryRevolving`, latest lens),
- include chain id/network metadata and tx hashes,
- include canonical factory -> marketType mapping for active factories,
- include ABI/selector surface notes required for SDK/subgraph/app integration.

2. Phase 2 -> Phase 3:
- keep SDK deploy-path logic frozen; Phase 3 may only update generated query artifacts or endpoint wiring needed to consume new indexing outputs.

3. Phase 3 -> Phase 4:
- provide validated subgraph endpoint/manifests and any regenerated GraphQL clients consumed by app paths.

4. Phase 4 -> Promotion gate:
- provide end-to-end smoke-test evidence on shared local stack (deploy -> index -> query -> app flows).

## Tooling and environment prerequisites
1. Foundry/toolchain reproducibility:
- lock and document the expected Foundry version/profile settings used for this rollout, because current local environments may fail `forge build/test` due to parser/lint/tooling drift.
- Foundry version selection is pending SphereX compatibility confirmation.

2. Deployment environment contract:
- document required env vars for protocol deploy scripts (`RPC_URL`, deployer key var, ArchController address, sanctions sentinel, optional existing template addresses),
- provide sanitized `.env.example` files per repo with repo-specific supporting docs (no secrets committed).

3. Local fork deployment output contract:
- require machine-readable output (JSON) that is consumed by later phases instead of manual copy/paste.
- minimum fields: addresses, tx hashes, chain id/network, canonical lens address, and factory -> marketType mapping.

## Milestones
### M0: Architecture freeze
Output:
- final interface shape for `IHooksFactoryRevolving`,
- final `marketData` encoding for revolving deployment,
- final event compatibility policy.

Exit criteria:
- all decision-log items required for implementation are resolved (currently complete).
- written design addendum committed to docs.

### M1: Revolving factory foundation
Scope:
- add `HooksFactoryRevolving` + `IHooksFactoryRevolving`,
- wire revolving market init code storage/hash,
- implement revolving-only deploy paths (including `marketData` decode/validation),
- preserve `hooksData` passthrough behavior,
- preserve generic hooks template behavior (`addHooksTemplate`/fees/enablement/instance deployment) without template-type policy gating,
- register factory/controller lifecycle with `ArchController`.

Testing:
- unit tests for deploy routing and `marketData` validation,
- unit tests that incompatible legacy-style deploy calls are rejected,
- unit tests that existing template styles (e.g. open and whitelist/access-control) function as expected on revolving deploy flows,
- unit tests for ArchController registration lifecycle (`registerControllerFactory` -> `registerWithArchController`),
- regression checks proving legacy `HooksFactory` behavior unchanged.

Exit criteria:
- revolving deploy works from `HooksFactoryRevolving`,
- incompatible/legacy deploy paths are rejected by `HooksFactoryRevolving`,
- template behavior remains generic and borrower-selected (no policy gate regressions),
- old `HooksFactory` remains untouched and operational,
- events/getters validated.

### M2: Revolving market contract
Scope:
- implement `WildcatMarketRevolving` with dedicated storage for `drawnAmount` and `commitmentFeeBips`,
- maintain external compatibility with legacy market surface where practical,
- introduce internal accrual extension points so revolving formula can be injected without `MarketState` changes.

Testing:
- borrow/repay/close state transitions for `drawnAmount`,
- utilization + commitment fee accrual behavior,
- parity tests for legacy market remaining unchanged.

Exit criteria:
- revolving behavior functionally matches target economics from `feat/rcf`,
- no `MarketState` struct changes.

### M3: Lens and integration compatibility
Scope:
- add non-breaking lens support for revolving-only fields,
- implement additive V2 lens read path for optional revolving getters via low-level `staticcall`,
- include explicit presence flags in V2 lens outputs for optional fields (do not infer missing values from `0` or sentinel numerics),
- make the new lens deployment the unified read surface for legacy + revolving markets,
- implement direct read/dispatch logic (no delegation to prior lens deployments),
- expose factory-parameterized borrower/template endpoints for explicit per-factory reads,
- expose aggregated borrower/template endpoints that merge across active factories for convenience UX,
- keep legacy market reads working with zero behavior changes.

Testing:
- mixed set of legacy (old factory) and revolving (new factory) markets in lens tests,
- verify optional getter fallback when selector is absent or malformed return data is encountered,
- verify `0` values for optional fields are treated as valid data when presence flag is true,
- verify parameterized borrower/template reads return correct per-factory views,
- verify aggregated borrower/template reads merge across factories correctly (including dedupe/order semantics).

Exit criteria:
- legacy lens queries succeed unchanged against both deployed market populations,
- V2 lens queries provide deterministic presence-aware outputs for mixed populations,
- revolving-only fields required by downstream SDK/app are exposed in production-ready read surfaces,
- both lens read modes are available and tested: parameterized (granular) and aggregated (convenience),
- latest lens deployment can serve as the single canonical onchain read target per network.

### M4: Hardening and rollout docs
Scope:
- full test pass (targeted + full suite where possible),
- gas/code size sanity checks,
- deployment/runbook notes,
- migration/indexing notes for app/backend teams.
- deployment scripting support for template registry sync (legacy factory -> `HooksFactoryRevolving`) with parity verification output.
- generate/export the Phase 1 machine-readable handoff artifact for downstream phases.

Exit criteria:
- release checklist complete,
- clear deployment and validation steps documented,
- scripted local anvil-fork deployment flow is documented and reproducible (including expected env vars and generated artifacts),
- template sync step (export/apply/verify) is documented for feature rollouts that introduce new factory deployments.
- handoff artifact schema and sample output are documented and validated in local workflow.

### M5: SDK dual-factory support
Scope:
- update SDK network deployment model to support legacy and revolving hooks factories,
- remove single-factory hardcoding in deploy/template wrappers,
- deploy routing policy: legacy deploys -> old `HooksFactory`, revolving deploys -> `HooksFactoryRevolving`,
- when market type is omitted, default route is legacy for backward compatibility; revolving requires explicit market-type selection,
- configure SDK to use the latest unified lens address per network as canonical read endpoint,
- ensure market-scoped factory reads can route by `market.factory()` where needed.

Testing:
- deploy flow tests targeting legacy and revolving factories,
- deploy flow tests proving unspecified market type routes to legacy,
- deploy flow tests proving explicit revolving market type routes to `HooksFactoryRevolving`,
- compatibility tests proving existing single-factory integrations still work,
- market read tests in mixed old/new factory environments.

Exit criteria:
- SDK deploys via correct factory by market type,
- SDK keeps backward-compatible behavior for callers that do not pass market type,
- SDK reads continue to work for markets from both factories,
- SDK onchain read paths point to latest unified lens address per network,
- no breaking API change for existing SDK consumers unless opted in.

### M6: Subgraph and indexing rollout
Scope:
- update subgraph data sources to index both legacy `HooksFactory` and `HooksFactoryRevolving`,
- preserve existing `MarketDeployed` entity/indexing behavior during rollout,
- derive and persist market type using datasource/factory-address context (no new typed deployment event dependency),
- validate that market discovery queries remain complete when both factories are active,
- document reindex/backfill requirements and production cutover order.

Testing:
- local/subgraph test run with markets deployed from both factories,
- regression test for existing market list queries and borrower market queries,
- parity check between subgraph market set and `ArchController.getRegisteredMarkets(...)`,
- check that `hooksFactory` linkage on market entities remains correct for mixed deployments.

Exit criteria:
- subgraph returns mixed-factory market sets with no missing markets,
- existing app/sdk market-list queries continue working unchanged,
- market type is queryable via derived factory-context mapping for both legacy and revolving markets,
- rollout runbook includes indexing and verification steps.

## Execution slices (step-by-step)
Execution policy:
- one slice per PR where feasible,
- each slice must pass its own validation commands before moving forward,
- do not start a dependent slice until predecessor exit criteria are met.

### Phase 1 slices (`v2-protocol`)
#### P1-S1: Revolving factory interface and skeleton
Depends on:
- none

Scope:
- add `IHooksFactoryRevolving` with narrow revolving deploy interface,
- add `HooksFactoryRevolving` skeleton with ownership/template registry parity behavior,
- define event surface (legacy `MarketDeployed` only for deploy event path).

Primary files:
- `src/IHooksFactoryRevolving.sol`
- `src/HooksFactoryRevolving.sol`
- `test/HooksFactoryRevolving.t.sol`

Validation:
- `forge build`
- targeted `forge test --match-path test/HooksFactoryRevolving.t.sol --block-timestamp $(date +%s)`

Exit criteria:
- compiles cleanly with interface/contract wiring,
- no typed deployment event introduced,
- legacy `HooksFactory` unchanged.

#### P1-S2: Revolving deploy path and validation rules
Depends on:
- `P1-S1`

Scope:
- implement revolving-only deploy path with `marketData` decode/version validation,
- enforce reject behavior for incompatible/legacy payloads,
- preserve `hooksData` passthrough semantics.

Primary files:
- `src/HooksFactoryRevolving.sol`
- `test/HooksFactoryRevolving.t.sol`
- shared test helpers if needed (`test/shared/Test.sol`, `test/helpers/Assertions.sol`)

Validation:
- targeted factory tests for success + reject paths,
- regression run for legacy factory tests (`forge test --match-path test/HooksFactory.t.sol --block-timestamp $(date +%s)`).

Exit criteria:
- revolving deploy succeeds with valid payload,
- malformed/legacy/incompatible payloads revert deterministically,
- legacy factory behavior regression-free.

#### P1-S3: Revolving market contract behavior
Depends on:
- `P1-S2`

Scope:
- implement `WildcatMarketRevolving` storage and logic (`drawnAmount`, `commitmentFeeBips`),
- keep `MarketState` unchanged and maintain ABI compatibility where required.

Primary files:
- `src/market/WildcatMarketRevolving.sol`
- `src/interfaces/IWildcatMarketRevolving.sol`
- relevant market base extension points (`src/market/WildcatMarketBase.sol` if needed)
- `test/market/WildcatMarketRevolving.t.sol`

Validation:
- targeted revolving market tests,
- legacy market regression subset (`test/market/WildcatMarket*.t.sol` as applicable).

Exit criteria:
- target revolving economics reproduced,
- no `MarketState` shape/size changes,
- legacy market tests still pass.

#### P1-S4: Unified lens market and borrower/template reads
Depends on:
- `P1-S3`

Scope:
- add revolving-only field visibility with presence flags,
- implement unified direct-read lens behavior (no delegation),
- implement borrower/template mode coverage across endpoint families,
- support factory-parameterized endpoints for targeted reads,
- support aggregated cross-factory endpoints with stable dedupe/order behavior.

Primary files:
- `src/lens/MarketLens.sol`
- `src/lens/MarketData.sol`
- `src/lens/HooksDataForBorrower.sol`
- `src/lens/HooksInstanceData.sol`
- `src/lens/HooksTemplateData.sol`
- `test/lens/MarketLensMultiFactory.t.sol` (or final chosen test file)

Validation:
- targeted lens test suite for mixed legacy/revolving populations,
- explicit tests for both borrower/template read modes.

Exit criteria:
- latest lens serves as single canonical read target,
- both granular and aggregated borrower/template reads pass and are deterministic.

#### P1-S5: Deployment scripting, template sync, and handoff artifact
Depends on:
- `P1-S4`

Scope:
- add deploy scripts for `HooksFactoryRevolving` and lens deployment,
- add template export/apply/verify scripts for cross-factory sync,
- output machine-readable handoff JSON (addresses, tx hashes, chain metadata, latest lens, factory->marketType map),
- document schema and local usage.

Primary files:
- `script/DeployHooksFactoryRevolving.sol` (or final naming)
- template sync script(s) in `script/` or `scripts/`
- docs/runbook updates
- optional `deployments/` artifact updates

Validation:
- local anvil-fork dry run end-to-end,
- validate produced JSON against documented schema.

Exit criteria:
- reproducible local deployment workflow documented,
- template sync and handoff artifact generation verified.

### Phase 2 slices (`wildcat.ts`)
#### P2-S1: Config model and routing primitives
Depends on:
- `P1-S5`

Scope:
- add dual-factory config model and market-type mapping primitives,
- add latest-lens-per-network config.

Primary files:
- `wildcat.ts/src/constants.ts`
- new routing helper(s) if needed

Validation:
- unit tests for config resolution and default behavior.

Exit criteria:
- resolves legacy/revolving factories and latest lens deterministically per network.

#### P2-S2: Deploy path routing behavior
Depends on:
- `P2-S1`

Scope:
- apply deploy routing with legacy-default behavior,
- route unspecified market type to legacy factory,
- route explicit revolving market type to `HooksFactoryRevolving`.

Primary files:
- `wildcat.ts/src/access/access-control.ts`
- `wildcat.ts/src/access/fixed-term.ts`
- deploy/controller call paths as needed

Validation:
- tests for both routing branches and backward compatibility.

Exit criteria:
- deploy routing policy matches D16 exactly.

#### P2-S3: Read-path lens adoption
Depends on:
- `P2-S2`

Scope:
- point onchain read paths to latest unified lens address,
- preserve compatibility for mixed market sets.

Primary files:
- `wildcat.ts/src/market.ts`
- any lens/read adapters

Validation:
- mixed-market read tests against local deployed stack.

Exit criteria:
- SDK reads succeed across legacy + revolving with canonical lens.

### Phase 3 slices (`wildcat-subgraph`)
#### P3-S1: Dual-factory datasource coverage
Depends on:
- `P2-S3`

Scope:
- index legacy and revolving factory deployments in manifests.

Validation:
- indexer startup + sync on local graph environment.

Exit criteria:
- both factory streams indexed.

#### P3-S2: Market type derivation and entity updates
Depends on:
- `P3-S1`

Scope:
- derive `marketType` from factory context mapping,
- persist in entities without typed deploy event dependency.

Validation:
- mapping tests / local query checks for derived market type.

Exit criteria:
- market type queryable for both factory populations.

#### P3-S3: Query compatibility and generated artifacts
Depends on:
- `P3-S2`

Scope:
- preserve existing query surfaces,
- regenerate GraphQL artifacts consumed by SDK/app.

Validation:
- regression queries + artifact generation check.

Exit criteria:
- existing app/sdk market list queries remain compatible.

### Phase 4 slices (`wildcat-app-v2`)
#### P4-S1: Config and endpoint adoption
Depends on:
- `P3-S3`

Scope:
- consume newest SDK config and unified lens/subgraph endpoints.

Validation:
- app boot + borrower/lender baseline flows.

Exit criteria:
- app resolves mixed-market data without manual endpoint switching.

#### P4-S2: Deploy flow behavior
Depends on:
- `P4-S1`

Scope:
- app deploy flows must follow SDK routing behavior,
- default to legacy deploy when market type is omitted,
- execute revolving deploy when revolving market type is explicitly selected.

Validation:
- UI/integration smoke tests for both deploy paths.

Exit criteria:
- deploy UX is backward-compatible and explicit for revolving.

#### P4-S3: Revolving visibility UX
Depends on:
- `P4-S2`

Scope:
- surface revolving-only fields in production paths where required.

Validation:
- borrower/lender smoke tests on local integrated stack.

Exit criteria:
- required revolving field visibility is present and accurate.

## Implementation guardrails
1. Do not modify `MarketState` shape or return sizes.
2. Do not add new hook flag bits/callbacks unless explicitly approved in M0.
3. Do not modify existing `HooksFactory` deploy behavior for legacy markets.
4. `HooksFactoryRevolving` must be revolving-only and reject incompatible/legacy deploy payloads.
5. Prefer additive interfaces/events over breaking changes.
6. SDK changes must preserve current behavior when only one factory is configured.
7. For revolving deploy paths, `hooksData` and `marketData` are independent: factory must decode `marketData` and pass `hooksData` to hooks without modification.
8. `HooksFactoryRevolving` deployment runbook must explicitly include ArchController registration steps (`registerControllerFactory(factory)` then `factory.registerWithArchController()`), plus verification calls.
9. Deployment scripts must produce deterministic artifacts for downstream phases (addresses by chain id/network, tx hashes, and ABI references).
10. Production rollout must include subgraph/indexer updates before enabling revolving deployments.
11. Do not modify inherited SphereX code unless required for confirmed toolchain compatibility and explicitly approved.
12. Canonical deployment policy must remain one active factory per market type.
13. Do not impose protocol-level template-type policy gates in `HooksFactoryRevolving`; template applicability remains borrower-driven.
14. SDK deploy APIs must preserve legacy-default behavior when market type is omitted.
15. Lens releases must be cumulative by visibility: latest lens must support all active market types.
16. Do not implement lens-to-lens delegation/chaining; latest lens must read contracts directly.
17. Do not add a typed deployment event in this rollout; keep `MarketDeployed` as the canonical deploy event and derive market type from factory context.
18. Keep template reuse support across factories via deployment scripting: provide template registry export/apply/verify tooling for new factory rollouts.
19. Deployment outputs must include a machine-readable handoff artifact consumable by SDK/subgraph/app automation (including latest lens and factory -> marketType mapping).
20. Unified lens must support both factory-parameterized and aggregated borrower/template reads; neither mode may be removed once shipped.

## Risks and mitigations
1. Risk: accidental behavior drift in legacy markets.
Mitigation: explicit legacy regression tests and keep old factory untouched.

2. Risk: dual-factory operational confusion (wrong deploy endpoint by market type).
Mitigation: strict SDK routing policy + protocol-side reject paths + runbook checks.

3. Risk: indexer/app assumptions about single factory address.
Mitigation: dual-factory indexing and `ArchController` parity checks.

4. Risk: partial support for revolving fields in lens/app.
Mitigation: phased rollout and compatibility fallback reads.

## Phase split
### Phase 1: Protocol rollout (`v2-protocol`)
Milestones included:
- M0, M1, M2, M3, M4.

Scope:
- New revolving-only factory + revolving market contract.
- Lens compatibility for mixed legacy/revolving market populations.
- Deployment/runbook/migration notes for protocol consumers.
- Primary repo/PR scope: `v2-protocol` only.

Out of scope:
- SDK deploy-path changes (handled in Phase 2).
- Subgraph/indexer implementation changes (handled in Phase 3).
- Frontend app integration changes (handled in Phase 4).

### Phase 2: SDK rollout (`wildcat.ts`)
Milestones included:
- M5.

Scope:
- Dual-factory configuration model.
- Deterministic factory selection by market type for deploy flows.
- Market-scoped routing where factory lookup is required.
- Primary repo/PR scope: `wildcat.ts` only.

Out of scope:
- Protocol contract changes.
- Subgraph/indexer implementation changes.
- Frontend app integration changes.

### Phase 3: Indexer/subgraph rollout (`wildcat-subgraph` + generated client artifacts)
Milestones included:
- M6.

Scope:
- dual-factory subgraph indexing and query compatibility,
- regeneration/update of dependent generated GraphQL artifacts consumed by SDK/app (mechanical sync PRs only; no SDK deploy-routing logic changes in this phase),
- Primary repo/PR scope: subgraph repository/manifests/mappings and generated client artifacts.

Out of scope:
- protocol contract changes,
- SDK deploy-path logic changes,
- borrower/lender UX integration changes unrelated to indexing correctness.

### Phase 4: App integration rollout (`wildcat-app-v2`)
Milestones included:
- post-M6 app wiring and rollout validation.

Scope:
- switch app deploy flows to SDK dual-factory-capable paths,
- adopt any required subgraph query updates after Phase 3,
- verify borrower/lender flows in mixed-factory environment.
- Primary repo/PR scope: `wildcat-app-v2` only.

Out of scope:
- protocol contract changes,
- SDK core deploy-routing logic changes,
- subgraph mapping/schema implementation changes.

## Estimated Scope of Contact
### Phase 1 expected files (protocol)
Expected new files:
- `src/HooksFactoryRevolving.sol`
- `src/IHooksFactoryRevolving.sol`
- `src/market/WildcatMarketRevolving.sol`
- `src/interfaces/IWildcatMarketRevolving.sol`
- protocol deployment scripts for revolving rollout (for example `script/DeployHooksFactoryRevolving.sol` and optional local-fork smoke deploy script)
- protocol template-sync script(s) for export/apply/verify between factories (exact file names TBD)
- `test/HooksFactoryRevolving.t.sol`
- `test/market/WildcatMarketRevolving.t.sol`
- `test/lens/MarketLensMultiFactory.t.sol` (name TBD)

Expected modified files:
- `.env` documentation/example files for protocol deployment inputs (sanitized; no private keys committed)
- `script/` or `scripts/` deployment scripts for local fork rollout and revolving factory wiring (exact file names TBD)
- `deployments/` entries (if persisted in-repo for local/testnet workflow)
- `src/market/WildcatMarketBase.sol` (extension points for alternate accrual behavior)
- `src/lens/MarketData.sol`
- `src/lens/HooksInstanceData.sol`
- `src/lens/HooksTemplateData.sol`
- `src/lens/HooksDataForBorrower.sol` (if borrower hooks discovery spans factory variants)
- `src/lens/MarketLens.sol` (or superseded by a new lens variant)
- `test/shared/Test.sol`
- `test/helpers/Assertions.sol`
- `test/helpers/ExpectedStateTracker.sol`

Files expected to remain unchanged:
- `src/libraries/MarketState.sol`
- `src/access/IHooks.sol`
- `src/types/HooksConfig.sol`
- `src/HooksFactory.sol` (legacy contract retained for compatibility)

### Phase 2 expected files (SDK)
Expected modified files:
- `wildcat.ts/.env.example` (or equivalent env template docs)
- `wildcat.ts/src/constants.ts`
- `wildcat.ts/src/access/access-control.ts`
- `wildcat.ts/src/access/fixed-term.ts`
- `wildcat.ts/src/market.ts`
- optional new routing helper (for deterministic market-type factory selection and market-scoped lookup)

### Phase 3 expected files (subgraph/indexing)
Expected modified files (repo/path names may vary by deployment setup):
- `wildcat-subgraph/.env.example` (or equivalent env template docs for local graph/indexing)
- `wildcat-subgraph/subgraph.yaml` (or per-network manifest files)
- subgraph mapping files that process factory deployment events
- generated GraphQL artifacts consumed by SDK/app (for example `wildcat.ts/src/gql/graphql.ts`)

### Phase 4 expected files (app)
Expected modified files:
- `wildcat-app-v2/.env.example` (or equivalent env template docs)
- `wildcat-app-v2/src/app/[locale]/borrower/create-market/hooks/useDeployV2Market.ts`
- `wildcat-app-v2/src/app/[locale]/borrower/hooks/getMaketsHooks/useGetBorrowerMarkets.ts`
- `wildcat-app-v2/src/app/[locale]/borrower/hooks/getMaketsHooks/useGetOthersMarkets.ts`
- `wildcat-app-v2/src/app/[locale]/borrower/hooks/useGetBorrowerHooksData.ts`
- any app query/wiring files that consume updated SDK/subgraph surfaces

## Deliverables checklist
### Phase 1 deliverables
- `docs/feat-rcf-v2-plan.md` finalized.
- `IHooksFactoryRevolving` interface/spec committed.
- `HooksFactoryRevolving` + tests.
- `WildcatMarketRevolving` + tests.
- lens compatibility updates + tests.
- deployment and migration notes.

### Phase 2 deliverables
- SDK dual-factory updates + tests.
- migration note for SDK consumers upgrading from single-factory assumptions, including explicit market-type opt-in for revolving deploys and legacy-default behavior.

### Phase 3 deliverables
- subgraph dual-factory indexing updates + validation.
- backward-compatible query verification for existing app/sdk market lists.

### Phase 4 deliverables
- app integration updates validated against mixed legacy/revolving factory environments.
- end-to-end borrower deployment and lender market-view smoke tests.

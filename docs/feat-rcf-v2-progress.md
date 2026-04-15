# feat/rcf-v2 progress

Date: 2026-03-17  
Last updated: 2026-03-17  
Status: Phase 2 started; `P2-S1` complete in `wildcat.ts`  
Branch target: `feat/rcf-v2`

Related plan: `docs/feat-rcf-v2-plan.md`
Archived source: `docs/feat-rcf-v2-progress-old.md`

## Overall status
- Phase 1 (`v2-protocol`) is implemented and validated locally.
- Phase 2 (`wildcat.ts`) is now in execution.
- Current position: `P2-S1` complete, `P2-S2` next.

## Tracker notes
- This document is the canonical progress tracker going forward.
- Historical Phase 1 execution notes were imported from `docs/feat-rcf-v2-progress-old.md`.
- The old coarse SDK tracker (`P2-S1` config, `P2-S2` deploys, `P2-S3` reads) is superseded by the current 10-slice Phase 2 plan and should be treated as obsolete naming only.

## Phase summary
| Phase | Repo | Status | Notes |
|---|---|---|---|
| Phase 1 | `v2-protocol` | Complete | Protocol-side revolving factory, market, unified lens, and deployment/runbook artifacts are in place |
| Phase 2 | `wildcat.ts` | In progress | SDK execution started on branch `feat/rcf-v2` |
| Phase 3 | subgraph repo | Not started | Waits on stable Phase 2 SDK surface |
| Phase 4 | `wildcat-app-v2` | Not started | Waits on protocol + SDK + subgraph readiness |

## Historical Phase 1 slice tracker
| Slice | Status | Updated | Notes |
|---|---|---|---|
| `P1-S1` | Complete | 2026-02-12 | Added `IHooksFactoryRevolving`, `HooksFactoryRevolving` scaffolding, and targeted tests |
| `P1-S2` | Complete | 2026-02-12 | Implemented revolving deploy path with strict `marketData` validation and reject semantics |
| `P1-S3` | Complete | 2026-02-13 | Implemented `WildcatMarketRevolving` and market extension seams with targeted tests |
| `P1-S4` | Complete | 2026-02-13 | Added unified mixed-factory lens reads and multi-factory coverage |
| `P1-S5` | Complete | 2026-02-13 | Added deployment scripts, template sync tooling, handoff tooling, and rollout docs |

## Slice tracker
| Slice | Status | Notes |
|---|---|---|
| `P2-S1` | Complete | Added additive SDK interfaces for `HooksFactoryRevolving` and `MarketLensV2_5`; regenerated `typechain`; aligned SDK lens struct names with protocol; no runtime behavior changes |
| `P2-S2` | Next | Add `marketType`, dual-factory config, and latest-lens routing primitives |
| `P2-S3` | Pending | Generalize deploy previews and add revolving `marketData` helpers |
| `P2-S4` | Pending | Open-term deploy routing |
| `P2-S5` | Pending | Fixed-term deploy routing |
| `P2-S6` | Pending | Market model enrichment |
| `P2-S7` | Pending | Direct-address read migration |
| `P2-S8` | Pending | Global market enumeration migration |
| `P2-S9` | Pending | Account and token read migration |
| `P2-S10` | Pending | Cleanup, compatibility shims, and smoke coverage |

## Latest completed work
### `P2-S1` SDK contract surface sync
Scope completed:
- added `wildcat.ts/contracts/HooksFactoryRevolving.sol`,
- added additive `wildcat.ts/contracts/MarketLensV2_5.sol`,
- regenerated `wildcat.ts/src/typechain/*` for the new interfaces,
- aligned the SDK lens naming with protocol semantics by splitting the base market read shape as `MarketDataBaseV2_5` and the additive RCF-aware shape as `MarketDataV2_5`,
- kept legacy `MarketLens` and `MarketLensV2` surfaces in place for now so this slice stays behavior-neutral.

Validation completed:
- `cd wildcat.ts && yarn codegen:typechain`
- `cd wildcat.ts && ./node_modules/.bin/tsc -p ./tsconfig.prod.json --noEmit`

Notes:
- `wildcat.ts` needed dependency installation before codegen would run.
- Existing Hardhat/SPDX warnings from older vendored contract files remain, but they did not block compile or type generation.

## Imported execution history
### 2026-02-12
- Completed `P1-S1` scaffolding in `v2-protocol`.
- Added `src/IHooksFactoryRevolving.sol`.
- Added `src/HooksFactoryRevolving.sol` with template/hooks-instance parity and stubbed deploy methods for the next slice.
- Added `test/HooksFactoryRevolving.t.sol` with wiring, template, and hooks-instance coverage.
- Validation:
- `forge test --offline -D never --match-path test/HooksFactoryRevolving.t.sol --block-timestamp $(date +%s)` passed (`5 passed, 0 failed`).

### 2026-02-12 (`P1-S2`)
- Implemented `deployMarket` and `deployMarketAndHooks` in `src/HooksFactoryRevolving.sol`.
- Added versioned `marketData` validation and dedicated errors:
- `InvalidMarketData()`
- `UnsupportedMarketDataVersion()`
- `InvalidCommitmentFeeBips()`
- Preserved hook-owned `hooksData` passthrough semantics.
- Added deploy success and reject-path coverage in `test/HooksFactoryRevolving.t.sol`.
- Validation:
- `forge test --offline --match-path test/HooksFactoryRevolving.t.sol --block-timestamp $(date +%s)` passed (`12 passed, 0 failed`).
- `forge test --offline --match-path test/HooksFactory.t.sol --block-timestamp $(date +%s)` passed (`30 passed, 0 failed`).
- `forge build --offline --force` passed (warnings only).

### 2026-02-13 (`P1-S3`, `P1-S4`)
- Completed `P1-S3`:
- added `src/market/WildcatMarketRevolving.sol` and `src/interfaces/IWildcatMarketRevolving.sol`,
- added legacy market extension seams in `WildcatMarketBase`, `WildcatMarket`, and `WildcatMarketWithdrawals`,
- added targeted tests in `test/market/WildcatMarketRevolving.t.sol`.
- Completed `P1-S4`:
- refactored lens helpers to use `IHooksFactory` for mixed-factory compatibility,
- added additive V2 market read surface and optional-field presence flags in `src/lens/MarketData.sol`,
- extended `src/lens/MarketLens.sol` with factory-parameterized and aggregated mixed-factory endpoints,
- added multi-factory lens coverage in `test/lens/MarketLensMultiFactory.t.sol`.
- Validation:
- `forge test --offline --match-path test/lens/MarketLens.t.sol --block-timestamp $(date +%s)` passed (`9 passed, 0 failed`).
- `forge test --offline --match-path test/lens/MarketLensMultiFactory.t.sol --block-timestamp $(date +%s)` passed (`7 passed, 0 failed`).
- Regression spot checks passed:
- `test/HooksFactory.t.sol` (`30 passed`),
- `test/HooksFactoryRevolving.t.sol` (`12 passed`),
- `test/market/WildcatMarketRevolving.t.sol` (`7 passed`).

### 2026-02-13 (`P1-S5`)
- Added deployment script helpers:
- `script/DeployScriptBase.sol`
- `script/DeployHooksFactoryRevolving.sol`
- `script/DeployMarketLens.sol`
- Added template sync tooling in `scripts/rcf-template-sync.js` with `export`, `apply`, and `verify` actions.
- Added handoff tooling:
- `scripts/generate-rcf-handoff.js`
- `scripts/validate-rcf-handoff.js`
- Added rollout docs:
- `docs/rcf-v2-deployment-runbook.md`
- `docs/rcf-v2-handoff.schema.json`
- Validation:
- `forge build --offline --force` passed.
- `node --check scripts/rcf-template-sync.js` passed.
- `node --check scripts/generate-rcf-handoff.js` passed.
- `node --check scripts/validate-rcf-handoff.js` passed.
- `node scripts/validate-rcf-handoff.js --input /tmp/rcf-handoff-smoke.json` passed.
- `node scripts/generate-rcf-handoff.js ... --output /tmp/rcf-handoff-generated.json` succeeded.
- `node scripts/validate-rcf-handoff.js --input /tmp/rcf-handoff-generated.json` passed.

### 2026-03-17 (`P2-S1`)
- Added additive SDK-side interfaces for `HooksFactoryRevolving` and `MarketLensV2_5` in `wildcat.ts/contracts`.
- Regenerated `wildcat.ts/src/typechain/*` for the new interfaces.
- Renamed the additive SDK lens structs to match the protocol semantic cleanup:
- base market read shape is now `MarketDataBaseV2_5`,
- additive RCF-aware market read shape is now `MarketDataV2_5`,
- removed the temporary collision artifact `MarketDataV2V2_5`.
- Kept legacy `MarketLens` and `MarketLensV2` surfaces in place to avoid runtime behavior changes in the ABI-sync slice.
- Validation:
- `cd wildcat.ts && yarn codegen:typechain`
- `cd wildcat.ts && ./node_modules/.bin/tsc -p ./tsconfig.prod.json --noEmit`

## Current assumptions / non-blockers
- Network addresses for new revolving deployments are intentionally deferred until deployment time.
- The latest unified lens interface is carried additively as `MarketLensV2_5` during the early SDK slices to keep review and rollback boundaries clean.
- Protocol semantic cleanup is complete: the additive lens structs are `MarketDataV2_5` and `OptionalUintDataV2_5`, while the `get*DataV2` function names remain unchanged to avoid ABI churn.

## Next slice
### `P2-S2` Config model and routing primitives
Planned focus:
- add SDK `marketType` separate from `MarketVersion`,
- add dual-factory config shape,
- add latest-lens-per-network config,
- add helper(s) to resolve factory by market type and market type by factory,
- keep deploy/read call sites unchanged in this slice.

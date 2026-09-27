# E21: lens coverage for the new market features

Source parent: `ea2729a` (E20). Status: complete.

The user requested exposing the new features through the lenses, including the
surfaces needed by later tranche integrations. Current market/hook/factory
behavior is the authority; the lenses must not implement a second lifecycle or
turn a stored default marker into a historical preview.

## Surface map

| Surface | Existing coverage | Work |
| --- | --- | --- |
| Current APR, reserves, accrued balances, borrower/principal transfers, revolving drawn amount and commitment fee | Full/live V2.5 data already exposes the relevant fields. | Preserve and test alongside the additions. |
| Repayment date, period, inclusive deadline, recorded default | Direct market getters only. | Shared lifecycle result in full and live V2.5 reads, including aggregation/facade routes; distinguish unavailable getters from valid zero terms. |
| Deposit capacity, borrowable assets, all debts, closed-market underlying surplus | Direct market getters/accounting only. | Shared liquidity result using market getters; amounts do not promise permission or successful token transfers. |
| Batch status and collectible withdrawal amount | Uses stored pending-batch identity and reports reserved funds as available before expiry. | Recognize early release by accrued automatic closure and report zero collectible amount while still pending. Preserve total lender claims separately. |
| Registered wrapper | Direct V2.5 market getter. | Include in full V2.5 configuration; do not label it as a future tranche vault. |
| Repayment parameter limits | Constraint tuple grew from ten words to twelve. | Decode old and current hooks safely, and identify whether repayment bounds were provided. |
| Hook creation-code commitment | Factory getter added in E16. | Include optional registered hash in template metadata, keeping factory provenance in scoped results. |
| Periodic withdrawal/proposal state | Term schedule and effective closure already exposed; proposal details are separate hook queries. | Include the current withdrawal-window query and optional proposal with its recorded response bounds. |
| Senior/junior shares, senior APR/floor and waterfall | No tranche implementation exists yet. | V2.6 contracts supply those interfaces later; do not invent them here. |

The new lens deployment has updated return tuples. Consumers must regenerate
their decoders; unchanged input selectors do not imply unchanged return ABIs.
Older markets/hooks/factories remain readable where their existing interfaces
are supported. Optional additions must not report an absent getter as a real
zero-valued policy. Default timestamps remain committed state even when the
same response contains accrued closure or repayment-state previews.

## Plan and tracker

| Task | Scope | Status |
| --- | --- | --- |
| E21-01 | Shared lifecycle/liquidity reads, full/live/facade/aggregation propagation, and real-market boundary regressions. | Complete; real-market boundary and route tests pass in all three profiles. |
| E21-02 | Constraint compatibility, artifact commitments, and hook query coverage, with malformed/legacy-response tests. | Complete; legacy/malformed responses, factory provenance, and proposal views are covered. |
| E21-03 | Maintained interface documentation, ABI/size review, ordinary full suites and strict deployment qualification. Signed kethcode checkpoint, no push. | Complete; 869 tests pass per profile, strict deployments and production sizes pass. |

Preserve all market and factory code and the E20 compiler settings. Recheck lens
runtime size as the tuples grow. Keep the user's reference documents untracked.

## Implementation and qualification notes

- The additions share full/live lifecycle and liquidity fillers. They read the
  market's terms, marker, and accounting getters; no lifecycle replay is copied
  into the lens. Registered wrapper data is configuration, not a tranche-vault
  identification mechanism.
- Optional one-word reads copy only one word. The current constraint decoder
  copies twelve words and accepts a complete legacy ten-word tuple with explicit
  padding. Solidity's ABI decoder still validates the integer widths. The
  periodic proposal probe copies four words; unavailable responses stay absent.
- Hook-template commitments retain their factory scope. The existing
  deduplicated endpoints continue selecting the first encountered record.
- The initial focused run passes all 38 lens tests. The first full run passes
  866 and fails two existing production-matrix tuple expectations, which left
  the new availability flags/hash at zero. Extend their independent expected
  tuples, including the hash of the stored creation code and periodic closure
  window; retain the complete-tuple comparisons.
- Incremental default and deployment builds produced different aggregator
  bytecode despite matching optimizer settings. Qualification therefore includes
  clean builds with the complete source graph before comparing artifacts. Both
  clean builds compile 315 files and match every lens byte-for-byte, including
  their ABIs. All ten existing market/factory/hook/composition artifacts still
  match E18/E20 exactly. The incremental comparison remains archived; use clean
  builds when producing deployment artifacts.
- Repository-wide `npm run lint:check` stops on 26 existing formatting failures.
  Each flagged file is byte-for-byte identical to source parent `ea2729a`.
  Changed Solidity files pass Prettier and Solhint; three existing import-line
  length warnings remain. Preserve the failed command and baseline evidence.
- The first actual-limit invocation passes both existing market deployment
  tests, but cannot create the 35,126-byte lifecycle test harness. The four
  production lenses fit. Add a small `MarketLensDeploymentTest` that deploys
  all four lenses against the real production stack and compares direct/facade
  return bytes for both market families. Keep the larger scenario suite and
  its decoded-field assertions in the ordinary full runs; do not raise the
  strict deployment limit.

Maintained consumer documentation lives in
[market lenses](../../integrations/lenses.md). Large receipts and logs are
outside the repository at
`/home/kethcode/wildcat/bytecode-research/2026-09-27/e21-lens-feature-surfaces/`.

## Clean deployment sizes

| Contract | Runtime bytes | Headroom below 24,576 |
| --- | ---: | ---: |
| `MarketLens` | 4,512 | 20,064 |
| `MarketLensCore` | 20,991 | 3,585 |
| `MarketLensAggregator` | 21,997 | 2,579 |
| `MarketLensLive` | 5,777 | 18,799 |

Both profiles produce these same binaries. No market, factory, or hook source
changes are included. Their runtime/creation bytecode, ABIs, and existing size
margins remain unchanged.

## Final qualification

| Command | Result |
| --- | --- |
| `forge build --force` and `FOUNDRY_PROFILE=deploy forge build --force` | Both clean builds pass; lens bytecode and ABI match between profiles. |
| `forge test --summary` | 869 pass, zero failed/skipped, 72 suites. |
| `npm run test:fixed -- --summary` | 869 pass, zero failed/skipped, fixed timestamp and seed. Same package script as `yarn test:fixed`; Yarn is unavailable here. |
| `FOUNDRY_PROFILE=deploy forge test --summary` | 869 pass, zero failed/skipped, 72 suites. |
| `FOUNDRY_PROFILE=deploy forge test --match-contract '^(SingleStorageDeploymentTest\|MarketLensDeploymentTest)$' --code-size-limit 24576 -vv` | Three tests pass: twelve existing factory/market/hook combinations, plus all four lenses reading both market families through their facade. |
| `FOUNDRY_PROFILE=deploy forge build --sizes src` | Every production runtime and creation payload fits. |
| Prettier and Solhint on every changed Solidity file | Pass; existing import-line warnings only. |

Each final full run includes the three existing invariant campaigns at 2,000
runs and depth 30: 540,000 calls across the three profiles, zero handler reverts.
The 10,896-byte deployment harness is added after the clean builds and passes
the strict limit; the final full runs include it. All four lens artifact hashes
are checked again after qualification and still match the clean builds. The
other ten measured artifacts retain their exact qualified creation/runtime
bytecode and public ABIs.

No existing assertion is removed or weakened. The two older tuple expectations
are extended for the new fields, and lens coverage gains 17 additional tests.
[results/e21.json](./results/e21.json) records the final results, the initial
expectation/harness failures and their resolutions, artifact hashes, and the
pre-existing repository formatting failures.

The lens changes are ready for review on this branch. SDK/application return
decoders and deployed lens addresses must be updated when adopting them.
Deployment-ceremony/fork rehearsal, gas measurements, final inventory,
audit/refreeze review, downstream indexing, and release-document cleanup remain
separate work. No tranche vault or tranche policy is implemented here.

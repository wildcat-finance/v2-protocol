# Engineering Backlog

Deferred tasks noted during the v2.5 pre-release cleanup pass (July 2026).
These are not release blockers; they are queued for after the doc pass.

## Deployment scripts for the v2.5 release

`script/DeployPeriodicTermHooksV21.sol` is deprecated: it targets the v2.1
rollout and predates the five-argument `MarketLens` constructor, so it fails
if run. The v2.5 release (RCF + PTH + lens set) needs updated deployment
scripts.

- Reuse the inventory-management pattern from `script/deploy/DeployMarketLens.sol`
  (labeled artifacts, canonical aliases, post-deploy wiring validation) — this
  direction is confirmed as correct.
- Evaluate whether the monolithic rollout-script model is right, or whether
  per-component scripts composed by a thin orchestrator would be easier to
  operate and audit.
- Delete `DeployPeriodicTermHooksV21.sol` once the replacement exists.

## prettier-plugin-solidity upgrade

`prettier-plugin-solidity` is pinned at 1.1.3 (2023). It cannot parse
file-level events (solidity 0.8.22+), which forced a `.prettierignore` entry
for `test/shared/mocks/MockHooks.sol`.

- Upgrade prettier + the plugin, re-run formatting over the repo, and verify
  the reformat is bytecode-identical (`forge build` artifact hash comparison,
  as done during the v2.5 cleanup).
- Supply-chain caution: pin exact versions, review the published tarballs and
  their provenance before installing, and avoid installing during an active
  npm incident window.
- Remove the `MockHooks.sol` entry from `.prettierignore` afterward.

## Wildcat4626Wrapper branch-coverage test pass

The wrapper sits at ~26/41 branch coverage: the vendored a16z ERC4626 property
suite does not exercise Wildcat-specific limit logic (`maxDeposit`/`maxMint`/
`maxRedeem`, `decimals`, `assetsPerShareRay`/`sharesPerAssetRay`, virtual-share
paths). The wrapper is in the EIP-4626 audit scope, so this deserves a careful
dedicated pass rather than a quick fill.

### Running coverage

`forge coverage` cannot parse `SphereXProtectedRegisteredBase.sol` as written
(its analyzer cannot resolve a modifier that takes the function's named return
value as an argument). A semantically identical inline of that modifier is
kept as `docs/coverage-spherex.patch` — it is deliberately never committed to
the source file because it is not bytecode-identical. Procedure:

```
git apply docs/coverage-spherex.patch
FOUNDRY_FUZZ_RUNS=32 FOUNDRY_INVARIANT_RUNS=8 FOUNDRY_INVARIANT_DEPTH=15 \
  forge coverage --no-match-coverage "(^test/|^script/|^lib/)" \
  --report summary --report lcov
git checkout -- src/spherex/SphereXProtectedRegisteredBase.sol
```

The run caps keep the instrumented build tractable; the anchored exclusion
regex matters (an unanchored `lib` also excludes `src/libraries`). Consider
wiring this procedure into the `coverage` script in package.json, and remove
the patch if a future foundry release fixes the analyzer.

## Lens

- `MarketLensCore` and `MarketLensLive` store `archController` / `hooksFactory`
  immutables they never use internally. Kept for constructor uniformity and
  off-chain discoverability; drop them if the SDK ends up not reading these
  getters.

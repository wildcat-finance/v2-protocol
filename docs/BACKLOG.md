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

## Wildcat4626Wrapper branch-coverage test pass — DONE

Completed in `test/vault/Wildcat4626WrapperGuards.t.sol` (50 tests): 37/41
branches. The four residuals are accounted for: three revert guards proven
unreachable for `scaleFactor >= RAY` (mint round-trip at Wildcat4626Wrapper
~L294, redeem ceil-to-zero ~L359, sweep ceil-to-zero ~L391 — each pinned
positively instead), and one forge-coverage attribution artifact on
`_beforeTokenTransfer`'s zero-amount early return, whose both behaviors are
directly asserted by passing tests. `_useVirtualShares`/`_underlyingDecimals`
are structurally required base-class overrides with no reachable call path
(all conversion entry points are overridden).

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

## Minimum-deposit check consolidation

The scaled-space minimum-deposit check is triplicated across the three hook
templates (with a shared comment block). All three inherit
MarketConstraintHooks, which could host a single helper so the next rounding
adjustment cannot be applied to one template and missed in the others.
Deferred because hoisting moves the `DepositBelowMinimum` declaration and
touches test error references late in the release cycle.

## Dead half-up scaleAmount removal

`MarketState.scaleAmount` (half-up) has no callers in src/ since the v2.5
floor-rounding change; `test/libraries/MarketState.t.sol` still tests it.
Remove both — a future dev reaching for `scaleAmount` instead of
`scaleAmountDown` would recreate the 4626-wrapper bug class inside the
protocol. Deferred to keep the pre-audit fix diff minimal.

## Lens

- `MarketLensCore` and `MarketLensLive` store `archController` / `hooksFactory`
  immutables they never use internally. Kept for constructor uniformity and
  off-chain discoverability; drop them if the SDK ends up not reading these
  getters.

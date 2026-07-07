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

## Lens

- `MarketLensCore` and `MarketLensLive` store `archController` / `hooksFactory`
  immutables they never use internally. Kept for constructor uniformity and
  off-chain discoverability; drop them if the SDK ends up not reading these
  getters.

# Engineering Backlog

Deferred tasks noted during the v2.5 pre-release cleanup pass (July 2026).
These are not release blockers; they are queued for after the doc pass.

## Deployment scripts for the v2.5 release — PARTIALLY DONE

The ordered `script/deploy/v2-5/01` through `09` flow now covers the wrapper factory, standard and revolving factories, borrower identity registry, lens, owner actions, registration, plan generation, inventory finalization, and canary market. The market-transfer checkpoint updated factory and lens deployment inputs for the identity registry.

This is still not the final ceremony package. It must be regenerated and independently rehearsed after hooks/providers, RCF draw fees, and the event/lens hard cut are complete.

`script/DeployPeriodicTermHooksV21.sol` remains deprecated: it targets the v2.1 rollout and predates the current `MarketLens` constructor.

- Delete `DeployPeriodicTermHooksV21.sol` after confirming no remaining operator documentation or automation references it.
- Regenerate the v2.5 ceremony package only after the remaining release-blocking contracts and ABIs are frozen.

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
the source file because it is not bytecode-identical. The tracked coverage
command applies the patch temporarily and verifies that the source is restored. Run it against a
focused family whose production graph the coverage compiler supports, for example:

```
FOUNDRY_TEST=test-next/sanctions yarn coverage --match-contract SanctionsTest
```

The run caps keep the instrumented build tractable; the anchored exclusion
regex matters (an unanchored `lib` also excludes `src/libraries`). Remove the
patch if a future Foundry release fixes the analyzer. Production graphs that
include `HooksFactoryRevolving` still exceed Forge's non-IR coverage compiler;
their canonical via-IR tests and focused coverage status are recorded in the
replacement parity ledgers.

## Minimum-deposit check consolidation

The scaled-space minimum-deposit check is triplicated across the three hook
templates (with a shared comment block). All three inherit
MarketConstraintHooks, which could host a single helper so the next rounding
adjustment cannot be applied to one template and missed in the others.
Deferred because hoisting moves the `DepositBelowMinimum` declaration and
touches test error references late in the release cycle.

## Minimum-deposit deployment documentation

Document the creation-time deposit-hook constraint in the SDK, app deployment
flow, and user-facing market configuration guidance. A positive initial
minimum enables `onDeposit` automatically. If a market starts with a zero
minimum but may need a positive minimum later, `onDeposit` must still be
enabled at creation because the market's hook dispatch flags cannot be changed
after deployment.

## Hooked-market ABI unification

OpenTermHooks and FixedTermHooks currently track whether deposit-hook dispatch
is enabled in a private `_depositHookEnabled` mapping, preserving their
historical `HookedMarket` getter ABIs. PeriodicTermHooks stores the equivalent
`depositHookEnabled` value in its public `HookedMarket` struct. This is an
intentional v2.5 compatibility choice, not the desired long-term precedent for
each new hooks type.

Before the next hooks-template release, review the current lens, SDK,
subgraphs, app, and historical deployed hooks together and choose a versioned
ABI strategy. In particular, evaluate adding `templateVersion()` to OpenTerm
and FixedTerm, supporting both legacy and revised tuples in the lens, and
normalizing shared hooked-market fields across hook types. The review must
also cover the dynamic-array getter encoding and direct SDK/subgraph reads;
checking only the single-market lens path is insufficient.

## Lens

- `MarketLensCore` and `MarketLensLive` store `archController` / `hooksFactory`
  immutables they never use internally. Kept for constructor uniformity and
  off-chain discoverability; drop them if the SDK ends up not reading these
  getters.

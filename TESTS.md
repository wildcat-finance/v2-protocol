# Testing

The canonical protocol suite lives in [`test/`](./test/). Deployment-format
comparisons and lifecycle invariants are part of that tree, not an alternate
release-test profile. Standalone gas and optimizer research uses fixtures under
`scripts/research/fixtures/`; those do not replace the canonical suite.

## Required commands

Install the pinned Foundry toolchain using the [build setup](./README.md#build-and-test).

```sh
forge test
yarn test:fixed
FOUNDRY_PROFILE=deploy forge test
```

- `forge test` is the default for local work and CI.
- `yarn test:fixed` uses a fixed timestamp and fuzz seed. Use it when you need a
  repeatable audit run.
- `FOUNDRY_PROFILE=deploy forge test` runs the same suite with the deployment
  artifact settings.

[`foundry.toml`](./foundry.toml) pins Solidity `0.8.25`, Cancun, via-IR,
optimizer runs `1`, and the exact Yul optimizer sequence. Normal builds, tests,
and the `deploy` profile share these settings. The market runtime-size tests
enforce the deployment limit under that configuration.

The configuration explicitly enables call isolation and dynamic test linking,
the defaults adopted with Foundry 1.8.3. Isolation gives top-level test calls
separate transaction contexts, so gas comparisons must preserve that setting
and distinguish direct test calls from callbacks nested inside market actions.
Deployment fixtures continue to use production artifacts and the real factory
paths where deployment identity and behavior are under test.

The complete suite also uses Python 3 and a local C compiler (`cc`) for the
offline [storage-codec reference](./test/reference/fastlz/README.md). Foundry FFI
is enabled in the repository configuration. That reference qualifies the
historical compression comparison; current deployment tooling selects raw or
split storage.

## Deployment tooling

Install the locked root and deployment-UI JavaScript dependencies, then run:

```sh
yarn install --frozen-lockfile --ignore-scripts
npm --prefix deploy-ui ci --ignore-scripts
node --test scripts/__tests__/*.test.js
npm --prefix deploy-ui test
npm --prefix deploy-ui run build
```

These cover plan commitments, template registration, handoff records, predicate
verification and the UI executor. They supplement the contract suite. A release
also needs the [deployment rehearsal](./docs/operations/deployment.md#release-workflow)
on a pinned target-chain fork with the actual frozen plan.

See [`test/README.md`](./test/README.md) for suite ownership, fixture rules,
stateful testing, and the focused coverage boundary.

## What tests should cover

- Give each behavior domain one owning suite. Don't multiply entrypoints through
  test inheritance.
- Cover authorization, success, reverts, events, boundaries, rounding, and state
  transitions where they apply.
- Test shared implementations through runtime matrices. Give distinct behavior
  its own properties.
- Keep mocks small and assertions explicit. Use real deployment paths when a
  test depends on constructors, immutables, CREATE2, or registration.
- Every bug fix needs a regression that fails against the unfixed code.

Library wrappers under `test/libraries/wrappers/` expose internal library
functions when a test needs an external call for a revert, event, or coverage
assertion. They are test infrastructure, not protocol interfaces.

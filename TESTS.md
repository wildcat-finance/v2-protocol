# Testing

The Foundry suite lives in [`test/`](./test/). It is the only protocol test
suite. There is no legacy suite, parity oracle, or alternate discovery profile.

## Required commands

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

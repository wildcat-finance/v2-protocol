# Testing

The canonical Foundry suite lives in [`test/`](./test/). There is no legacy
suite, parity oracle, or alternate discovery profile.

## Required Commands

```sh
forge test
yarn test:fixed
FOUNDRY_PROFILE=deploy forge test
```

Plain `forge test` is the local-development and CI contract. The fixed lane
adds a stable timestamp and fuzz seed for repeatable audit evidence. The deploy
lane proves the same suite under deployment artifact settings.

See [`test/README.md`](./test/README.md) for suite ownership, fixture rules,
stateful testing guidance, and the focused coverage boundary.

## Test Design Contract

- Give each behavior domain one concrete owning suite; do not multiply test
  entrypoints through inheritance.
- Cover authorization, success, revert, event, boundary, rounding, and state
  transition behavior where they apply.
- Test common implementations through runtime matrices and distinct semantics
  through distinct properties.
- Keep mocks capability-sized and assertions explicit. Production deployment
  paths remain real when constructor, immutable, CREATE2, or registration
  behavior is under test.
- Add a regression for every corrected bug and verify that it fails against
  the unfixed implementation.

Library wrappers under `test/libraries/wrappers/` expose internal library
functions where external calls are needed for revert, event, or coverage
assertions. They are test infrastructure, not protocol interfaces.

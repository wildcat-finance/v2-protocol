# Testing

The canonical protocol suite lives in [`test/`](./test/). Deployment-format
comparisons and lifecycle invariants are part of that tree. This audit branch
retains the release suite except tests and matrix cases for excluded providers;
see the [scope and test accounting](./docs/releases/v2.5-audit-scope.md).

## Required commands

Install the pinned Foundry toolchain using the [build setup](./README.md#build-and-test).

```sh
forge test
forge test --block-timestamp 1724284800 --fuzz-seed 0x5eed --summary
FOUNDRY_PROFILE=deploy forge test
```

- `forge test` is the default for local work and CI.
- The second command uses a fixed timestamp and fuzz seed for a repeatable
  audit run. `yarn test:fixed` is an optional alias for it.
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

## Focused development

After the initial compile, run one suite or regression without forcing a clean
build:

```sh
forge test --match-path test/market/RepayExpiryDelinquency.t.sol
forge test --match-test test_wildcatDebtTokenCannotAuthorizeDepositsIntoItsOwnMarket -vvv
```

`--match-path` and `--match-test` select execution; the canonical compilation
graph still makes artifacts available to fixtures that use `vm.getCode`.
Keep that graph for regression work unless you have checked the fixture's
artifact dependencies. A changed Solidity dependency may still require a
substantial compile. Run the full suite before handing back a finding or fix.

`LiveBalanceRoleProviderMock` deliberately imports the pinned Solady
`MerkleProofLib` even though its credential checks do not call that library.
The original provider suite brought this source into the compiler input.
Removing it changes compiler-generated identifiers and the optimized lens
bytecode under Solidity 0.8.25. Keep the import when reproducing the package's
canonical artifacts; source-only or otherwise narrowed builds have a different
input graph and may emit different bytecode.

The installation constructors and their Solidity regression helpers remain.
Ceremony, inventory, and deployment-UI programs are excluded; operational
rehearsal belongs to the release repository.

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

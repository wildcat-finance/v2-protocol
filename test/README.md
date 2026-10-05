# Canonical Foundry suite

`test/` is the canonical protocol test tree. It uses the default production build's:

- Solidity and EVM versions.
- Optimizer settings.
- via-IR setting.
- Metadata settings.

Plain `forge test` needs no timestamp, seed, profile, or environment setup.

The default, fixed-seed, and `deploy` runs use optimizer runs `1` and the
exact Yul sequence pinned in [`foundry.toml`](../foundry.toml). The suite
includes the market and hook artifact limits and the real factory deployment
matrix. Keep those checks enabled when changing compiler settings.

## Commands

```sh
# Canonical local and CI boundary
forge test

# Reproducible timestamp and fuzz seed
yarn test:fixed

# Deployment-profile confirmation
FOUNDRY_PROFILE=deploy forge test

# Focused coverage (see Coverage boundary for limits)
FOUNDRY_TEST=test/sanctions yarn coverage --match-contract SanctionsTest
```

## Structure

- `access/`, `providers/`, `root/`, and `sanctions/`: Authority, credentials,
  registry, and sanctions behavior.
- `factories/`, `market/`, and `vault/`: Deployment matrices and production
  market or wrapper behavior.
- `integration/` and `invariants/`: Cross-contract lifecycles, economic
  scenarios, and stateful properties.
- `libraries/`, `types/`, `lens/`, and `spherex/`: Focused unit and boundary
  tests.
- `research/`: Stored-initcode integrity, format comparisons and deployment
  limits. These executable regressions remain in the canonical suite even when
  working research documents are archived.
- `mocks/` and `shared/`: Capability-sized fixtures and test-only
  infrastructure. No test entry points.

## Adding and changing tests

- Put `test*` and `invariant*` entry points only on concrete domain suites.
  Shared behavior belongs in internal scenario or assertion helpers. Do not
  inherit test functions.
- Use the smallest fixture that proves the behavior. Keep real factory and
  CREATE2 paths where deployment is the behavior under test.
- Exercise equivalent implementations with runtime matrices. Split properties
  only when behavior intentionally differs.
- Tests that warp inside one call must read time with
  `vm.getBlockTimestamp()`. Tests needing a non-default initial timestamp must
  establish it in their fixture. The compiler can treat `block.timestamp` as
  constant within a call, even when a cheatcode changes the clock.
- Every bug fix needs the smallest regression that fails without it. Prefer
  assertions over logs and explicit revert expectations over
  `testFail_*` naming.

## Lifecycle and deployment coverage

The market matrix checks ordinary-market properties. Separate repayment and
penalty campaigns check inclusive cutoffs, observed-funding history, cure/reset
behavior, closure and final withdrawal allocation against independent models.
Preserve the assertions and configured run/depth budgets when changing lifecycle
code.

`LifecycleFixture` deploys the complete `LifecycleHandler` through `_deployCode`.
This runs its real constructor without embedding the handler's creation code in
each concrete suite. Keep the explicit handler import so focused builds produce
the artifact. Its inheritance from `MarketMatrixHandler` and its constructor's
creation of the immutable `LifecycleReference` remain: the campaigns need both
the shared actions and the independent timeline model.

Normal production fixtures choose raw storage for fitting artifacts and split
storage for larger ones. Explicit compressed controls preserve the comparison
and factory hash-check regressions. Size checks and strict deployment harnesses
enforce the real 24,576-byte runtime limit; a larger allowance for test contracts
does not qualify a production artifact for deployment.

## Coverage boundary

`scripts/coverage.sh`:

1. Applies `scripts/coverage-spherex.patch` temporarily.
2. Runs a focused non-via-IR coverage build.
3. Restores the source on every exit path.
4. Verifies the source stayed clean.

Set `FOUNDRY_TEST` to a narrow test directory or a single `.t.sol` file. The
coverage profile has an empty source root, so narrowing test discovery also
narrows the compilation graph. A `--match-contract` filter alone does not do
that. For example:

```sh
FOUNDRY_TEST=test/libraries/FeeMath.t.sol yarn coverage \
  --report lcov --report-file /tmp/fee-math.lcov
```

The wrapper uses 32 fuzz runs and invariant budgets of 8 runs at depth 15.
These smaller coverage budgets supplement the canonical suite; they do not
replace its 1,000 fuzz runs or 2,000 invariant runs at depth 30.

Whole-suite accurate coverage is not supported. The 2026-10-05 check found:

- Non-via-IR stack limits in `HooksFactoryRevolving`, `BaseHooks.t.sol`, and
  `LifecycleOracle` block their importing graphs.
- Some focused fixtures load artifacts by string with `vm.getCode`. A narrow
  graph can omit those artifacts even though the complete canonical suite
  builds them. `MarketTransitionLayoutTest`, for example, needs the
  `OpenTermHooks` artifact through `MarketFixture`.
- `AprValidationTest` includes a production artifact-size assertion that fails
  under coverage's different compiler settings. Keep the canonical size gate;
  coverage compilation does not qualify deployment sizes.
- A whole-suite `--ir-minimum` attempt also failed with a Yul stack error. That
  mode additionally warns about inaccurate source maps.

Coverage for `SphereXProtectedRegisteredBase` uses its temporarily patched
source and bytecode. The patch is only for coverage; deployment builds use the
original source.

This does not affect the default via-IR build, canonical tests, invariants, or
deployment-profile tests. Foundry may still print a non-fatal
`unresolved symbol locals` diagnostic for the SphereX modifier during normal
compilation.

## Static analysis

Use the qualified
[Slither function-library-resolution fork](https://github.com/wildcat-finance/slither/tree/fix/function-library-resolution)
and its qualification instructions. Pin the runtime revision: the qualified
fork and an unpatched installation can both report version `0.11.6`.

## Recorded results

The [2026-10-05 test review](../docs/releases/test-review-2026-10-05.json)
records source identities, tool versions, commands, coverage inputs, and
results. Its `maintenanceFollowUp` section records the timestamp-read cleanup
and artifact-based lifecycle fixture deployment, including their verification.

That follow-up passed 958 reported tests across 87 suites. Each of the three
stateful campaigns completed 2,000 runs and 60,000 calls without handler
reverts. Forge groups the market matrix's nine invariant properties into one
campaign; the source contained 955 test functions and 11 invariant properties.
Compilation took 261.27 seconds and the full run took 414.02 seconds on the
recorded machine.

The receipt's coverage results cover six test families and 31 individual-file
runs. They are partial and predate the maintenance follow-up. The Slither
result covers parser, SlithIR, and SSA compatibility; security detectors were
not run or triaged. Use each result with its recorded source and toolchain.

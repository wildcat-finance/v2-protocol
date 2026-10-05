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

This suite replaced a frozen, inheritance-heavy oracle after a
property-by-property review. The migration evidence remains in Git history.
Parity tooling is not ongoing infrastructure.

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

At the V2.5 cutover, the canonical run contained 682 tests across 46 suites.
Those counts are a historical baseline, not a growth limit.

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

## Maintenance rules

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

The original market matrix retains its ordinary-market properties. Separate
repayment and penalty campaigns check inclusive cutoffs, observed-funding
history, cure/reset behavior, closure and final withdrawal allocation against
independent models. Keep the original assertions and the configured run/depth
budgets when changing lifecycle code.

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

The refreshed SphereX patch passed application and restoration checks on
successful and failed runs. Coverage for `SphereXProtectedRegisteredBase`
refers to its temporarily patched source and bytecode, not a deployment build.

This does not affect the default via-IR build, canonical tests, invariants, or
deployment-profile tests. Foundry may still print a non-fatal
`unresolved symbol locals` diagnostic for the SphereX modifier during normal
compilation.

## Review checkpoint: 2026-10-05

The [test review receipt](../docs/releases/test-review-2026-10-05.json) pins
source `8ae329c5519aede7aeabd7a51082e79cb227396e`, tool versions, commands,
coverage inputs and results. It records a local test baseline, not a deployment
or audit attestation.

- A forced fixed-seed run passed 958 reported tests across 87 suites. Compilation
  took 288.33 seconds; total wall time was 442.89 seconds. The three stateful
  campaigns each completed 2,000 runs and 60,000 calls without handler reverts.
  Forge groups the market matrix's nine invariant properties into one campaign;
  the source contains 955 test functions and 11 invariant properties.
- No inherited test entry points or entry points in shared fixtures were found.
  Test-side creation bytecode totals 2,539,755 bytes. The deepest fixture chain
  has five ancestors; it composes lifecycle capabilities rather than inheriting
  test functions. Direct creation of the large lifecycle handler in four suites
  was identified as a compile-cost candidate.
- Fourteen tests combined warps with direct `block.timestamp` reads. They passed
  this run, but did not follow the time-read rule above.
- Six complete test families and 31 additional individual-file runs produced
  usable coverage. Their union is partial: missing factory and lifecycle
  instrumentation must not be presented as a whole-protocol percentage or as
  proof those behaviors have no tests.
- The qualified Slither fork is distinct from an unpatched global installation,
  even though both report version 0.11.6. Use the
  [function-library-resolution fork](https://github.com/wildcat-finance/slither/tree/fix/function-library-resolution)
  and its qualification instructions; pin the runtime revision, not only the
  version string. The parser, SlithIR and SSA check passed with partial analysis
  disabled and assembly included. Security detectors were not run or triaged.

The earlier three-to-four-minute baseline used a smaller suite, different
compiler settings and a different CPU. These measurements do not establish a
like-for-like performance regression.

### Maintenance follow-up

The receipt's `maintenanceFollowUp` section pins the subsequent test changes by
file hash and records their checks. All 14 flagged tests now use
`vm.getBlockTimestamp()`, as do two additional setup/helper cases found by
extending the scan beyond test entry points. No function body in that scan
still combines a direct timestamp read with a time-warp call.

Artifact deployment removed 228,451 bytes of repeated creation code across the
four lifecycle suites. The handler, reference model and all 129 production
artifacts kept identical creation/runtime bytecode and ABI. The full run again
passed 958 reported tests across 87 suites, with unchanged invariant budgets
and per-action call counts. Compilation took 261.27 seconds; total wall time was
414.02 seconds. The 15 affected test entry points also passed with Foundry's
default initial timestamp of 1, including the setup branch that advances an
early clock. The baseline coverage figures above were not refreshed by this
maintenance run.

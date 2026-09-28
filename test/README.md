# Canonical Foundry suite

`test/` is the only protocol test tree. It uses the default production build's:

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

# Focused accurate coverage
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
  establish it in their fixture.
- Every bug fix needs the smallest regression that fails without it. Prefer
  assertions over logs and explicit revert expectations over
  `testFail_*` naming.

## Lifecycle and deployment coverage

The original market matrix retains its ordinary-market properties. Separate
repayment and penalty campaigns check inclusive cutoffs, observed-funding
history, cure/reset behavior, closure and final withdrawal allocation against
independent models. Keep the original assertions and the configured run/depth
budgets when changing lifecycle code.

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

Set `FOUNDRY_TEST` to a narrow test directory. Whole-suite accurate coverage is
not supported. Production graphs containing `HooksFactoryRevolving` exceed the
non-via-IR compiler's stack limits.

This does not affect the default via-IR build, canonical tests, invariants, or
deployment-profile tests. Foundry may still print a non-fatal
`unresolved symbol locals` diagnostic for the SphereX modifier during normal
compilation.

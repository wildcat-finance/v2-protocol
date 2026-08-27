# Canonical Foundry Suite

`test/` is the only protocol test tree. It uses the same Solidity, EVM,
optimizer, via-IR, and metadata settings as the default production build.
Plain `forge test` requires no timestamp, seed, profile, or environment setup.

The suite replaced a frozen inheritance-heavy oracle after an explicit
property-by-property review. That migration evidence remains in Git history;
parity tooling is not ongoing test infrastructure.

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

| Path | Responsibility |
| --- | --- |
| `access/`, `providers/`, `root/`, `sanctions/` | Authority, credentials, registry, and sanctions behavior. |
| `factories/`, `market/`, `vault/` | Deployment matrices and production market/wrapper behavior. |
| `integration/`, `invariants/` | Cross-contract lifecycles, economic scenarios, and stateful properties. |
| `libraries/`, `types/`, `lens/`, `spherex/` | Focused unit and boundary tests. |
| `mocks/`, `shared/` | Capability-sized fixtures and test-only infrastructure; no test entrypoints. |

## Maintenance Rules

- Put `test*` and `invariant*` entrypoints only on concrete domain suites.
  Shared behavior belongs in internal scenario or assertion helpers, not
  inherited test functions.
- Use the smallest fixture that proves the behavior. Keep real factory and
  CREATE2 paths where deployment is the behavior under test.
- Exercise equivalent implementations with runtime matrices. Split properties
  only where behavior intentionally differs.
- Tests that warp inside one call must read time with
  `vm.getBlockTimestamp()`. Tests needing a non-default initial timestamp must
  establish it in their fixture.
- Every bug fix needs the smallest regression that fails without the fix.
  Prefer assertions over logs and explicit revert expectations over
  `testFail_*` naming.

## Coverage Boundary

`scripts/coverage.sh` temporarily applies `scripts/coverage-spherex.patch`, runs a
focused non-via-IR coverage build, restores the source on every exit path, and
verifies the source stayed clean. Set `FOUNDRY_TEST` to a narrow test directory;
whole-suite accurate coverage is not supported because production graphs that
include `HooksFactoryRevolving` exceed the non-via-IR compiler's stack limits.

The default via-IR build, canonical tests, invariants, and deployment-profile
tests are unaffected. Foundry may still print a non-fatal
`unresolved symbol locals` diagnostic for the SphereX modifier during normal
compilation.

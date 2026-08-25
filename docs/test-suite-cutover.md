# Canonical Foundry Test-Suite Cutover

Status: canonical Foundry suite as of 2026-08-23.

The ground-up suite under `test-next/` is now the default Foundry and deployment-profile test
tree. The former `test/` tree is unchanged and remains available through the explicit `legacy`
profile for one review cycle.

The redesign and cutover do not modify production `src/` Solidity or the frozen `test/` tree.

## Final shape

| Measure                            | Frozen legacy suite | Canonical suite |          Change |
| ---------------------------------- | ------------------: | --------------: | --------------: |
| Solidity test files                |                 117 |              80 |         -31.62% |
| Solidity test lines                |              39,445 |          27,360 |         -30.64% |
| Runnable suites                    |                  94 |              46 |         -51.06% |
| Test and invariant entries         |               1,797 |             674 |         -62.49% |
| Inherited entries                  |                 473 |               0 |           -100% |
| Test-side initcode                 |    12,517,142 bytes | 1,192,195 bytes |         -90.48% |
| Test-side runtime bytecode         |     6,774,062 bytes | 1,175,139 bytes |         -82.65% |
| Forced fixed-seed compile-to-green |           32m16.65s |        3m50.30s | -88.11% / 8.41x |
| Peak RSS for that run              |            33.5 GiB |        4.29 GiB | -87.20% / 7.81x |

Both forced runs used official solc 0.8.25, full via-IR, the canonical 44-run optimizer profile,
the same fixed timestamp and seed, 1,000 fuzz runs, and 2,000 invariant runs at depth 30. The
replacement passed all 674 entries; the frozen oracle passed all 1,797 entries. The deploy profile
also passed all 674 entries from a forced build in 3m49.45s with a 4.52 GiB peak. Warm fixed-seed
execution took 41.67s for the replacement and 37.83s for the frozen oracle; the replacement's eight
matrix invariants each completed 2,000 runs at depth 30 with zero handler reverts.

The lower entry count is not a claim that fewer behaviors matter. Family ledgers under
`test-next/parity/` document the semantic replacement, and
`legacy-property-dispositions.json` accounts for every one of the 1,438 legacy declarations and
all 1,797 concrete/inherited entries: 206 direct, 1,198 composed, 29 reassigned across production
contract boundaries, and five retired with explicit rationale. The manifest is backed by AST
snapshots and source-tree hashes, and its validator rejects missing owners, changed family counts,
unknown origins, source drift, or stale generated output.

The intent-level audit did find production compositions and deterministic sequences that the first
component pass had compressed too far. Those gaps are now native `test-next/` properties covering
the real six-cell factory matrix, complete lifecycles, periodic APR governance, minimum-deposit
ordering, rounding regressions, sanctions, production-sized economics, borrower accounts, exact
events, Lens V1 rejection, and wrapped scaled queueing. The completed catalogue and exit gate are
in `test-next/parity/integration-intents.md`.

## Maintenance model

- One concrete suite owns each behavior domain.
- Shared behavior is a scenario or runtime matrix, not an inherited `test*` function.
- Fixtures are capability-sized and use artifact-backed infrastructure where deployment is not
  the behavior under test.
- Tests establish any non-default initial timestamp in their own fixture. Plain `forge test` must
  run without environment setup or CLI overrides.
- Real factories and CREATE2 paths remain in tests that own deployment behavior.
- Every new property gets one clear owner and a parity note when it replaces existing coverage.
- The suite may grow with the protocol. The constraint is to avoid multiplicative compile-time
  growth from omnibus fixtures and inherited entrypoints, not to hold an arbitrary line or test
  count.

## Commands

```sh
# Ordinary canonical suite
forge test

# Repeatable audit lane
yarn test:fixed

# Exact legacy-property disposition check
yarn test:parity

# Exact deployment-profile lane used by the ceremony
FOUNDRY_PROFILE=deploy forge test

# Frozen pre-cutover oracle; audit-injected test/fizz harnesses are excluded
yarn test:legacy:fixed

# Focused accurate coverage; whole-suite Forge coverage is compiler-blocked
FOUNDRY_TEST=test-next/sanctions yarn coverage --match-contract SanctionsTest
```

`test:next` and `test:next:fixed` remain as transitional aliases. The `test-next` profile keeps an
isolated cache/output path for metrics, but it does not change compiler settings.

## Coverage boundary

`scripts/test-next-coverage.sh` safely applies and reverses the temporary SphereX analyzer patch.
Focused replacement families produce accurate non-IR Forge coverage and their results are recorded
in the parity ledgers. Whole-suite Forge coverage is not a release gate: Forge disables via-IR for
accurate source maps, then the production `HooksFactoryRevolving` graph fails stack allocation.
`--ir-minimum` fails separately during Yul stack allocation. Both failures occur before test
execution, and neither affects the canonical via-IR suite.

No coverage-only Solidity change is retained. A different coverage tool can replace this focused
lane later without changing the canonical test architecture.

## Known tooling note

Foundry still prints a non-fatal `unresolved symbol locals` diagnostic for the SphereX modifier at
`SphereXProtectedRegisteredBase.sol:153`. Canonical compilation, test execution, artifact metrics,
and deployment-profile execution all return success.

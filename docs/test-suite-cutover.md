# Canonical Foundry Test-Suite Cutover

Status: provisional on `refactor/test-suite-next`; semantic integration parity is under review.

The ground-up suite under `test-next/` is now the default Foundry and deployment-profile test
tree. The former `test/` tree is unchanged and remains available through the explicit `legacy`
profile for one review cycle.

The redesign and cutover do not modify production `src/` Solidity or the frozen `test/` tree.

## Final shape

| Measure                            | Frozen legacy suite | Canonical suite |          Change |
| ---------------------------------- | ------------------: | --------------: | --------------: |
| Solidity test files                |                 117 |              74 |         -36.75% |
| Solidity test lines                |              39,445 |          25,176 |         -36.17% |
| Runnable suites                    |                  94 |              43 |         -54.26% |
| Test and invariant entries         |               1,797 |             656 |         -63.49% |
| Inherited entries                  |                 473 |               0 |           -100% |
| Test-side initcode                 |    12,517,142 bytes | 1,069,410 bytes |         -91.46% |
| Test-side runtime bytecode         |     6,774,062 bytes | 1,055,573 bytes |         -84.42% |
| Forced fixed-seed compile-to-green |           32m16.65s |        3m33.39s | -88.98% / 9.08x |
| Peak RSS for that run              |            33.5 GiB |         4.0 GiB | -88.11% / 8.41x |

Both forced runs used official solc 0.8.25, full via-IR, the canonical 44-run optimizer profile,
the same fixed timestamp and seed, 1,000 fuzz runs, and 2,000 invariant runs at depth 30. The
replacement passed all 656 entries; the frozen oracle passed all 1,797 entries. The deploy profile
also passed the complete replacement suite in 3m34.50s with a 4.2 GiB peak.

The lower entry count is not a claim that fewer behaviors matter. Thirty-one family ledgers under
`test-next/parity/` record the initial mapping to direct replacements, stronger composed/runtime
properties, deliberate handoffs, or explicit retirements. A later intent-level audit found that
several cross-contract handoffs were too broad: the component behavior exists, but the production
composition or required deterministic sequence does not. The open integration requirements and
exit gate are tracked in `test-next/parity/integration-intents.md`.

## Maintenance model

- One concrete suite owns each behavior domain.
- Shared behavior is a scenario or runtime matrix, not an inherited `test*` function.
- Fixtures are capability-sized and use artifact-backed infrastructure where deployment is not
  the behavior under test.
- Real factories and CREATE2 paths remain in tests that own deployment behavior.
- Every new property gets one clear owner and a parity note when it replaces existing coverage.
- The suite may grow with the protocol. The constraint is to avoid multiplicative compile-time
  growth from omnibus fixtures and inherited entrypoints, not to hold an arbitrary line or test
  count.

## Commands

```sh
# Ordinary canonical suite
yarn test

# Repeatable audit lane
yarn test:fixed

# Exact deployment-profile lane used by the ceremony
FOUNDRY_PROFILE=deploy forge test

# Frozen pre-cutover oracle
yarn test:legacy:fixed
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
and deployment-profile execution all return success. Remaining instrumentation notes are retained
in `test-next/REVIEW_NOTES.md` for the review cycle.

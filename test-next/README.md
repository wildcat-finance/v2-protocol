# Candidate Canonical Foundry Suite

This tree is the default Foundry suite while semantic parity is reviewed. It uses the same compiler
settings as deployment builds.
The former suite remains untouched under `test/` as a frozen parity oracle; it does not participate
in ordinary or deploy-profile test discovery. The integration-intent gaps that must close before
the cutover is final are tracked in `parity/integration-intents.md`.

Run it with:

```sh
yarn test
```

The repeatable parity lane uses a fixed timestamp and fuzz seed:

```sh
yarn test:fixed
```

Focused accurate coverage uses the documented temporary SphereX analyzer workaround. The
coverage script refuses to touch an already-modified SphereX source file, applies
`docs/coverage-spherex.patch` only for the run, restores the source on exit, and verifies the
file is clean afterward. The patch is never part of the replacement suite. Forge's
accurate-coverage mode replaces the canonical via-IR build with a non-IR instrumented build.
Production graphs that import `HooksFactoryRevolving` exceed that coverage-only compiler; this
does not affect canonical compilation or test execution. Set `FOUNDRY_TEST` to keep discovery
narrow, for example:

```sh
FOUNDRY_TEST=test-next/sanctions yarn coverage --match-contract SanctionsTest
```

The default and deploy profiles discover this tree directly. The transitional `test-next`
profile remains available with isolated artifacts for comparison tooling; all three inherit the
same official solc version, via-IR setting, optimizer sequence, optimizer runs, EVM version, and
metadata settings.

## Maintenance rules

- Do not import the legacy `test/` fixture or helpers. Small dependencies should live here so the
  new suite's compile graph remains visible.
- Put `test*` and `invariant*` entrypoints only on concrete domain suites. Shared behavior belongs
  in internal scenario/assertion helpers, not inherited test functions.
- Use the smallest fixture that proves the behavior. A library test should not deploy the
  controller, factories, hooks, providers, markets, and wrapper stack.
- Exercise common implementation variants at runtime from one property. Keep separate properties
  only when behavior is intentionally different.
- Runtime matrices that warp inside one test call must read time with `vm.getBlockTimestamp()`.
  The EVM assumes `block.timestamp` is stable during a transaction, so via-IR may reuse that value
  across a Foundry cheatcode warp.
- Keep real factory/CREATE2 deployment paths when deployment is the behavior under test. Fixture
  infrastructure may use artifact-backed deployment after constructor and immutable semantics are
  verified.
- Map every migrated property in `parity/`; a lower test count is acceptable only when the new
  property is demonstrably equivalent or stronger.
- Let the suite grow when the protocol grows. Avoid compile-time copies; do not optimize for an
  arbitrary permanent test count.

The old suite remains available without being edited or moved. Run its matching fixed-seed oracle
with `yarn test:legacy:fixed`.

Completed family ledgers live in `parity/`:

- `access-controls.md`
- `libraries-types.md`
- `role-provider-factories.md`
- `token-role-providers.md`
- `managed-role-providers.md`
- `wildcat-arch-controller.md`
- `borrower-identity-registry.md`
- `mock-arch-controller-owner.md`
- `borrower-account-origination.md`
- `hooks-administrator-transfer.md`
- `sanctions.md`
- `reentrancy-guard.md`
- `spherex-config.md`
- `hooks-factory-templates.md`
- `hook-dispatch.md`
- `open-term-hooks.md`
- `fixed-term-hooks.md`
- `periodic-term-hooks.md`
- `market-constraint-hooks.md`
- `market-token.md`
- `market-base.md`
- `market-config.md`
- `market-lifecycle.md`
- `market-borrower-transfer.md`
- `market-withdrawals.md`
- `wildcat-4626-wrapper-factory.md`
- `wildcat-4626-wrapper.md`
- `wildcat-4626-wrapper-integration.md`
- `market-lens.md`
- `market-invariants.md`
- `production-matrix-scenarios.md`
- `production-economics.md`

# Replacement Foundry Suite

This tree is the canonical-settings replacement for `test/`. Both suites stay available until
semantic and coverage parity are demonstrated.

Run it with:

```sh
yarn test:next
```

The repeatable parity lane uses a fixed timestamp and fuzz seed:

```sh
yarn test:next:fixed
```

Accurate coverage uses the documented temporary SphereX analyzer workaround:

```sh
yarn coverage:next
```

The coverage script refuses to touch an already-modified SphereX source file, applies
`docs/coverage-spherex.patch` only for the run, restores the source on exit, and verifies the
file is clean afterward. The patch is never part of the replacement suite. Forge's
accurate-coverage mode replaces the canonical via-IR build with a non-IR instrumented build.
Production graphs that import `HooksFactoryRevolving` exceed that coverage-only compiler; this
does not affect canonical compilation or test execution. Focused families can set `FOUNDRY_TEST`
to keep discovery narrow, for example:

```sh
FOUNDRY_TEST=test-next/sanctions yarn coverage:next --match-contract SanctionsTest
```

The `test-next` Foundry profile changes only test discovery and artifact/cache paths. It inherits
the same official solc version, via-IR setting, optimizer sequence, optimizer runs, EVM version,
and metadata settings as the deployment build.

## Rules while rebuilding

- Do not import the legacy `test/` fixture or helpers. Small dependencies should live here so the
  new suite's compile graph remains visible.
- Put `test*` and `invariant*` entrypoints only on concrete domain suites. Shared behavior belongs
  in internal scenario/assertion helpers, not inherited test functions.
- Use the smallest fixture that proves the behavior. A library test should not deploy the
  controller, factories, hooks, providers, markets, and wrapper stack.
- Exercise common implementation variants at runtime from one property. Keep separate properties
  only when behavior is intentionally different.
- Keep real factory/CREATE2 deployment paths when deployment is the behavior under test. Fixture
  infrastructure may use artifact-backed deployment after constructor and immutable semantics are
  verified.
- Map every migrated property in `parity/`; a lower test count is acceptable only when the new
  property is demonstrably equivalent or stronger.

The old suite remains the behavioral oracle during the migration. It is not being edited or moved
as part of this work. Its matching fixed-seed command is `yarn test:legacy:fixed`.

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

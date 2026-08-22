# Parity Ledger

`legacy-suite.json` is the machine-readable baseline for the tracked legacy suite. It is generated
from Foundry's canonical cache and artifacts rather than source-name heuristics:

```sh
forge build --ast
node scripts/test-suite-metrics.js --compact > test-next/parity/legacy-suite.json
```

The AST flag is required to recover the declaring contract behind inherited test selectors. For
the replacement tree, use the same commands with `FOUNDRY_PROFILE=test-next`,
`--artifacts out-test-next`, `--cache cache-test-next/solidity-files-cache.json`, and
`--prefix test-next/`.

The baseline records each declared property, its source declaration, every concrete suite that
inherits or implements it, compiler settings, category totals, and emitted test bytecode. The
current snapshot contains 94 runnable suites, 1,797 test/invariant entries, 1,438 distinct declared
properties, and 12,517,142 bytes of test-side creation bytecode.

Replacement ledgers should classify each legacy property as directly replaced, covered by a
stronger runtime property, deliberately retained in the reference suite, or retired with a written
rationale.

## Coverage lane

The legacy monolith still cannot produce current coverage: after the temporary SphereX workaround,
Forge's non-IR coverage build reaches unrelated stack-too-deep failures and minimum-IR reaches a
Yul allocation failure. This is a limitation of the coverage-only compiler profile, not the
canonical via-IR test lane. Accurate non-IR coverage works for replacement slices whose import
graphs avoid those contracts. Completed integration slices that import
`HooksFactoryRevolving` carry that tooling exception in their family ledgers.

Run it with:

```sh
yarn coverage:next
```

`scripts/test-next-coverage.sh` applies `docs/coverage-spherex.patch` temporarily and reverses it
even when Forge fails. It refuses to start if the SphereX source is already dirty and verifies the
source is restored before returning. No coverage-only Solidity change is retained.

Use `FOUNDRY_TEST` for a focused family when the complete replacement discovery graph includes a
compiler-blocked integration slice. For example:

```sh
FOUNDRY_TEST=test-next/sanctions yarn coverage:next --match-contract SanctionsTest
```

At the first representative checkpoint, 236 tests cover the currently imported production slice
at 98.16% lines, 97.69% statements, 94.59% branches, and 99.49% functions. The remaining
`IHooks.onCreateMarket` path belongs to the hook-specific migration rather than this shared slice.

The second checkpoint adds the complete role-provider factory family. All six factory contracts
have 100% line, statement, branch, and function coverage. Aggregate coverage of every newly
imported source is temporarily lower because the factory matrix necessarily imports provider and
`OpenTermHooks` implementations whose full behavior belongs to later slices; those partial files
are not being presented as complete.

The token role-provider checkpoint replaces 84 provider and deposit-hook entries with 30 focused
properties. Four pull providers have 100% coverage; ERC5192 and ERC5484 have 100% branch/function
coverage and only four constant-return lines missed by Forge's line instrumentation. The three
Wildcat debt-token/wrapper scenarios remain explicitly mapped to the market/vault slice.

The managed-provider checkpoint replaces 44 AccessList/Merkle entries with 24 focused properties.
ManagedRoleProvider and AccessListRoleProvider have 100% line, statement, branch, and function
coverage; MerkleRoleProvider has 100% branch/function coverage with one constant-return line missed
by Forge instrumentation. See `managed-role-providers.md` for the composition boundary around
factory, FixedTerm, and generic market dispatch.

The shared market-token and market-base checkpoint replaces 74 standard/inherited FixedTerm
entries with 14 properties on one runtime-matrix suite. Focused accurate coverage keeps
`WildcatMarketToken` at 100%; `WildcatMarketBase` is intentionally partial until its configuration,
lifecycle, borrower-transfer, and withdrawal slices join the same artifact. See `market-token.md`
and `market-base.md`.

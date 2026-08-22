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
its non-IR build reaches unrelated stack-too-deep failures and minimum-IR reaches a Yul allocation
failure. The replacement suite's narrow import graph avoids both failures, so accurate non-IR
coverage now works for each completed slice.

Run it with:

```sh
yarn coverage:next
```

`scripts/test-next-coverage.sh` applies `docs/coverage-spherex.patch` temporarily and reverses it
even when Forge fails. It refuses to start if the SphereX source is already dirty and verifies the
source is restored before returning. No coverage-only Solidity change is retained.

At the first representative checkpoint, 236 tests cover the currently imported production slice
at 98.16% lines, 97.69% statements, 94.59% branches, and 99.49% functions. The remaining
`IHooks.onCreateMarket` path belongs to the hook-specific migration rather than this shared slice.

The second checkpoint adds the complete role-provider factory family. All six factory contracts
have 100% line, statement, branch, and function coverage. Aggregate coverage of every newly
imported source is temporarily lower because the factory matrix necessarily imports provider and
`OpenTermHooks` implementations whose full behavior belongs to later slices; those partial files
are not being presented as complete.

The token role-provider core checkpoint replaces 42 provider-level legacy entries with 21 focused
properties. Four pull providers have 100% coverage; ERC5192 and ERC5484 have 100% branch/function
coverage and only four constant-return lines missed by Forge's line instrumentation. Market-hook
behavior and the Wildcat debt-token/wrapper scenarios remain explicitly mapped to later slices.

# Parity Ledger

The family ledgers are an initial mapping, not a completed semantic-parity claim. The later
integration-intent review found cross-contract guarantees that were split across component tests
without retaining their production composition or deterministic sequence. Those open requirements
and the final exit gate live in `integration-intents.md`.

`legacy-suite.json` is the machine-readable baseline for the tracked legacy suite. It is generated
from Foundry's canonical cache and artifacts rather than source-name heuristics:

```sh
FOUNDRY_PROFILE=legacy forge build --ast
node scripts/test-suite-metrics.js \
  --artifacts out-legacy \
  --cache cache-legacy/solidity-files-cache.json \
  --prefix test/ \
  --compact > test-next/parity/legacy-suite.json
```

The AST flag is required to recover the declaring contract behind inherited test selectors. For
the replacement tree, use the default profile with `--artifacts out`,
`--cache cache/solidity-files-cache.json`, and `--prefix test-next/`. The isolated transitional
profile remains reproducible with `FOUNDRY_PROFILE=test-next`, `out-test-next`, and
`cache-test-next/solidity-files-cache.json`.

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

Run a focused family with:

```sh
FOUNDRY_TEST=test-next/sanctions yarn coverage --match-contract SanctionsTest
```

`scripts/test-next-coverage.sh` applies `docs/coverage-spherex.patch` temporarily and reverses it
even when Forge fails. It refuses to start if the SphereX source is already dirty and verifies the
source is restored before returning. No coverage-only Solidity change is retained.

The complete replacement discovery graph includes a compiler-blocked integration slice, so an
unscoped `yarn coverage` is expected to stop at that production compiler boundary.

At the first representative checkpoint, 236 tests cover the currently imported production slice
at 98.16% lines, 97.69% statements, 94.59% branches, and 99.49% functions. The remaining
`IHooks.onCreateMarket` path belongs to the hook-specific migration rather than this shared slice.

The second checkpoint adds the complete role-provider factory family. All six factory contracts
have 100% line, statement, branch, and function coverage. Aggregate coverage of every newly
imported source is temporarily lower because the factory matrix necessarily imports provider and
`OpenTermHooks` implementations whose full behavior belongs to later slices; those partial files
are not being presented as complete.

The token role-provider checkpoint replaces all 87 provider and deposit-hook entries with 33
properties. Four pull providers have 100% coverage; ERC5192 and ERC5484 have 100%
branch/function coverage and only four constant-return lines missed by Forge's line
instrumentation. Three production-composition properties close the Wildcat debt-token and wrapper
interest boundary through real source and target markets.

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

The market-configuration checkpoint replaces all 88 standard/inherited FixedTerm configuration
entries with 22 properties split at the production contract boundary: seven constraint-hook
properties and 15 market properties. Focused accurate coverage reports 100% for
`WildcatMarketConfig`; the remaining partial market files belong to lifecycle, borrower-transfer,
and withdrawal slices. See `market-config.md`.

The market-lifecycle checkpoint maps all 122 standard/inherited `WildcatMarketTest` entries.
Fourteen new runtime-matrix properties own state updates, deposits, fees, borrowing, repayment,
closure, batch-key safety, and rescue behavior; completed token, dispatch, and access-hook families
own the duplicated cross-boundary properties. The withdrawal checkpoint now owns the final two
randomized closed-market drain entries. See `market-lifecycle.md` and `market-withdrawals.md`.

The market borrower-transfer checkpoint maps the core identity, authority, sanctions, accounting,
and withdrawal-escrow entries into 12 composed properties. All executable lines and branches in
the production borrower-transfer region are covered. The wrapper integration checkpoint now owns
the final six cross-boundary entries. See `market-borrower-transfer.md`, `market-withdrawals.md`,
and `wildcat-4626-wrapper-integration.md`.

The market-withdrawal checkpoint maps all 124 standard/inherited withdrawal entries, the two
lifecycle closed-market drain entries, and the two borrower-principal escrow entries. Eighteen
runtime-matrix market properties plus one production-Sentinel property cover the family, while
completed access-hook suites own repeated credential gates. `WildcatMarketWithdrawals` has 100%
line, statement, branch, and function coverage. See `market-withdrawals.md`.

The revolving-market checkpoint maps all 22 direct market entries and four deterministic
differential entries into 12 properties on the shared market artifact. Drawn-principal accounting,
commitment/utilization interest, protocol and delinquency fees, dust boundaries, borrower transfer,
closure, and standard-market anchors give `WildcatMarketRevolving` 100% line, statement, branch,
and function coverage. The randomized hook × market matrix is complete in the invariant
checkpoint. See `market-revolving.md` and `market-invariants.md`.

The wrapper-factory checkpoint replaces all 16 generation-routing, deployment, registration, and
transfer-policy entries with nine composed properties. The production factory reaches 100% line,
statement, branch, and function coverage. See `wildcat-4626-wrapper-factory.md`.

The Lens checkpoint replaces 74 core and multi-factory entries with 19 properties split across
the deployed facade, core/live, and aggregator boundaries. Focused accurate coverage gives
`MarketLens`, `MarketLensCore`, `MarketLensLive`, and `MarketLensAggregator` 100% line, statement,
branch, and function coverage. See `market-lens.md`.

The invariant checkpoint replaces 26 meaningful matrix and CAF12 entries with eight properties in
one six-cell runtime matrix. The two withdrawal-batch identity invariants are owned by stronger
deterministic market properties, and three vacuous generic MockERC20 invariants are retired. Every
canonical property passes 2,000 runs at depth 30, the focused accurate-coverage lane is green, and
the invariant tail falls from 1,761,168 to 54,426 bytes of initcode. See `market-invariants.md`.

The core wrapper checkpoint maps all 160 non-factory vault entries into 19 composed properties.
Conversions, execution, allowances, caps, sanctions, defensive reads, sweeps, and quarantine use the
production wrapper with one floor-rounding market mock. Ten production-composition properties then
close the ten legacy integration entries, six borrower-transfer wrapper handoffs, and three
token-provider cross-feature entries, including the live escrow-release branch, all built-in
hooks, borrower accounts, a revolving market, and production debt-token/wrapper access checks.
See `wildcat-4626-wrapper.md` and `wildcat-4626-wrapper-integration.md`.

# Test replacement review notes

Non-blocking items collected while the replacement suite is being built. Resolve or remove this
file before the final cutover.

- Canonical `forge test --ast` currently prints Foundry's non-fatal `unresolved symbol locals`
  diagnostic for the SphereX modifier at `SphereXProtectedRegisteredBase.sol:153`. Compilation,
  test execution, and the AST metrics all complete with exit status 0.
- The repository-wide formatting check currently stops on existing Prettier drift outside
  `test-next/`. New replacement files are checked directly until that baseline is cleaned up.
- The ERC20-debt-token and ERC4626-wrapper interest scenarios cross provider, market, and wrapper
  behavior. They remain in the legacy oracle until the market/vault integration slice rather than
  forcing the full protocol fixture into the focused provider suite.
- The token-provider matrix now reaches production `OpenTermHooks.onDeposit` from a registered
  lightweight market identity. One real `WildcatMarket.depositUpTo -> onDeposit` dispatch still
  belongs in the later market/access-hook slice; repeating that generic dispatch for all six
  providers would recreate the fixture duplication this rewrite is removing.
- Forge line instrumentation leaves ERC5192/ERC5484's four constant-return source lines uncovered
  while reporting their `isPullProvider` and `getCredential` functions as executed. The tests
  explicitly assert both return values; branch and function coverage for both contracts is 100%.

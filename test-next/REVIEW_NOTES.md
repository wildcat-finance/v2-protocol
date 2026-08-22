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
- Managed-provider integration now reaches the same production OpenTerm path. The legacy
  AccessList suite also repeated shared credential behavior through a mock FixedTerm hook; one
  production FixedTerm dispatch remains assigned to the FixedTerm hook slice rather than being
  inferred from the OpenTerm result.
- Forge line instrumentation leaves ERC5192/ERC5484's four constant-return source lines uncovered
  while reporting their `isPullProvider` and `getCredential` functions as executed. The tests
  explicitly assert both return values; branch and function coverage for both contracts is 100%.
- Forge reports the same instrumentation behavior for one constant-return line in
  `MerkleRoleProvider`: branch and function coverage are 100%, and both zero-return paths are
  explicitly asserted.
- The disabled CAF-13 invalid-pagination and CAF-16 registered-target-validation cases are not
  carried into the ArchController replacement suite. They describe remediations that cannot be
  applied to the deployed singleton; the new suite preserves its current registry semantics.
- ArchController SphereX propagation uses lightweight registered targets. Their mocks cover the
  controller-owned dispatch and allowlisting behavior; each real target's own
  `changeSphereXEngine` implementation remains assigned to its factory, hooks, or market slice.
- The standalone SphereX configuration slice preserves the registered base's controller-only
  update and engine-disabled guard cases. Active engine pre/post validation and storage snapshots
  remain assigned to the protected factory, hook, market, and wrapper slices.
- Forge does not credit the `MockArchControllerOwner.onlyAuthorized` modifier's revert
  statement/branch. Multiple replacement properties still exercise it and assert the exact
  `NotAuthorized` selector through three separate external functions.
- Forge does not credit `ReentrancyGuard.nonReentrant`'s `_clearReentrancyGuard()` source line.
  It reports `_clearReentrancyGuard` itself as executed, and repeated guarded calls in one test
  transaction prove the transient slot is cleared after each successful call.
- Forge's accurate-coverage profile cannot compile the borrower-account origination,
  hooks-administrator transfer, or direct factory graphs after the SphereX patch:
  `HooksFactoryRevolving.sol:882` is stack-too-deep without via-IR, and `--ir-minimum` fails Yul
  stack allocation. This does not block the canonical via-IR suite, which is green. Exact factory
  source coverage remains unavailable through Forge's current coverage compiler, and no
  coverage-only source patch is retained.
- Runtime matrices that use `vm.warp` should read mutable cheatcode time through
  `vm.getBlockTimestamp()`, not repeatedly through the `block.timestamp` opcode. Via-IR may
  rematerialize or hoist that opcode because timestamp cannot change during a real transaction;
  Foundry's warp cheatcode deliberately breaks that EVM invariant inside the test call.
- Focused market coverage leaves two `WildcatMarket` lines. The internal `_repay` closed-state
  guard is structurally preceded by `closeMarket`'s public closed-state check. Reaching
  `CloseMarketWithUnpaidWithdrawals` requires an adversarial asset that reports successful
  `transferFrom` without moving funds; keep that case for the adversarial/invariant pass rather
  than changing the normal ERC-20 fixture.
- Borrower-transfer core behavior and both market-withdrawal escrow cases are complete. Its six
  wrapper readiness, wrapper escrow, wrapper namespace, and sweep-authority cases remain assigned
  to the wrapper slice; the borrower-transfer ledger names them so they do not disappear.

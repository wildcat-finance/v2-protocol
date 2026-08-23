# Test replacement review notes

Non-blocking instrumentation and review notes retained for the first post-cutover review cycle.
None of these items blocks the canonical or deployment-profile suite.

- Canonical `forge test --ast` currently prints Foundry's non-fatal `unresolved symbol locals`
  diagnostic for the SphereX modifier at `SphereXProtectedRegisteredBase.sol:153`. Compilation,
  test execution, and the AST metrics all complete with exit status 0.
- The legacy oracle commands explicitly exclude `test/fizz/**`. Audit-generated fuzz harnesses can
  remain in the worktree without changing the frozen 94-suite / 1,797-entry comparison.
- The repository-wide formatting check currently stops on existing Prettier drift outside
  `test-next/`. New replacement files are checked directly until that baseline is cleaned up.
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
- Focused market coverage leaves two `WildcatMarket` lines. The internal `_repay` closed-state
  guard is structurally preceded by `closeMarket`'s public closed-state check. Reaching
  `CloseMarketWithUnpaidWithdrawals` requires an adversarial asset that reports successful
  `transferFrom` without moving funds. These remain explicit defensive coverage exceptions rather
  than changing the canonical market fixture away from supported ERC-20 behavior.
- Core wrapper coverage leaves two shadowed Solady configuration helpers and three defensive
  arithmetic guards unreachable under the market's required `scaleFactor >= RAY`. The parity ledger
  records the identities. Production wrapper integration now covers the live sanctions-escrow
  release branch, all built-in hooks, borrower-account namespace transitions, and the revolving
  market path.
- Accurate Lens coverage closes all four shipped Lens contracts with one `FOUNDRY_TEST` root at a
  time. Directory-wide discovery imports the existing factory graph that Forge's non-IR coverage
  compiler cannot lower; canonical via-IR compilation is unaffected.

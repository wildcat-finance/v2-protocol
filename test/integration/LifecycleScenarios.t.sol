// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';

/// @dev Full-lifecycle integration scenarios over the hooks x market matrix.
///
///      The two production-proven cells (open/standard, fixed/standard) act as
///      controls that validate the harness itself; the remaining cells
///      (periodic/standard and the revolving column) are the configurations
///      with no production data.
///
///      Each scenario runs: deposits -> borrow -> interest accrual (checked
///      against a closed-form oracle) -> partial repay -> in-term withdrawal
///      -> close -> full exit, asserting at the end that every lender leaves
///      with at least their principal and the market is fully drained.
contract LifecycleScenariosTest is MarketConfigMatrix {
  using MathUtils for uint256;

  uint256 internal constant ALICE_DEPOSIT = 100_000e18;
  uint256 internal constant BOB_DEPOSIT = 50_000e18;

  // ========================================================================== //
  //                            Happy quarter matrix                            //
  // ========================================================================== //

  function test_happyQuarter_openTerm_standard() external {
    _runHappyQuarter(defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard));
  }

  function test_happyQuarter_fixedTerm_standard() external {
    _runHappyQuarter(defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Standard));
  }

  function test_happyQuarter_periodicTerm_standard() external {
    _runHappyQuarter(defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard));
  }

  function test_happyQuarter_openTerm_revolving() external {
    _runHappyQuarter(defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving));
  }

  function test_happyQuarter_fixedTerm_revolving() external {
    _runHappyQuarter(defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Revolving));
  }

  function test_happyQuarter_periodicTerm_revolving() external {
    _runHappyQuarter(defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Revolving));
  }

  function _runHappyQuarter(Cell memory cell) internal {
    DeployedCell memory d = deployCell(cell);
    uint256 aliceBalanceBefore = asset.balanceOf(alice);
    uint256 bobBalanceBefore = asset.balanceOf(bob);

    // --- Phase 1: deposits ---
    _depositAs(d, alice, ALICE_DEPOSIT);
    _depositAs(d, bob, BOB_DEPOSIT);
    assertEq(d.market.balanceOf(alice), ALICE_DEPOSIT, 'alice market balance');
    assertEq(d.market.balanceOf(bob), BOB_DEPOSIT, 'bob market balance');
    assertEq(d.market.totalSupply(), ALICE_DEPOSIT + BOB_DEPOSIT, 'total supply');

    // --- Phase 2: borrower draws half of what is borrowable ---
    uint256 borrowable = d.market.borrowableAssets();
    assertGt(borrowable, 0, 'nothing borrowable');
    uint256 draw = borrowable / 2;
    uint256 borrowerBalanceBefore = asset.balanceOf(borrower);
    _borrowAs(d, draw);
    assertEq(asset.balanceOf(borrower) - borrowerBalanceBefore, draw, 'borrow transfer');

    // --- Phase 3: interest accrues; scale factor must match the oracle ---
    _accrueAndCheck(d, 10 days);
    _accrueAndCheck(d, 11 days);

    // --- Phase 4: partial repay changes the revolving rate basis ---
    _repayAs(d, draw / 2);
    _accrueAndCheck(d, 9 days);

    // --- Phase 5: an in-term withdrawal through whatever gate the cell has ---
    // Accrue to the gate-open time under the oracle rather than raw-warping,
    // so fixed-term and periodic cells keep accrual coverage up to the gate.
    uint256 untilOpen = _timeUntilWithdrawalsOpen(d);
    if (untilOpen > 0) _accrueAndCheck(d, untilOpen);
    // Restore full liquidity so the batch can be paid on expiry.
    _repayAs(d, draw - draw / 2);
    uint256 withdrawAmount = d.market.balanceOf(alice) / 2;
    uint32 expiry = _queueWithdrawalAs(d, alice, withdrawAmount);
    fastForward(d.cell.withdrawalBatchDuration + 1);
    d.market.updateState();
    uint256 received = _executeWithdrawalAs(d, alice, expiry);
    assertGe(received + DUST, withdrawAmount, 'withdrawal underpaid');

    // --- Phase 6: close the market and let everyone exit ---
    _accrueQuietly(d, 5 days);
    _closeMarketAs(d);
    assertTrue(d.market.isClosed(), 'market not closed');

    _exitAllLenders(d);

    // --- Final accounting ---
    assertEq(d.market.scaledTotalSupply(), 0, 'scaled supply not drained');
    uint256 aliceProfit = asset.balanceOf(alice) - aliceBalanceBefore;
    uint256 bobProfit = asset.balanceOf(bob) - bobBalanceBefore;
    assertGt(aliceProfit, 0, 'alice earned no interest');
    assertGt(bobProfit, 0, 'bob earned no interest');
    // Bob deposited half as much for the same duration: profits should be
    // proportional to principal (modulo alice's mid-term withdrawal, which can
    // only reduce her share).
    assertLe(
      aliceProfit,
      ((bobProfit * ALICE_DEPOSIT) / BOB_DEPOSIT) + DUST,
      'profit proportionality'
    );
    assertLe(asset.balanceOf(address(d.market)), DUST, 'assets stranded in market');
  }

  /// @dev Accrue without an oracle check, for phases where a withdrawal batch
  ///      may expire mid-interval (the oracle only models single-segment
  ///      accrual).
  function _accrueQuietly(DeployedCell memory d, uint256 duration) internal {
    fastForward(duration);
    d.market.updateState();
  }

  /// @dev Queue full withdrawals for both lenders on the closed market, roll
  ///      past the batch, and execute. On a closed market the batch duration
  ///      is zero and term/window restrictions no longer apply.
  function _exitAllLenders(DeployedCell memory d) internal {
    address[2] memory lenders = [alice, bob];
    uint32[2] memory expiries;
    for (uint256 i; i < lenders.length; i++) {
      if (d.market.balanceOf(lenders[i]) > 0) {
        expiries[i] = _queueFullWithdrawalAs(d, lenders[i]);
      }
    }
    fastForward(1);
    d.market.updateState();
    for (uint256 i; i < lenders.length; i++) {
      if (expiries[i] != 0) {
        _executeWithdrawalAs(d, lenders[i], expiries[i]);
      }
    }
  }

  // ========================================================================== //
  //                      Term gates actually gate (matrix)                     //
  // ========================================================================== //

  function test_withdrawalGates_fixedTerm_standard() external {
    _runFixedTermGate(defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Standard));
  }

  function test_withdrawalGates_fixedTerm_revolving() external {
    _runFixedTermGate(defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Revolving));
  }

  function test_withdrawalGates_periodicTerm_standard() external {
    _runPeriodicGate(defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard));
  }

  function test_withdrawalGates_periodicTerm_revolving() external {
    _runPeriodicGate(defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Revolving));
  }

  function _runFixedTermGate(Cell memory cell) internal {
    DeployedCell memory d = deployCell(cell);
    _depositAs(d, alice, ALICE_DEPOSIT);

    // Before the term ends: queueing must revert.
    startPrank(alice);
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    d.market.queueFullWithdrawal();
    stopPrank();

    // One second before the boundary, still gated.
    vm.warp(d.deployedAt + cell.fixedTermDuration - 1);
    startPrank(alice);
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    d.market.queueFullWithdrawal();
    stopPrank();

    // At the boundary the gate opens.
    vm.warp(d.deployedAt + cell.fixedTermDuration);
    uint32 expiry = _queueFullWithdrawalAs(d, alice);
    assertGt(expiry, 0, 'queue after term should succeed');
  }

  function _runPeriodicGate(Cell memory cell) internal {
    DeployedCell memory d = deployCell(cell);
    _depositAs(d, alice, ALICE_DEPOSIT);
    PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);

    // Before the first window: gated.
    assertFalse(pth.isWithdrawalWindowOpen(address(d.market)), 'window unexpectedly open');
    startPrank(alice);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    d.market.queueFullWithdrawal();
    stopPrank();

    // Inside the window: allowed.
    uint256 windowStart = d.deployedAt + cell.firstWindowDelay;
    vm.warp(windowStart);
    assertTrue(pth.isWithdrawalWindowOpen(address(d.market)), 'window should be open');
    uint32 expiry = _queueWithdrawalAs(d, alice, ALICE_DEPOSIT / 4);
    assertGt(expiry, 0, 'queue inside window should succeed');

    // Just past the window: gated again.
    vm.warp(windowStart + cell.withdrawalWindowDuration);
    startPrank(alice);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    d.market.queueWithdrawal(1e18);
    stopPrank();

    // Next period's window: open again.
    vm.warp(windowStart + cell.periodDuration);
    uint32 expiry2 = _queueWithdrawalAs(d, alice, 1e18);
    assertGt(expiry2, 0, 'queue in next window should succeed');

    // A closed market ignores the window entirely.
    vm.warp(windowStart + cell.periodDuration + cell.withdrawalWindowDuration + 1);
    _repayAllDebts(d);
    _closeMarketAs(d);
    uint32 expiry3 = _queueFullWithdrawalAs(d, alice);
    assertGt(expiry3, 0, 'queue on closed market should succeed');
  }

  function _repayAllDebts(DeployedCell memory d) internal {
    uint256 assets = asset.balanceOf(address(d.market));
    uint256 debts = d.market.totalDebts();
    if (debts > assets) {
      _repayAs(d, debts - assets);
    }
  }
}

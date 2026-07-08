// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';

/// @dev Regression guards for the pre-audit interaction-review findings on
///      the floor-rounding change (v2.5): exact-debt close settlement, closed
///      market batch stranding, and exact-minimum deposits. These originally
///      reproduced the regressions; they now pin the fixes
///      (`maxScaledSettleableAmount` and the scaled-space minimum check).
contract RoundingRegressionReproTest is MarketConfigMatrix {
  using MathUtils for uint256;

  /// Finding 2 (fixed): depositing exactly `minimumDeposit` must succeed at
  /// any scale factor. The hooks compare in scaled units, so the acceptance
  /// boundary is the smallest tender whose floor-scaled amount matches the
  /// floor-scaled minimum: T = ceil(floor(min * RAY / sf) * sf / RAY).
  /// Tenders >= T pass (a sub-one-scaled-token band below the minimum is
  /// intentionally accepted); T - 1 is the largest rejected tender.
  function test_repro_exactMinimumDeposit_openTerm() external {
    _runExactMinimumDeposit(MatrixHooksKind.OpenTerm);
  }

  function test_repro_exactMinimumDeposit_fixedTerm() external {
    _runExactMinimumDeposit(MatrixHooksKind.FixedTerm);
  }

  function test_repro_exactMinimumDeposit_periodicTerm() external {
    _runExactMinimumDeposit(MatrixHooksKind.PeriodicTerm);
  }

  function _runExactMinimumDeposit(MatrixHooksKind hooksKind) internal {
    Cell memory cell = defaultCell(hooksKind, MatrixMarketKind.Standard);
    cell.minimumDeposit = 100_000e18;
    DeployedCell memory d = deployCell(cell);

    // Seed supply and borrow so interest accrues and the scale factor leaves
    // RAY; at sf == RAY the old and new checks are indistinguishable.
    _depositAs(d, bob, 500_000e18);
    _borrowAs(d, 300_000e18);
    fastForward(120 days);
    d.market.updateState();
    uint256 sf = d.market.scaleFactor();
    assertGt(sf, 1e27, 'scale factor did not move');

    // Exactly the minimum must be accepted.
    startPrank(alice);
    d.market.depositUpTo(100_000e18);
    stopPrank();
    assertGt(d.market.balanceOf(alice), 0, 'exact-minimum deposit rejected');

    // Pin the exact boundary: the smallest accepted tender T and the largest
    // rejected tender T - 1.
    uint256 minScaled = (uint256(100_000e18) * 1e27) / sf;
    uint256 boundary = (minScaled * sf + 1e27 - 1) / 1e27; // ceil
    startPrank(bob);
    d.market.depositUpTo(boundary);
    stopPrank();
    assertGt(d.market.balanceOf(bob), 0, 'boundary tender rejected');

    startPrank(bob);
    vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
    d.market.depositUpTo(boundary - 1);
    stopPrank();
  }

  /// Finding 1 (fixed): with all supply queued into a pending batch, close
  /// must settle the batch fully at any scale factor.
  function test_repro_closeWithFullyQueuedBatch() external {
    Cell memory cell = defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard);
    cell.reserveRatioBips = 0; // let everything be withdrawable
    DeployedCell memory d = deployCell(cell);

    // Deposit an amount chosen so that, after some accrual, S*sf/RAY has a
    // fractional part in (0, 0.5) - the stranding window.
    _depositAs(d, alice, 123_457e18);
    _borrowAs(d, 100_000e18);
    fastForward(37 days);
    d.market.updateState();

    // Repay everything so the market is fully funded, then queue the full supply.
    uint256 debts = d.market.totalDebts();
    uint256 held = asset.balanceOf(address(d.market));
    if (debts > held) _repayAs(d, debts - held);

    // Vacuity guard: the fixture constants must land in the stranding window
    // (frac in (0, HALF_RAY)), where the pre-fix floor capacity came up one
    // scaled token short. Outside it the old code also passed.
    uint256 frac = (d.market.scaledTotalSupply() * d.market.scaleFactor()) % 1e27;
    assertGt(frac, 0, 'fixture left the stranding window (frac == 0)');
    assertLt(frac, 0.5e27, 'fixture left the stranding window (frac >= HALF_RAY)');

    startPrank(alice);
    d.market.queueFullWithdrawal();
    stopPrank();

    // Close must fully settle the queued batch regardless of frac.
    startPrank(borrower);
    d.market.closeMarket();
    stopPrank();
    MarketState memory st = d.market.previousState();
    assertEq(st.scaledPendingWithdrawals, 0, 'pending withdrawals remain after close');
    assertEq(d.market.getUnpaidBatchExpiries().length, 0, 'unpaid batches after close');
  }

  /// Finding 1 variant (fixed): a full withdrawal queued on an already-closed,
  /// fully-funded market must be fully paid, never stranded.
  function test_repro_fullWithdrawalOnClosedMarket() external {
    Cell memory cell = defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard);
    cell.reserveRatioBips = 0;
    DeployedCell memory d = deployCell(cell);

    _depositAs(d, alice, 123_457e18);
    _borrowAs(d, 100_000e18);
    fastForward(37 days);
    d.market.updateState();
    uint256 debts = d.market.totalDebts();
    uint256 held = asset.balanceOf(address(d.market));
    if (debts > held) _repayAs(d, debts - held);

    startPrank(borrower);
    d.market.closeMarket();
    stopPrank();

    // Vacuity guard: post-close (scale factor frozen), the full-supply batch
    // must land in the stranding window for this repro to prove anything.
    uint256 frac = (d.market.scaledTotalSupply() * d.market.scaleFactor()) % 1e27;
    assertGt(frac, 0, 'fixture left the stranding window (frac == 0)');
    assertLt(frac, 0.5e27, 'fixture left the stranding window (frac >= HALF_RAY)');

    startPrank(alice);
    uint32 expiry = d.market.queueFullWithdrawal();
    stopPrank();

    fastForward(2);
    d.market.updateState();

    // On a closed, fully-funded market every batch must be finishable, and
    // the lender must actually be able to collect the payout.
    assertEq(d.market.getUnpaidBatchExpiries().length, 0, 'batch stranded on closed market');
    uint256 balanceBefore = asset.balanceOf(alice);
    uint256 withdrawn = d.market.executeWithdrawal(alice, expiry);
    assertGt(withdrawn, 0, 'nothing withdrawn');
    assertEq(asset.balanceOf(alice) - balanceBefore, withdrawn, 'payout mismatch');
    assertEq(d.market.balanceOf(alice), 0, 'lender still holds market tokens');
  }
}

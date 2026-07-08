// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';

/// @dev Differential tests anchoring WildcatMarketRevolving's interest model
///      to the production-proven standard market.
///
///      The revolving rate is `commitmentFee + APR * min(drawn, supply) / supply`.
///      Three closed-form anchors follow:
///
///      1. With zero commitment fee and the full deposit drawn, the drawn
///         amount equals the pre-accrual supply, so the first accrual segment
///         must match a standard market with identical parameters EXACTLY,
///         for any segment length.
///      2. After that first segment the supply has grown past the fixed drawn
///         amount, so the revolving market must accrue STRICTLY LESS than the
///         standard market — by design, lenders earn full APR only on drawn
///         funds.
///      3. With nothing drawn, the market must accrue exactly the commitment
///         fee and nothing else; with debts fully repaid, the drawn amount
///         must return to zero and the market reverts to fee-only accrual.
contract RevolvingDifferentialTest is MarketConfigMatrix {
  using MathUtils for uint256;

  uint256 internal constant DEPOSIT = 100_000e18;

  /// @dev Zero-fee, zero-reserve cell so the full deposit is borrowable and
  ///      the only accrual source is the APR itself.
  function _differentialCell(MatrixMarketKind marketKind) internal pure returns (Cell memory cell) {
    cell = defaultCell(MatrixHooksKind.OpenTerm, marketKind);
    cell.reserveRatioBips = 0;
    cell.delinquencyFeeBips = 0;
    cell.commitmentFeeBips = 0;
  }

  function test_fullyDrawn_zeroFee_firstSegmentMatchesStandard() external {
    DeployedCell memory std = deployCell(_differentialCell(MatrixMarketKind.Standard));
    DeployedCell memory rcf = deployCell(_differentialCell(MatrixMarketKind.Revolving));

    _depositAs(std, alice, DEPOSIT);
    _depositAs(rcf, alice, DEPOSIT);
    _borrowAs(std, DEPOSIT);
    _borrowAs(rcf, DEPOSIT);
    assertEq(
      IWildcatMarketRevolving(address(rcf.market)).drawnAmount(),
      DEPOSIT,
      'drawn != deposit'
    );

    // Segment 1: drawn == pre-accrual supply, so the trajectories must be
    // identical no matter how long the segment is.
    fastForward(45 days);
    std.market.updateState();
    rcf.market.updateState();
    assertEq(
      uint256(rcf.market.scaleFactor()),
      uint256(std.market.scaleFactor()),
      'segment 1: rcf != standard'
    );
    assertGt(uint256(std.market.scaleFactor()), RAY, 'segment 1: no accrual');

    // Segment 2: supply has outgrown the drawn amount; the revolving market
    // must now accrue strictly less than the standard market, and must still
    // match its own closed-form oracle.
    uint256 expectedRcf = _expectedScaleFactorAt(rcf, block.timestamp + 30 days);
    fastForward(30 days);
    std.market.updateState();
    rcf.market.updateState();
    assertEq(uint256(rcf.market.scaleFactor()), expectedRcf, 'segment 2: rcf oracle mismatch');
    assertLt(
      uint256(rcf.market.scaleFactor()),
      uint256(std.market.scaleFactor()),
      'segment 2: rcf should accrue less than standard'
    );
  }

  function test_zeroDrawn_accruesOnlyCommitmentFee() external {
    Cell memory cell = defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving);
    cell.commitmentFeeBips = 500;
    DeployedCell memory d = deployCell(cell);

    _depositAs(d, alice, DEPOSIT);
    assertEq(IWildcatMarketRevolving(address(d.market)).drawnAmount(), 0, 'drawn != 0');

    uint256 duration = 73 days;
    uint256 expected = uint256(RAY).rayMul(
      RAY + MathUtils.calculateLinearInterestFromBips(cell.commitmentFeeBips, duration)
    );
    fastForward(duration);
    d.market.updateState();
    assertEq(uint256(d.market.scaleFactor()), expected, 'fee-only accrual mismatch');

    // The APR (10% in the default cell) must not have contributed: a single
    // segment at the full APR would have produced a strictly larger factor.
    uint256 aprOnly = uint256(RAY).rayMul(
      RAY + MathUtils.calculateLinearInterestFromBips(cell.annualInterestBips, duration)
    );
    assertLt(uint256(d.market.scaleFactor()), aprOnly, 'APR leaked into undrawn market');
  }

  function test_fullRepay_returnsToFeeOnlyAccrual() external {
    Cell memory cell = defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving);
    cell.reserveRatioBips = 0;
    cell.delinquencyFeeBips = 0;
    cell.commitmentFeeBips = 300;
    DeployedCell memory d = deployCell(cell);

    _depositAs(d, alice, DEPOSIT);
    _borrowAs(d, DEPOSIT);
    _accrueAndCheck(d, 20 days);

    // Repay everything owed: the drawn amount must return to zero.
    uint256 debts = d.market.totalDebts();
    uint256 assets = asset.balanceOf(address(d.market));
    _repayAs(d, debts - assets);
    assertEq(
      IWildcatMarketRevolving(address(d.market)).drawnAmount(),
      0,
      'drawn != 0 after full repay'
    );

    // Subsequent accrual is commitment-fee only.
    uint256 scaleBefore = d.market.scaleFactor();
    uint256 duration = 15 days;
    uint256 expected = scaleBefore.rayMul(
      RAY + MathUtils.calculateLinearInterestFromBips(cell.commitmentFeeBips, duration)
    );
    fastForward(duration);
    d.market.updateState();
    assertEq(uint256(d.market.scaleFactor()), expected, 'post-repay accrual mismatch');
  }

  /// @dev CR-02 regression at the integration level: assets the borrower
  ///      supplied themselves (an over-repay) must not accrue lender APR when
  ///      re-borrowed.
  function test_overRepayThenBorrow_drawnClampedToOutstandingDebt() external {
    Cell memory cell = _differentialCell(MatrixMarketKind.Revolving);
    DeployedCell memory d = deployCell(cell);

    _depositAs(d, alice, DEPOSIT);
    _borrowAs(d, DEPOSIT / 2);

    // Borrower over-repays: returns the draw plus an extra 25% of the deposit.
    _repayAs(d, DEPOSIT / 2 + DEPOSIT / 4);
    assertEq(IWildcatMarketRevolving(address(d.market)).drawnAmount(), 0, 'drawn after over-repay');

    // Re-borrowing the surplus draws down self-supplied assets first: drawn
    // must be clamped to the market's outstanding debt, not the raw amount.
    uint256 borrowAmount = DEPOSIT / 2;
    uint256 assetsBefore = asset.balanceOf(address(d.market));
    uint256 debts = d.market.totalDebts();
    uint256 expectedDrawn = debts.satSub(assetsBefore - borrowAmount);
    _borrowAs(d, borrowAmount);
    assertEq(
      IWildcatMarketRevolving(address(d.market)).drawnAmount(),
      MathUtils.min(borrowAmount, expectedDrawn),
      'drawn not clamped to outstanding debt'
    );
    assertLt(
      IWildcatMarketRevolving(address(d.market)).drawnAmount(),
      borrowAmount,
      'clamp had no effect'
    );
  }
}

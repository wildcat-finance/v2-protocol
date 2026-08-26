// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketState } from 'src/libraries/MarketState.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

contract ProductionEconomicsTest is ProductionMatrixFixture {
  uint256 internal constant ProductionCapacity = 130_000_000e18;
  uint256 internal constant ProductionDraw = 70_000_000e18;

  function test_largeBalanceDelinquencyLifecycleMatchesOracleAcrossMarketTypes() external {
    ProductionStack memory stack = _deployProductionStack();

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      _runDelinquencyLifecycle(stack, MatrixMarketKind(marketKind), uint96(200 + marketKind));
    }
  }

  function test_largeBalanceYieldCrossoverPinsStandardAndRevolvingEconomics() external {
    ProductionStack memory stack = _deployProductionStack();

    _assertYieldOrdering(stack, 13_000_000e18, false, 210);
    _assertYieldOrdering(stack, ProductionDraw, true, 211);
    _assertYieldOrdering(stack, 123_500_000e18, true, 212);
  }

  function _runDelinquencyLifecycle(
    ProductionStack memory stack,
    MatrixMarketKind marketKind,
    uint96 nonce
  ) private {
    MatrixOptions memory options = _productionOptions(marketKind);
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    _authorize(stack, cell, MatrixAlice);
    _authorize(stack, cell, MatrixBob);
    _deposit(stack, cell, MatrixAlice, 80_000_000e18);
    _deposit(stack, cell, MatrixBob, 50_000_000e18);
    _approveBorrower(stack, cell, options.maxTotalSupply);
    _borrow(cell, ProductionDraw);

    assertEq(cell.market.maxTotalSupply(), ProductionCapacity, 'production capacity');
    assertEq(cell.market.annualInterestBips(), 850, 'production APR');
    assertEq(cell.market.reserveRatioBips(), 2_000, 'production reserve ratio');

    _accrueAndCheck(cell, 30 days);
    assertFalse(cell.market.previousState().isDelinquent, 'quiet month delinquency');

    uint256 remaining = cell.market.borrowableAssets();
    assertTrue(remaining > 0, 'remaining draw');
    _borrow(cell, remaining);
    _accrueAndCheck(cell, 12 hours);
    assertTrue(cell.market.previousState().isDelinquent, 'full draw delinquency');

    _accrueAndCheck(cell, 24 hours);
    MarketState memory graceState = cell.market.previousState();
    assertEq(graceState.timeDelinquent, 24 hours, 'grace clock');

    uint256 scaleBeforePenalty = graceState.scaleFactor;
    _accrueAndCheck(cell, 5 days);
    MarketState memory penaltyState = cell.market.previousState();
    assertEq(penaltyState.timeDelinquent, 6 days, 'penalty clock');
    assertTrue(penaltyState.scaleFactor > scaleBeforePenalty, 'penalty accrual');

    uint256 debts = cell.market.totalDebts();
    uint256 assets = stack.asset.balanceOf(address(cell.market));
    assertTrue(debts > assets, 'debt shortfall');
    _repay(cell, debts - assets);
    assertFalse(cell.market.previousState().isDelinquent, 'repayment recovery');

    _accrueAndCheck(cell, 24 hours);
    assertEq(cell.market.previousState().timeDelinquent, 5 days, 'recovery decay');
    _accrueAndCheck(cell, 7 days);
    assertFalse(cell.market.previousState().isDelinquent, 'recovered delinquency');
    assertEq(cell.market.previousState().timeDelinquent, 0, 'recovered clock');
  }

  function _assertYieldOrdering(
    ProductionStack memory stack,
    uint256 draw,
    bool revolvingWins,
    uint96 nonce
  ) private {
    MatrixOptions memory standardOptions = _productionOptions(MatrixMarketKind.Standard);
    MatrixOptions memory revolvingOptions = _productionOptions(MatrixMarketKind.Revolving);
    standardOptions.reserveRatioBips = 0;
    revolvingOptions.reserveRatioBips = 0;
    standardOptions.delinquencyFeeBips = 0;
    revolvingOptions.delinquencyFeeBips = 0;

    MatrixCell memory standard = _deployMatrixCell(
      stack,
      standardOptions,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    MatrixCell memory revolving = _deployMatrixCell(
      stack,
      revolvingOptions,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    _authorize(stack, standard, MatrixAlice);
    _authorize(stack, revolving, MatrixAlice);
    _deposit(stack, standard, MatrixAlice, ProductionCapacity);
    _deposit(stack, revolving, MatrixAlice, ProductionCapacity);
    _approveBorrower(stack, standard, ProductionCapacity);
    _approveBorrower(stack, revolving, ProductionCapacity);
    _borrow(standard, draw);
    _borrow(revolving, draw);

    uint256 target = vm.getBlockTimestamp() + 30 days;
    uint256 expectedStandard = _expectedScaleFactorAt(standard, target);
    uint256 expectedRevolving = _expectedScaleFactorAt(revolving, target);
    vm.warp(target);
    standard.market.updateState();
    revolving.market.updateState();
    assertEq(standard.market.scaleFactor(), expectedStandard, 'standard yield oracle');
    assertEq(revolving.market.scaleFactor(), expectedRevolving, 'revolving yield oracle');

    if (revolvingWins) {
      assertTrue(expectedRevolving > expectedStandard, 'revolving should win');
    } else {
      assertTrue(expectedRevolving < expectedStandard, 'standard should win');
    }
  }

  function _productionOptions(
    MatrixMarketKind marketKind
  ) private pure returns (MatrixOptions memory options) {
    options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, marketKind);
    options.maxTotalSupply = uint128(ProductionCapacity);
    options.annualInterestBips = 850;
    options.delinquencyFeeBips = 500;
    options.delinquencyGracePeriod = 48 hours;
    options.withdrawalBatchDuration = 24 hours;
    options.reserveRatioBips = 2_000;
    options.commitmentFeeBips = 400;
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // GraceTrackerDefaultTest
//  \ ^ /   Default follows the growing and decaying grace tracker.
//    V
//
//  FIXTURE
//  setUp()
//  _delinquentCell(...)
//
//  TRACKER DEFAULT
//  test_defaultWithoutWithdrawalsOrPenaltyApr()
//  test_repeatedBriefCuresOnlyEarnTheirRecoveryTime()
//  test_sameTimestampCureAndRelapseDoNotRestoreAllowance()
//  test_recoveryThroughGraceAndZeroRestoresRecoveredAllowance()
//  test_repaymentPenaltyDoesNotShortenTheTrackerThreshold()
// ═════

import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { MarketState } from 'src/libraries/MarketState.sol';

contract GraceTrackerDefaultTest is ProductionMatrixFixture {
  ProductionStack internal stack;
  uint96 private _nonce;

  // ┌─ setUp ─────
  function setUp() public {
    vm.warp(1_800_000_000);
    stack = _deployProductionStack();
  }

  // ┌─ _delinquentCell ─────
  function _delinquentCell(uint256 model, uint32 grace, uint32 date) private returns (MatrixCell memory cell) {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind(model));
    options.annualInterestBips = 1_000;
    options.commitmentFeeBips = 0;
    options.delinquencyFeeBips = 0;
    options.delinquencyGracePeriod = grace;
    options.repaymentDate = date;
    options.repaymentPeriod = date == 0 ? 0 : 90 days;
    cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, ++_nonce);
    _authorize(stack, cell, MatrixAlice);
    _approveBorrower(stack, cell, 1_000_000e18);
    _deposit(stack, cell, MatrixAlice, 1_000e18);
    _borrow(cell, 800e18);
    vm.warp(vm.getBlockTimestamp() + 1);
    cell.market.updateState();
    assertTrue(cell.market.previousState().isDelinquent, 'interest exhausts exact reserves');
    assertEq(cell.market.previousState().timeDelinquent, 0, 'tracker begins at observed shortfall');
  }

  // ┌─ test_defaultWithoutWithdrawalsOrPenaltyApr ─────
  function test_defaultWithoutWithdrawalsOrPenaltyApr() public {
    for (uint256 model; model < 2; ++model) {
      MatrixCell memory cell = _delinquentCell(model, 2 days, 0);
      uint256 cutoff = vm.getBlockTimestamp() + 92 days;
      vm.warp(cutoff);
      cell.market.updateState();
      MarketState memory state = cell.market.previousState();
      assertEq(state.timeDelinquent, 92 days, 'grace plus exactly ninety days');
      assertEq(state.scaledPendingWithdrawals, 0, 'no withdrawal required');
      assertEq(state.pendingWithdrawalExpiry, 0, 'no withdrawal batch');
      assertEq(cell.market.delinquencyFeeBips(), 0, 'no penalty APR required');
      assertEq(cell.market.defaultedAt(), 0, 'threshold must be exceeded');
      vm.warp(cutoff + 1);
      cell.market.updateState();
      assertEq(cell.market.defaultedAt(), cutoff, 'historical threshold recorded');
      _repay(cell, cell.market.totalDebts() - cell.market.totalAssets());
      vm.warp(cutoff + 3 days);
      cell.market.updateState();
      assertEq(cell.market.defaultedAt(), cutoff, 'repayment and decay cannot erase default');
    }
  }

  // ┌─ test_repeatedBriefCuresOnlyEarnTheirRecoveryTime ─────
  function test_repeatedBriefCuresOnlyEarnTheirRecoveryTime() public {
    for (uint256 model; model < 2; ++model) {
      MatrixCell memory cell = _delinquentCell(model, 2 days, 0);
      uint256 originalCutoff = vm.getBlockTimestamp() + 92 days;
      for (uint256 cure; cure < 3; ++cure) {
        vm.warp(vm.getBlockTimestamp() + 20 days);
        _repay(cell, cell.market.coverageLiquidity() - cell.market.totalAssets());
        uint256 tracker = cell.market.previousState().timeDelinquent;
        assertFalse(cell.market.previousState().isDelinquent, 'reserve shortfall cured');
        vm.warp(vm.getBlockTimestamp() + 1);
        cell.market.updateState();
        assertEq(cell.market.previousState().timeDelinquent, tracker - 1, 'one second recovered');
        assertTrue(cell.market.previousState().isDelinquent, 'interest resumes delinquency');
      }
      uint256 cutoff = originalCutoff + 6;
      vm.warp(cutoff);
      cell.market.updateState();
      assertEq(
        cell.market.previousState().timeDelinquent, 92 days, 'three healthy seconds earned six wall-clock seconds'
      );
      assertEq(cell.market.defaultedAt(), 0, 'exact threshold remains curable');
      vm.warp(cutoff + 1);
      cell.market.updateState();
      assertEq(cell.market.defaultedAt(), cutoff, 'cures did not grant fresh ninety-day runs');
    }
  }

  // ┌─ test_sameTimestampCureAndRelapseDoNotRestoreAllowance ─────
  function test_sameTimestampCureAndRelapseDoNotRestoreAllowance() public {
    for (uint256 model; model < 2; ++model) {
      MatrixCell memory cell = _delinquentCell(model, 2 days, 0);
      uint256 cutoff = vm.getBlockTimestamp() + 92 days;
      vm.warp(vm.getBlockTimestamp() + 30 days);
      _repay(cell, cell.market.totalDebts() - cell.market.totalAssets());
      assertFalse(cell.market.previousState().isDelinquent, 'full repayment cures shortfall');
      uint256 tracker = cell.market.previousState().timeDelinquent;
      _borrow(cell, cell.market.borrowableAssets());
      vm.prank(MatrixAlice);
      cell.market.queueFullWithdrawal();
      assertTrue(cell.market.previousState().isDelinquent, 'same-timestamp withdrawal resumes shortfall');
      assertEq(cell.market.previousState().timeDelinquent, tracker, 'no elapsed recovery');
      vm.warp(cutoff + 1);
      cell.market.updateState();
      assertEq(cell.market.defaultedAt(), cutoff, 'original tracker cutoff retained');
    }
  }

  // ┌─ test_recoveryThroughGraceAndZeroRestoresRecoveredAllowance ─────
  function test_recoveryThroughGraceAndZeroRestoresRecoveredAllowance() public {
    for (uint256 model; model < 2; ++model) {
      for (uint256 fullyRecovered; fullyRecovered < 2; ++fullyRecovered) {
        MatrixCell memory cell = _delinquentCell(model, 2 days, 0);
        vm.warp(vm.getBlockTimestamp() + 6 days);
        _repay(cell, cell.market.totalDebts() - cell.market.totalAssets());
        vm.warp(vm.getBlockTimestamp() + (fullyRecovered == 0 ? 5 days : 10 days));
        cell.market.updateState();
        uint256 recoveredTracker = fullyRecovered == 0 ? 1 days : 0;
        assertEq(cell.market.previousState().timeDelinquent, recoveredTracker, 'tracker decays through grace to zero');
        _borrow(cell, cell.market.borrowableAssets());
        vm.warp(vm.getBlockTimestamp() + 1);
        cell.market.updateState();
        uint256 remainingTracker = fullyRecovered == 0 ? 1 days - 1 : 0;
        assertEq(cell.market.previousState().timeDelinquent, remainingTracker, 'last healthy second also decays');
        assertTrue(cell.market.previousState().isDelinquent, 'interest resumes shortfall');
        uint256 cutoff = vm.getBlockTimestamp() + 92 days - remainingTracker;
        vm.warp(cutoff);
        cell.market.updateState();
        assertEq(cell.market.defaultedAt(), 0, 'remaining allowance reaches exact threshold');
        assertEq(cell.market.previousState().timeDelinquent, 92 days, 'configured grace restored through decay');
        vm.warp(cutoff + 1);
        cell.market.updateState();
        assertEq(cell.market.defaultedAt(), cutoff, 'new default reflects actual recovery');
      }
    }
  }

  // ┌─ test_repaymentPenaltyDoesNotShortenTheTrackerThreshold ─────
  function test_repaymentPenaltyDoesNotShortenTheTrackerThreshold() public {
    for (uint256 model; model < 2; ++model) {
      uint32 date = uint32(vm.getBlockTimestamp() + 50 days);
      MatrixCell memory cell = _delinquentCell(model, 20 days, date);
      uint256 start = vm.getBlockTimestamp();
      vm.warp(start + 91 days);
      cell.market.updateState();
      assertEq(cell.market.reserveRatioBips(), 10_000, 'scheduled repayment active');
      assertEq(cell.market.previousState().timeDelinquent, 91 days, 'repayment preserves tracker');
      assertEq(cell.market.defaultedAt(), 0, 'configured grace still counts for tracker default');
      uint256 cutoff = start + 110 days;
      vm.warp(cutoff + 1);
      cell.market.updateState();
      assertTrue(cutoff < cell.market.repaymentDeadline(), 'tracker threshold precedes repayment deadline');
      assertEq(cell.market.defaultedAt(), cutoff, 'tracker is independent of fee grace override');
    }
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LifecycleScenarios.t
//  \ ^ /   Deterministic and fuzzed lifecycle boundary and drain scenarios.
//    V
//
//  FIXTURE
//  setUp()
//
//  TIMELINE AND CURE
//  test_seededMatrixMatchesIndependentOracle()
//  test_idleDateAndDeadlineCrossingMatchesOracle()
//  testFuzz_deadlineCureIsInclusive(...)
//  test_oneWeiShortDoesNotCloseAndSameTimestampCureCounts()
//  testFuzz_lateDonationCannotRewriteFunding(...)
//
//  REPAYMENT ADMISSION
//  test_repaymentRejectsAdmissionAndBothAprRoutes()
//
//  BATCH FUNDING AND DRAIN
//  test_forcedQueueRetainsFractionalDebtAndItsBatchClaim()
//  test_boundedPaymentPreservesDebtUntilFullyFunded()
//  test_partialBatchesSanctionedCollectionAndScheduledDrain()
//  testFuzz_batchExpiryAtInclusiveDeadline(...)
//  test_surplusRecoveryPreservesScheduledDrain()
// ═════

import { LifecycleFixture } from './LifecycleFixture.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';

// ┌─ LifecycleScenariosTest ───────────────────────────────────────────────────
contract LifecycleScenariosTest is LifecycleFixture {
  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    _setupLifecycle();
  }

  // ░░▒▒▓▓██ [ TIMELINE AND CURE ] ────────────────────────────────────────────

  // ┌─ test_seededMatrixMatchesIndependentOracle ─────
  function test_seededMatrixMatchesIndependentOracle() external view {
    _assertLifecycle();
  }

  // ┌─ test_idleDateAndDeadlineCrossingMatchesOracle ─────
  function test_idleDateAndDeadlineCrossingMatchesOracle() external {
    vm.warp(vm.getBlockTimestamp() + 160 days);
    _assertLifecycle();
    lifecycle.updateState();
    _assertLifecycle();
  }

  // ┌─ testFuzz_deadlineCureIsInclusive ─────
  function testFuzz_deadlineCureIsInclusive(uint8 cell, bool late, bool process, uint8 updates) external {
    uint256 i = uint256(cell) % MatrixSize;
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
    uint256 deadline = market.repaymentDeadline();
    vm.warp(deadline + (late ? 1 : 0));
    for (uint256 n; n < uint256(updates) % 3; ++n) {
      lifecycle.checkpoint(i);
    }
    lifecycle.fund(i, 1, 1, process);
    assertTrue(market.previousState().isClosed, 'full funding closes');
    assertEq(market.defaultedAt(), late ? deadline : 0, 'inclusive cutoff');
    uint256 scale = market.scaleFactor();
    vm.warp(deadline + 120 days);
    lifecycle.checkpoint(i);
    assertEq(market.scaleFactor(), scale, 'closed economics');
    assertEq(market.defaultedAt(), late ? deadline : 0, 'permanent marker');
    _assertLifecycle();
  }

  // ┌─ test_oneWeiShortDoesNotCloseAndSameTimestampCureCounts ─────
  function test_oneWeiShortDoesNotCloseAndSameTimestampCureCounts() external {
    uint256 snapshot = vm.snapshot();
    for (uint256 i; i < MatrixSize; ++i) {
      WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
      vm.warp(market.repaymentDeadline());
      lifecycle.checkpoint(i);
      lifecycle.fund(i, 2, 0, false);
      assertFalse(market.isClosed(), 'one wei remains due');
      assertEq(market.defaultedAt(), 0, 'cutoff still open');
      lifecycle.fund(i, 1, 0, false);
      assertTrue(market.isClosed(), 'exact final wei');
      vm.warp(vm.getBlockTimestamp() + 1);
      lifecycle.checkpoint(i);
      assertEq(market.defaultedAt(), 0, 'same timestamp cure');
      _assertLifecycle();
      assertTrue(vm.revertTo(snapshot), 'restore matrix');
    }
  }

  // ┌─ testFuzz_lateDonationCannotRewriteFunding ─────
  function testFuzz_lateDonationCannotRewriteFunding(uint8 cell, bool beforeDeadline) external {
    uint256 i = uint256(cell) % MatrixSize;
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
    uint256 deadline = market.repaymentDeadline();
    vm.warp(deadline + (beforeDeadline ? 0 : 1));
    lifecycle.donate(i, 1, 0);
    assertEq(market.defaultedAt(), 0, 'transfer is not a write');
    // even a transfer at the deadline is late if the first market write observes it afterward.
    vm.warp(deadline + 1);
    lifecycle.checkpoint(i);
    assertEq(market.defaultedAt(), deadline, 'last observed cash decides');
    if (!market.isClosed()) lifecycle.fund(i, 1, 0, false);
    assertTrue(market.isClosed(), 'current funding can finish');
    _assertLifecycle();
  }

  // ░░▒▒▓▓██ [ REPAYMENT ADMISSION ] ──────────────────────────────────────────

  // ┌─ test_repaymentRejectsAdmissionAndBothAprRoutes ─────
  function test_repaymentRejectsAdmissionAndBothAprRoutes() external {
    uint256 date = WildcatMarket(lifecycle.marketAt(2)).repaymentDate();
    // propose after the first window so execution is ready during repayment, not expired.
    vm.warp(date - 22 days);
    lifecycle.proposeAprReduction(500);
    vm.warp(date + 8 days);
    for (uint256 i; i < MatrixSize; ++i) {
      lifecycle.probeAdmission(i);
      lifecycle.changeApr(i, 900, 0);
      lifecycle.changeApr(i, 1_100, 1);
    }
    lifecycle.executeAprReduction();
    for (uint256 i = 2; i < MatrixSize; i += 3) {
      WildcatMarket periodic = WildcatMarket(lifecycle.marketAt(i));
      vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForOldLiquidityRatio.selector);
      periodic.executePendingAnnualInterestBipsReduction();
    }
    lifecycle.updateState();
    for (uint256 i; i < MatrixSize; ++i) {
      WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
      assertEq(market.reserveRatioBips(), 10_000, 'reserve floor');
      assertEq(market.annualInterestBips(), 1_000, 'underfunded APR unchanged');
    }
    _assertLifecycle();
  }

  // ░░▒▒▓▓██ [ BATCH FUNDING AND DRAIN ] ──────────────────────────────────────

  // ┌─ test_forcedQueueRetainsFractionalDebtAndItsBatchClaim ─────
  function test_forcedQueueRetainsFractionalDebtAndItsBatchClaim() external {
    lifecycle.sanctionLender(0);
    lifecycle.advance(1, 2, 34_689_600_001);
    lifecycle.fund(2, 2, 95, true);
    lifecycle.nukeFromOrbit(0);
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(2));
    assertFalse(market.previousState().isClosed, 'forced queue preserves the unpaid fraction');
    assertEq(market.totalDebts(), market.totalAssets() + 1);
    lifecycle.fund(2, 1, 0, false);
    assertTrue(market.previousState().isClosed, 'full funding closes');
    assertEq(market.previousState().pendingWithdrawalExpiry, 0, 'closure releases the batch');
    assertEq(lifecycle.trackedExpiryCount(2), 1, 'released batch remains tracked');
    _assertLifecycle();
    _finishLifecycle('forced-queue-regression');
  }

  // ┌─ test_boundedPaymentPreservesDebtUntilFullyFunded ─────
  function test_boundedPaymentPreservesDebtUntilFullyFunded() external {
    lifecycle.queueFullWithdrawal(0);
    lifecycle.advance(1, 1, 0);
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(3));
    lifecycle.fund(3, 2, 2, true);
    assertFalse(market.previousState().isClosed, 'allocation does not discard carried debt');
    assertEq(market.totalDebts(), market.totalAssets() + 1);
    lifecycle.fund(3, 1, 0, false);
    assertTrue(market.previousState().isClosed, 'full funding closes');
    assertEq(market.totalAssets(), market.totalDebts(), 'all remaining liabilities backed');
    assertEq(IWildcatMarketRevolving(address(market)).drawnAmount(), 0, 'closure clears principal');
    _assertLifecycle();
  }

  // ┌─ test_partialBatchesSanctionedCollectionAndScheduledDrain ─────
  function test_partialBatchesSanctionedCollectionAndScheduledDrain() external {
    lifecycle.deposit(1, 1_000e18);
    lifecycle.transfer(1, 2, 500e18);
    lifecycle.drawAvailable();
    WildcatMarket first = WildcatMarket(lifecycle.marketAt(0));
    vm.warp(first.repaymentDate());
    lifecycle.queueWithdrawalScaled(1, 250e18);
    lifecycle.queueWithdrawal(2, 200e18);
    lifecycle.queueFullWithdrawal(0);
    for (uint256 i; i < MatrixSize; ++i) {
      lifecycle.fund(i, 0, 2, false);
    }
    vm.warp(vm.getBlockTimestamp() + 2 days);
    lifecycle.updateState();
    lifecycle.sanctionLender(2);
    for (uint256 i; i < MatrixSize; ++i) {
      for (uint256 j; j < lifecycle.trackedExpiryCount(i); ++j) {
        lifecycle.collectClaims(i, 1, j);
        lifecycle.collectClaim(i, 1, j);
        lifecycle.collectClaim(i, 2, j);
        // a consumed entitlement cannot be collected again without another allocation.
        lifecycle.collectClaim(i, 1, j);
        lifecycle.collectClaim(i, 2, j);
      }
      lifecycle.fund(i, 3, 100e18, true);
    }
    _assertLifecycle();
    (, uint256 failure) = lifecycle.unwindAndDrain();
    assertEq(failure, 0, 'bounded scheduled exit');
    _assertLifecycle();
  }

  // ┌─ testFuzz_batchExpiryAtInclusiveDeadline ─────
  function testFuzz_batchExpiryAtInclusiveDeadline(bool late, bool process) external {
    lifecycle.deposit(1, 1_000e18);
    lifecycle.drawAvailable();
    uint256 snapshot = vm.snapshot();
    for (uint256 i; i < MatrixSize; ++i) {
      WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
      uint256 deadline = market.repaymentDeadline();
      vm.warp(deadline - 1 days);
      lifecycle.queueFullWithdrawal(1);
      assertEq(market.previousState().pendingWithdrawalExpiry, deadline, 'batch/deadline tie');
      vm.warp(deadline + (late ? 1 : 0));
      lifecycle.fund(i, 1, 1, process);
      assertEq(market.defaultedAt(), late ? deadline : 0, 'inclusive boundary ordering');
      assertTrue(market.isClosed(), 'timely or late completion');
      _assertLifecycle();
      assertTrue(vm.revertTo(snapshot), 'restore tied boundary');
    }
  }

  // ┌─ test_surplusRecoveryPreservesScheduledDrain ─────
  function test_surplusRecoveryPreservesScheduledDrain() external {
    for (uint256 i; i < MatrixSize; ++i) {
      WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
      uint256 deadline = market.repaymentDeadline();
      if (vm.getBlockTimestamp() < deadline) vm.warp(deadline);
      lifecycle.fund(i, 3, 50e18, true);
      lifecycle.recoverSurplus(i);
      assertEq(market.totalAssets(), market.totalDebts(), 'every liability retained');
      _assertLifecycle();
    }
    _finishLifecycle('surplus-recovery');
  }
}

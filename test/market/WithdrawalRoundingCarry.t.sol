// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WithdrawalRoundingCarry.t
//  \ ^ /   Withdrawal carry collection, closure, and numerator conservation.
//    V
//
//  CARRY COLLECTION
//  test_carryCollectsElevenInsteadOfTen_AcrossMarketKinds()
//  _accrued(...)
//
//  CARRY SETTLEMENT
//  test_carryDebtClosesExactly_AcrossMarketKinds()
//  test_multipleBatchRemaindersCloseAndPayExactly_AcrossMarketKinds()
//  test_automaticClosureProtectsCarryFromRescue_AcrossMarketKinds()
//  test_finalFractionReleasedOnlyWhenBatchCannotGrow_AcrossMarketKinds()
//  test_closeReturnsOnlyTrueSurplusThroughRescue_AcrossMarketKinds()
//  prepareTwoBatches(...)
//  _frozen(...)
//  _setFactor(...)
//
//  NUMERATOR CONSERVATION
//  testFuzz_paymentNumeratorsAccumulateAcrossChangingFactors(...)
// ═════

import { RAY } from 'src/libraries/MathUtils.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';

// ┌─ WithdrawalRoundingCarryTest ──────────────────────────────────────────────
contract WithdrawalRoundingCarryTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);

  // ░░▒▒▓▓██ [ CARRY COLLECTION ] ─────────────────────────────────────────────

  // ┌─ test_carryCollectsElevenInsteadOfTen_AcrossMarketKinds ─────
  function test_carryCollectsElevenInsteadOfTen_AcrossMarketKinds() external {
    for (uint256 i; i < 4; ++i) {
      (Fixture memory f, uint32 expiry) = _accrued(10, 1000, i >= 2, HooksKind(i % 2));
      assertEq(f.market.scaleFactor(), (11 * RAY) / 10);
      for (uint256 j; j < 11; ++j) {
        vm.prank(Borrower);
        f.market.repay(1);
      }
      WithdrawalBatch memory batch = f.market.getWithdrawalBatch(expiry);
      assertEq(batch.scaledAmountBurned, 10);
      assertEq(batch.normalizedAmountPaid, 11);
      assertEq(batch.paymentRemainder, 0);
    }
  }

  // ┌─ _accrued ─────
  function _accrued(
    uint128 amount,
    uint16 rate,
    bool revolving,
    HooksKind kind
  )
    private
    returns (Fixture memory fixture, uint32 expiry)
  {
    Options memory options = _defaultOptions(kind);
    options.revolving = revolving;
    options.annualInterestBips = rate;
    options.protocolFeeBips = 0;
    options.delinquencyFeeBips = 0;
    options.commitmentFeeBips = 0;
    options.reserveRatioBips = 0;
    fixture = _newMarket(options);
    _deposit(fixture, Holder, amount);
    vm.prank(Borrower);
    fixture.market.borrow(amount);
    vm.warp(vm.getBlockTimestamp() + 365 days);
    vm.prank(Holder);
    expiry = fixture.market.queueFullWithdrawal();
    _fundAndApprove(fixture, Borrower, uint256(amount) * 4);
  }

  // ░░▒▒▓▓██ [ CARRY SETTLEMENT ] ─────────────────────────────────────────────

  // ┌─ test_carryDebtClosesExactly_AcrossMarketKinds ─────
  function test_carryDebtClosesExactly_AcrossMarketKinds() external {
    for (uint256 i; i < 4; ++i) {
      (Fixture memory f, uint32 expiry) = _accrued(4, 2500, i >= 2, HooksKind(i % 2));
      assertEq(f.market.scaleFactor(), (5 * RAY) / 4);
      vm.prank(Borrower);
      f.market.repay(3);
      WithdrawalBatch memory batch = f.market.getWithdrawalBatch(expiry);
      assertEq(batch.scaledAmountBurned, 3);
      assertEq(batch.normalizedAmountPaid, 3);
      assertEq(batch.paymentRemainder, (3 * RAY) / 4);
      assertEq(f.market.totalDebts(), 5, 'carry counted in debt');
      assertEq(f.market.currentState().withdrawalRemainder, (3 * RAY) / 4);
      vm.prank(Borrower);
      f.market.closeMarket();
      assertTrue(f.market.isClosed());
      assertEq(f.market.currentState().withdrawalRemainder, 0);
      assertEq(f.market.getWithdrawalBatch(expiry).normalizedAmountPaid, 5);
      assertEq(f.market.executeWithdrawal(Holder, expiry), 5);
      assertEq(f.market.totalAssets(), 0);
      assertEq(f.market.totalDebts(), 0);
    }
  }

  // ┌─ test_multipleBatchRemaindersCloseAndPayExactly_AcrossMarketKinds ─────
  function test_multipleBatchRemaindersCloseAndPayExactly_AcrossMarketKinds() external {
    for (uint256 i; i < 4; ++i) {
      Fixture memory f = _frozen(8, 0, i >= 2, HooksKind(i % 2));
      (uint32 first, uint32 second) = this.prepareTwoBatches(f);
      vm.prank(Borrower);
      f.market.closeMarket();
      assertEq(f.market.currentState().withdrawalRemainder, 0);
      assertEq(f.market.getUnpaidBatchExpiries().length, 0);
      assertEq(f.market.executeWithdrawal(Holder, first), 5);
      assertEq(f.market.executeWithdrawal(Holder, second), 5);
      assertEq(f.market.totalAssets(), 0);
    }
  }

  // ┌─ test_automaticClosureProtectsCarryFromRescue_AcrossMarketKinds ─────
  function test_automaticClosureProtectsCarryFromRescue_AcrossMarketKinds() external {
    for (uint256 i; i < 4; ++i) {
      uint32 date = uint32(vm.getBlockTimestamp() + 100);
      Fixture memory f = _frozen(8, date, i >= 2, HooksKind(i % 2));
      (uint32 first, uint32 second) = this.prepareTwoBatches(f);
      f.asset.mint(address(f.market), 3);
      // write this backing before the repayment boundary so the historical decision sees it.
      f.market.updateState();
      vm.warp(date);
      f.market.updateState();
      assertTrue(f.market.isClosed());
      assertEq(f.market.totalDebts(), 10);
      assertEq(f.market.currentState().withdrawalRemainder, (3 * RAY) / 4);
      assertEq(f.market.getUnpaidBatchExpiries().length, 1);
      uint256 borrowerBalance = f.asset.balanceOf(Borrower);
      vm.prank(Borrower);
      f.market.rescueTokens(address(f.asset));
      assertEq(f.asset.balanceOf(Borrower), borrowerBalance, 'carry cannot be rescued');
      f.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      assertEq(f.market.currentState().withdrawalRemainder, 0);
      assertEq(f.market.executeWithdrawal(Holder, first), 5);
      assertEq(f.market.executeWithdrawal(Holder, second), 5);
      assertEq(f.market.totalAssets(), 0);
    }
  }

  // ┌─ test_finalFractionReleasedOnlyWhenBatchCannotGrow_AcrossMarketKinds ─────
  function test_finalFractionReleasedOnlyWhenBatchCannotGrow_AcrossMarketKinds() external {
    for (uint256 i; i < 4; ++i) {
      Fixture memory f = _frozen(3, 0, i >= 2, HooksKind(i % 2));
      vm.prank(Holder);
      uint32 expiry = f.market.queueFullWithdrawal();
      vm.prank(Borrower);
      f.market.repay(3);
      assertEq(f.market.currentState().withdrawalRemainder, (3 * RAY) / 4);
      assertEq(f.market.getWithdrawalBatch(expiry).paymentRemainder, (3 * RAY) / 4);
      vm.warp(uint256(expiry) + 1);
      f.market.updateState();
      assertEq(f.market.currentState().withdrawalRemainder, 0);
      assertEq(f.market.getWithdrawalBatch(expiry).paymentRemainder, 0);
      assertEq(f.market.executeWithdrawal(Holder, expiry), 3);
      assertEq(f.market.totalDebts(), 0);
    }
  }

  // ┌─ test_closeReturnsOnlyTrueSurplusThroughRescue_AcrossMarketKinds ─────
  function test_closeReturnsOnlyTrueSurplusThroughRescue_AcrossMarketKinds() external {
    for (uint256 i; i < 4; ++i) {
      Fixture memory f = _frozen(3, 0, i >= 2, HooksKind(i % 2));
      vm.prank(Holder);
      uint32 expiry = f.market.queueFullWithdrawal();
      vm.prank(Borrower);
      f.market.repay(1);
      assertEq(f.market.totalDebts(), 4);
      vm.prank(Borrower);
      f.market.closeMarket();
      assertEq(f.market.totalDebts(), 3);
      assertEq(f.market.totalAssets(), 4);
      uint256 borrowerBalance = f.asset.balanceOf(Borrower);
      vm.prank(Borrower);
      f.market.rescueTokens(address(f.asset));
      assertEq(f.asset.balanceOf(Borrower), borrowerBalance + 1);
      assertEq(f.market.executeWithdrawal(Holder, expiry), 3);
      assertEq(f.market.totalAssets(), 0);
    }
  }

  // ┌─ prepareTwoBatches ─────
  function prepareTwoBatches(Fixture memory f) external returns (uint32 first, uint32 second) {
    vm.prank(Holder);
    first = f.market.queueWithdrawalScaled(4);
    vm.prank(Borrower);
    f.market.repay(3);
    vm.warp(uint256(first) + 1);
    f.market.updateState();
    vm.prank(Holder);
    second = f.market.queueFullWithdrawal();
    vm.prank(Borrower);
    f.market.repay(4);
    assertEq(f.market.getWithdrawalBatch(first).paymentRemainder, (3 * RAY) / 4);
    assertEq(f.market.getWithdrawalBatch(second).paymentRemainder, RAY / 2);
    assertEq(f.market.currentState().withdrawalRemainder, (5 * RAY) / 4, 'sum crosses one whole unit');
    assertEq(f.market.totalDebts(), 10);
    assertEq(f.market.coverageLiquidity(), 10);
    assertEq(f.market.borrowableAssets(), 0);
  }

  // ┌─ _frozen ─────
  function _frozen(uint128 amount, uint32 date, bool revolving, HooksKind kind) private returns (Fixture memory f) {
    Options memory options = _defaultOptions(kind);
    options.revolving = revolving;
    options.annualInterestBips = 0;
    options.protocolFeeBips = 0;
    options.delinquencyFeeBips = 0;
    options.commitmentFeeBips = 0;
    options.reserveRatioBips = 0;
    options.withdrawalBatchDuration = 10;
    options.repaymentDate = date;
    options.repaymentPeriod = date == 0 ? 0 : 3600;
    f = _newMarket(options);
    _deposit(f, Holder, amount);
    vm.prank(Borrower);
    f.market.borrow(amount);
    _fundAndApprove(f, Borrower, uint256(amount) * 10 + 10);
    _setFactor(f, uint112((5 * RAY) / 4));
  }

  // fix a valid scale without accruing again, so expected rounding doesn't depend on timing
  // or the revolving utilization formula.
  // ┌─ _setFactor ─────
  function _setFactor(Fixture memory f, uint112 factor) private {
    bytes32 word = vm.load(address(f.market), bytes32(uint256(3)));
    uint256 mask = uint256(type(uint112).max) << 80;
    vm.store(address(f.market), bytes32(uint256(3)), bytes32((uint256(word) & ~mask) | (uint256(factor) << 80)));
    assertEq(f.market.scaleFactor(), factor);
  }

  // ░░▒▒▓▓██ [ NUMERATOR CONSERVATION ] ───────────────────────────────────────

  // ┌─ testFuzz_paymentNumeratorsAccumulateAcrossChangingFactors ─────
  function testFuzz_paymentNumeratorsAccumulateAcrossChangingFactors(uint256 seed) external {
    Fixture memory f = _frozen(1000, 0, seed & 1 != 0, HooksKind((seed >> 1) & 1));
    vm.prank(Holder);
    uint32 expiry = f.market.queueFullWithdrawal();
    uint256 numerator;
    uint112 factor = uint112((5 * RAY) / 4);
    for (uint256 i; i < 12; ++i) {
      seed = uint256(keccak256(abi.encode(seed, i)));
      factor += uint112(seed % (RAY / 10));
      _setFactor(f, factor);
      uint256 beforeBurned = f.market.getWithdrawalBatch(expiry).scaledAmountBurned;
      vm.prank(Borrower);
      f.market.repay(1 + (seed % 7));
      WithdrawalBatch memory batch = f.market.getWithdrawalBatch(expiry);
      uint256 burned = batch.scaledAmountBurned - beforeBurned;
      numerator += burned * factor;
      assertEq(batch.normalizedAmountPaid, numerator / RAY, 'round the accumulated numerator once');
      assertEq(batch.paymentRemainder, numerator % RAY);
      assertEq(f.market.currentState().withdrawalRemainder, numerator % RAY);
    }
  }
}

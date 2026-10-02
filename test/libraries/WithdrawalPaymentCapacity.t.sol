// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WithdrawalPaymentCapacity.t
// ║  ██▀▀     ▀▀██   Payment capacity, carry conservation, and overflow boundaries.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  FIXTURE
// ║  setUp()
// ║
// ║  PAYMENT CAPACITY
// ║  testFuzz_capacityIsMaximalAndDebtIsConserved(...)
// ║  test_maximumFactorAndDonationDoNotOverflow()
// ║  testFuzz_paymentPreservesReservesWithFreeSupplyAndOtherCarry(...)
// ║  test_zeroAndOneUnitLiquidityPreserveCarry()
// ║  _checkPayment(...)
// ║
// ║  HEADROOM AND ACCOUNTING BOUNDS
// ║  test_globalUnclaimedHeadroomCapsPayment()
// ║  test_zeroGlobalUnclaimedHeadroomLeavesPositivePaymentUnprocessed()
// ║  test_cumulativePaidOverflowStillReverts()
// ║  test_syntheticWideCumulativeStateKeepsItsSmallLiveDifference()
// ║  test_missingAggregateContributionStillReverts()
// ╚═════

import { MarketFixture } from '../shared/MarketFixture.sol';
import { WithdrawalPaymentHarness } from '../mocks/WithdrawalPaymentHarness.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { RAY } from 'src/libraries/MathUtils.sol';

// ┌─ WithdrawalPaymentCapacityTest ────────────────────────────────────────────
contract WithdrawalPaymentCapacityTest is MarketFixture {
  WithdrawalPaymentHarness internal harness;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    Fixture memory fixture = _newMarket(HooksKind.OpenTerm);
    harness = WithdrawalPaymentHarness(
      fixture.factory.deployMarket(vm.getCode('test/mocks/WithdrawalPaymentHarness.sol:WithdrawalPaymentHarness'))
    );
  }

  // ░░▒▒▓▓██ [ PAYMENT CAPACITY ] ─────────────────────────────────────────────

  // ┌─ testFuzz_capacityIsMaximalAndDebtIsConserved ─────
  function testFuzz_capacityIsMaximalAndDebtIsConserved(
    uint104 owed,
    uint112 factor,
    uint128 remainder,
    uint256 available
  )
    external
    view
  {
    remainder = uint128(bound(remainder, 0, RAY - 1));
    factor = uint112(bound(factor, RAY, type(uint112).max));
    _checkPayment(owed, factor, remainder, available);
  }

  // ┌─ test_maximumFactorAndDonationDoNotOverflow ─────
  function test_maximumFactorAndDonationDoNotOverflow() external view {
    _checkPayment(type(uint104).max, type(uint112).max, uint128(RAY - 1), type(uint256).max);
    _checkPayment(type(uint104).max, type(uint112).max, uint128(RAY - 1), type(uint256).max / RAY);
    _checkPayment(type(uint104).max, type(uint112).max, uint128(RAY - 1), 1);
  }

  // ┌─ testFuzz_paymentPreservesReservesWithFreeSupplyAndOtherCarry ─────
  function testFuzz_paymentPreservesReservesWithFreeSupplyAndOtherCarry(
    uint104 owed,
    uint104 extraSupply,
    uint112 factor,
    uint128 ownRemainder,
    uint128 otherRemainder,
    uint16 ratio,
    uint256 available
  )
    external
    view
  {
    extraSupply = uint104(bound(extraSupply, 0, type(uint104).max - owed));
    factor = uint112(bound(factor, RAY, type(uint112).max));
    ownRemainder = uint128(bound(ownRemainder, 0, RAY - 1));
    otherRemainder = uint128(bound(otherRemainder, 0, RAY - 1));
    MarketState memory state;
    state.scaleFactor = factor;
    state.scaledTotalSupply = owed + extraSupply;
    state.scaledPendingWithdrawals = owed + extraSupply / 2;
    state.withdrawalRemainder = ownRemainder + otherRemainder;
    state.normalizedUnclaimedWithdrawals = 3;
    state.accruedProtocolFees = 7;
    state.reserveRatioBips = uint16(bound(ratio, 0, 10000));
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = uint128(owed) + 1;
    batch.scaledAmountBurned = 1;
    batch.normalizedAmountPaid = 1;
    batch.paymentRemainder = ownRemainder;
    (, MarketState memory afterState,,) = harness.applyPayment(batch, state, available);
    assertEq(afterState.totalDebts(), state.totalDebts(), 'all debt conserved');
    assertEq(afterState.liquidityRequired(), state.liquidityRequired(), 'all reserves conserved');
  }

  // ┌─ test_zeroAndOneUnitLiquidityPreserveCarry ─────
  function test_zeroAndOneUnitLiquidityPreserveCarry() external view {
    _checkPayment(4, uint112((5 * RAY) / 4), uint128((3 * RAY) / 4), 0);
    _checkPayment(4, uint112((5 * RAY) / 4), uint128((3 * RAY) / 4), 1);
    _checkPayment(4, uint112((5 * RAY) / 4), uint128((3 * RAY) / 4), 2);
    _checkPayment(0, uint112(RAY), uint128(RAY - 1), 0);
  }

  // ┌─ _checkPayment ─────
  function _checkPayment(uint104 owed, uint112 factor, uint128 remainder, uint256 available) private view {
    MarketState memory state;
    state.scaleFactor = factor;
    state.scaledTotalSupply = owed;
    state.scaledPendingWithdrawals = owed;
    state.withdrawalRemainder = remainder;
    state.normalizedUnclaimedWithdrawals = 1;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = uint128(owed) + 1;
    batch.scaledAmountBurned = 1;
    batch.normalizedAmountPaid = 1;
    batch.paymentRemainder = remainder;
    (WithdrawalBatch memory afterBatch, MarketState memory afterState, uint104 burned, uint128 paid) =
      harness.applyPayment(batch, state, available);
    uint256 numerator = uint256(burned) * factor + remainder;
    assertTrue(burned <= owed, 'cannot burn more than owed');
    assertTrue(paid <= available, 'cannot reserve more than available');
    assertEq(paid, numerator / RAY, 'exact carry-aware price');
    if (burned < owed) {
      assertTrue(((uint256(burned) + 1) * factor + remainder) / RAY > available, 'burn is maximal');
    }
    assertEq(afterBatch.scaledAmountBurned, uint256(burned) + 1);
    assertEq(afterBatch.normalizedAmountPaid, uint256(paid) + 1);
    assertEq(afterBatch.paymentRemainder, numerator % RAY);
    assertEq(afterState.withdrawalRemainder, numerator % RAY);
    assertEq(afterState.scaledTotalSupply, uint256(owed) - burned);
    assertEq(afterState.scaledPendingWithdrawals, uint256(owed) - burned);
    assertEq(afterState.totalDebts(), state.totalDebts(), 'payment conserves debt');
  }

  // ░░▒▒▓▓██ [ HEADROOM AND ACCOUNTING BOUNDS ] ───────────────────────────────

  // ┌─ test_globalUnclaimedHeadroomCapsPayment ─────
  function test_globalUnclaimedHeadroomCapsPayment() external view {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledTotalSupply = 10;
    state.scaledPendingWithdrawals = 10;
    state.normalizedUnclaimedWithdrawals = type(uint128).max - 7;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = 10;

    (WithdrawalBatch memory afterBatch, MarketState memory afterState, uint104 burned, uint128 paid) =
      harness.applyPayment(batch, state, type(uint256).max);

    assertEq(burned, 7, 'burn limited to global headroom');
    assertEq(paid, 7, 'payment fills global headroom');
    assertEq(afterBatch.scaledAmountBurned, 7);
    assertEq(afterBatch.normalizedAmountPaid, 7);
    assertEq(afterState.normalizedUnclaimedWithdrawals, type(uint128).max);
    assertEq(afterState.scaledPendingWithdrawals, 3);
    assertEq(afterState.totalDebts(), state.totalDebts(), 'payment conserves debt');
  }

  // ┌─ test_zeroGlobalUnclaimedHeadroomLeavesPositivePaymentUnprocessed ─────
  function test_zeroGlobalUnclaimedHeadroomLeavesPositivePaymentUnprocessed() external view {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledTotalSupply = 1;
    state.scaledPendingWithdrawals = 1;
    state.normalizedUnclaimedWithdrawals = type(uint128).max;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = 1;

    (WithdrawalBatch memory afterBatch, MarketState memory afterState, uint104 burned, uint128 paid) =
      harness.applyPayment(batch, state, 1);

    assertEq(burned, 0);
    assertEq(paid, 0);
    assertEq(afterBatch.scaledAmountBurned, 0);
    assertEq(afterBatch.normalizedAmountPaid, 0);
    assertEq(afterState.normalizedUnclaimedWithdrawals, type(uint128).max);
    assertEq(afterState.scaledPendingWithdrawals, 1);
    assertEq(afterState.totalDebts(), state.totalDebts());
  }

  // ┌─ test_cumulativePaidOverflowStillReverts ─────
  function test_cumulativePaidOverflowStillReverts() external {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledTotalSupply = 1;
    state.scaledPendingWithdrawals = 1;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = 1;
    batch.normalizedAmountPaid = type(uint128).max;
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    harness.applyPayment(batch, state, 1);
  }

  // defensive helper behavior for synthetic state outside the queue-admission invariant.
  // ┌─ test_syntheticWideCumulativeStateKeepsItsSmallLiveDifference ─────
  function test_syntheticWideCumulativeStateKeepsItsSmallLiveDifference() external view {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledTotalSupply = 7;
    state.scaledPendingWithdrawals = 7;
    state.normalizedUnclaimedWithdrawals = type(uint128).max - 7;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = type(uint128).max;
    batch.scaledAmountBurned = type(uint128).max - 7;
    batch.normalizedAmountPaid = type(uint128).max - 7;
    (WithdrawalBatch memory afterBatch, MarketState memory afterState, uint104 burned, uint128 paid) =
      harness.applyPayment(batch, state, type(uint256).max);
    assertEq(burned, 7);
    assertEq(paid, 7);
    assertEq(afterBatch.scaledAmountBurned, type(uint128).max);
    assertEq(afterBatch.normalizedAmountPaid, type(uint128).max);
    assertEq(afterState.totalDebts(), state.totalDebts());
  }

  // ┌─ test_missingAggregateContributionStillReverts ─────
  function test_missingAggregateContributionStillReverts() external {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledTotalSupply = 1;
    state.scaledPendingWithdrawals = 1;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = 1;
    batch.paymentRemainder = uint128(RAY / 2);
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    harness.applyPayment(batch, state, 1);
  }
}

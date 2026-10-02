// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketState.t
// ║  ██▀▀     ▀▀██   Supply, share conversion, and reserve-accounting tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SUPPLY AND CAPACITY
// ║  test_totalSupply(...)
// ║  test_maximumDeposit()
// ║
// ║  SHARE CONVERSION
// ║  test_normalizeAmount(...)
// ║  test_normalizeAmount(...)
// ║  test_scaleAmountDown(...)
// ║  test_maxScaledSettleableAmount_SaturatesBeforeLiquidityOverflow()
// ║  test_maxScaledSettleableAmount_IsMaximal(...)
// ║
// ║  LIABILITIES AND LIQUIDITY
// ║  test_totalDebts(...)
// ║  test_liquidityRequired(...)
// ║  test_liquidityRequired_NormalizedSupplyPartition(...)
// ║  test_liquidityRequired_HighScaleReserveRounding()
// ║  test_borrowableAssets(...)
// ║  test_withdrawableProtocolFees(...)
// ║
// ║  WITHDRAWAL STATUS
// ║  test_hasPendingExpiredBatch(...)
// ╚═════

import 'src/libraries/MathUtils.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import './wrappers/MarketStateLibExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

using MathUtils for uint256;

// coverage workaround for MarketStateLib: the external wrapper uses library-qualified calls
// (XLib.x(value)), so the mapper sees the library identifier instead of value.x().
// ┌─ MarketStateTest ──────────────────────────────────────────────────────────
contract MarketStateTest is TestKernel {
  using MarketStateLibExternal for MarketState;

  // ░░▒▒▓▓██ [ SUPPLY AND CAPACITY ] ──────────────────────────────────────────

  // ┌─ test_totalSupply ─────
  function test_totalSupply(uint112 scaleFactor, uint104 scaledTotalSupply) external pure {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;
    state.scaledTotalSupply = scaledTotalSupply;

    assertEq(state.$totalSupply(), state.$normalizeAmount(scaledTotalSupply));
  }

  // ┌─ test_maximumDeposit ─────
  function test_maximumDeposit() external pure {
    MarketState memory state;
    uint256 expected;
    assertEq(expected, state.$maximumDeposit());
  }

  // ░░▒▒▓▓██ [ SHARE CONVERSION ] ─────────────────────────────────────────────

  // ┌─ test_normalizeAmount ─────
  function test_normalizeAmount(uint256 scaledAmount, uint256 scaleFactor) external pure {
    scaledAmount = bound(scaledAmount, 0, type(uint104).max);
    scaleFactor = bound(scaleFactor, RAY, type(uint112).max);
    MarketState memory state;
    state.scaleFactor = uint112(scaleFactor);

    uint256 expected = ((scaledAmount * scaleFactor) + HALF_RAY) / RAY;
    assertEq(state.$normalizeAmount(scaledAmount), expected);
  }

  // ┌─ test_normalizeAmount ─────
  function test_normalizeAmount(uint112 scaleFactor, uint104 scaledAmount) external pure {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;

    assertEq(state.$normalizeAmount(scaledAmount), uint256(scaledAmount).rayMul(scaleFactor));
  }

  // ┌─ test_scaleAmountDown ─────
  function test_scaleAmountDown(uint256 scaleFactor, uint256 normalizedAmount) external pure {
    scaleFactor = bound(scaleFactor, RAY, type(uint112).max);
    normalizedAmount = bound(normalizedAmount, 0, type(uint128).max);
    MarketState memory state;
    state.scaleFactor = uint112(scaleFactor);
    uint256 expected = (normalizedAmount * RAY) / uint256(scaleFactor);
    uint256 actual = state.$scaleAmountDown(normalizedAmount);
    assertEq(actual, expected);
  }

  // ┌─ test_maxScaledSettleableAmount_SaturatesBeforeLiquidityOverflow ─────
  function test_maxScaledSettleableAmount_SaturatesBeforeLiquidityOverflow() external pure {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    uint256 overflowingLiquidity = type(uint256).max / RAY;

    assertEq(state.$maxScaledSettleableAmount(overflowingLiquidity), type(uint104).max);
    assertEq(state.$maxScaledSettleableAmount(type(uint104).max - 1), type(uint104).max - 1);
  }

  // ┌─ test_maxScaledSettleableAmount_IsMaximal ─────
  function test_maxScaledSettleableAmount_IsMaximal(uint112 scaleFactor, uint256 availableLiquidity) external pure {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;

    uint256 scaledAmount = state.$maxScaledSettleableAmount(availableLiquidity);
    uint256 maxScaledAmount = type(uint104).max;

    assertTrue(scaledAmount <= maxScaledAmount, 'uint104 cap');
    assertTrue(MathUtils.mulDiv(scaledAmount, scaleFactor, RAY) <= availableLiquidity, 'returned amount fits liquidity');

    if (scaledAmount < maxScaledAmount) {
      assertTrue(
        MathUtils.mulDiv(scaledAmount + 1, scaleFactor, RAY) > availableLiquidity, 'next scaled unit does not fit'
      );
    }
  }

  // ░░▒▒▓▓██ [ LIABILITIES AND LIQUIDITY ] ────────────────────────────────────

  // ┌─ test_totalDebts ─────
  function test_totalDebts(
    uint112 scaleFactor,
    uint104 scaledTotalSupply,
    uint128 normalizedUnclaimedWithdrawals,
    uint128 accruedProtocolFees
  )
    external
    pure
  {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;
    state.scaledTotalSupply = scaledTotalSupply;
    state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;
    state.accruedProtocolFees = accruedProtocolFees;

    uint256 expected = ((uint256(scaledTotalSupply) * scaleFactor + HALF_RAY) / RAY) + normalizedUnclaimedWithdrawals
      + accruedProtocolFees;
    assertEq(state.$totalDebts(), expected);
  }

  // ┌─ test_liquidityRequired ─────
  function test_liquidityRequired(
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 reserveRatioBips,
    uint128 accruedProtocolFees,
    uint128 normalizedUnclaimedWithdrawals
  )
    external
    pure
  {
    reserveRatioBips = uint16(bound(reserveRatioBips, 0, BIP));
    scaledPendingWithdrawals = uint104(bound(scaledPendingWithdrawals, 0, scaledTotalSupply));

    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledPendingWithdrawals = scaledPendingWithdrawals;
    state.scaledTotalSupply = scaledTotalSupply;
    state.reserveRatioBips = reserveRatioBips;
    state.accruedProtocolFees = accruedProtocolFees;
    state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;

    uint256 normalizedPendingWithdrawals = state.$normalizeAmount(scaledPendingWithdrawals);
    uint256 normalizedOutstandingSupply = state.$totalSupply() - normalizedPendingWithdrawals;

    assertEq(
      state.$liquidityRequired(),
      normalizedPendingWithdrawals + normalizedOutstandingSupply.bipMul(reserveRatioBips)
        + state.normalizedUnclaimedWithdrawals + uint256(accruedProtocolFees)
    );
  }

  // ┌─ test_liquidityRequired_NormalizedSupplyPartition ─────
  function test_liquidityRequired_NormalizedSupplyPartition(
    uint112 scaleFactor,
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 reserveRatioBips,
    uint128 accruedProtocolFees,
    uint128 normalizedUnclaimedWithdrawals
  )
    external
    pure
  {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    scaledPendingWithdrawals = uint104(bound(scaledPendingWithdrawals, 0, scaledTotalSupply));
    reserveRatioBips = uint16(bound(reserveRatioBips, 0, BIP));

    MarketState memory state;
    state.scaleFactor = scaleFactor;
    state.scaledPendingWithdrawals = scaledPendingWithdrawals;
    state.scaledTotalSupply = scaledTotalSupply;
    state.reserveRatioBips = reserveRatioBips;
    state.accruedProtocolFees = accruedProtocolFees;
    state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;

    uint256 normalizedPendingWithdrawals = state.$normalizeAmount(scaledPendingWithdrawals);
    uint256 normalizedTotalSupply = state.$totalSupply();
    uint256 normalizedOutstandingSupply = normalizedTotalSupply - normalizedPendingWithdrawals;
    uint256 otherDebts = uint256(accruedProtocolFees) + normalizedUnclaimedWithdrawals;

    assertEq(
      state.$liquidityRequired(),
      normalizedPendingWithdrawals + normalizedOutstandingSupply.bipMul(reserveRatioBips) + otherDebts,
      'normalized partition'
    );

    state.reserveRatioBips = 0;
    assertEq(state.$liquidityRequired(), normalizedPendingWithdrawals + otherDebts, 'zero reserve ratio');

    state.reserveRatioBips = uint16(BIP);
    assertEq(state.$liquidityRequired(), state.$totalDebts(), 'full reserve ratio');
  }

  // ┌─ test_liquidityRequired_HighScaleReserveRounding ─────
  function test_liquidityRequired_HighScaleReserveRounding() external pure {
    MarketState memory state;
    state.scaleFactor = uint112((1 << 22) * RAY);
    state.scaledTotalSupply = 1;
    state.reserveRatioBips = 4_999;

    assertEq(state.$liquidityRequired(), 2_096_733, '4,999 bip reserve');
    assertEq(state.$borrowableAssets(2_096_733), 0, 'reserved assets are not borrowable');
    assertEq(state.$borrowableAssets(2_096_734), 1, 'assets above the reserve are borrowable');

    state.reserveRatioBips = 5_000;
    assertEq(state.$liquidityRequired(), 2_097_152, '5,000 bip reserve');

    state.reserveRatioBips = 10_000;
    assertEq(state.$liquidityRequired(), state.$totalDebts(), 'full reserve recombines');
  }

  // ┌─ test_borrowableAssets ─────
  function test_borrowableAssets(
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 reserveRatioBips,
    uint128 accruedProtocolFees,
    uint128 normalizedUnclaimedWithdrawals,
    uint128 totalAssets
  )
    external
    pure
  {
    reserveRatioBips = uint16(bound(reserveRatioBips, 0, BIP));
    scaledPendingWithdrawals = uint104(bound(scaledPendingWithdrawals, 0, scaledTotalSupply));

    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledPendingWithdrawals = scaledPendingWithdrawals;
    state.scaledTotalSupply = scaledTotalSupply;
    state.reserveRatioBips = reserveRatioBips;
    state.accruedProtocolFees = accruedProtocolFees;
    state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;

    uint256 normalizedPendingWithdrawals = state.$normalizeAmount(scaledPendingWithdrawals);
    uint256 normalizedOutstandingSupply = state.$totalSupply() - normalizedPendingWithdrawals;

    assertEq(
      state.$liquidityRequired(),
      normalizedPendingWithdrawals + normalizedOutstandingSupply.bipMul(reserveRatioBips)
        + state.normalizedUnclaimedWithdrawals + uint256(accruedProtocolFees)
    );
    assertEq(
      state.$borrowableAssets(totalAssets),
      totalAssets < state.$liquidityRequired() ? 0 : totalAssets - state.$liquidityRequired()
    );
  }

  // ┌─ test_withdrawableProtocolFees ─────
  function test_withdrawableProtocolFees(
    uint256 accruedProtocolFees,
    uint256 normalizedUnclaimedWithdrawals,
    uint256 totalAssets
  )
    external
    pure
  {
    accruedProtocolFees = bound(accruedProtocolFees, 0, type(uint128).max);
    normalizedUnclaimedWithdrawals = bound(normalizedUnclaimedWithdrawals, 0, type(uint128).max);
    totalAssets = bound(totalAssets, 0, type(uint128).max);
    MarketState memory state;
    state.accruedProtocolFees = uint128(accruedProtocolFees);
    state.normalizedUnclaimedWithdrawals = uint128(normalizedUnclaimedWithdrawals);
    uint256 availableAssets =
      totalAssets < normalizedUnclaimedWithdrawals ? 0 : totalAssets - normalizedUnclaimedWithdrawals;
    uint256 expectedWithdrawable = accruedProtocolFees > availableAssets ? availableAssets : accruedProtocolFees;

    assertEq(state.$withdrawableProtocolFees(totalAssets), expectedWithdrawable);
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL STATUS ] ────────────────────────────────────────────

  // ┌─ test_hasPendingExpiredBatch ─────
  function test_hasPendingExpiredBatch(uint32 pendingWithdrawalExpiry, uint32 timestamp) external {
    vm.warp(timestamp);
    MarketState memory state;
    state.pendingWithdrawalExpiry = pendingWithdrawalExpiry;

    assertEq(state.$hasPendingExpiredBatch(), pendingWithdrawalExpiry > 0 && pendingWithdrawalExpiry < timestamp);
  }
}

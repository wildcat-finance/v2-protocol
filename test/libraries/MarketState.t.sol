// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'src/libraries/MathUtils.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import './wrappers/MarketStateLibExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

using MathUtils for uint256;

// Uses an external wrapper library to make forge coverage work for MarketStateLib.
// Forge is currently incapable of mapping MemberAccess function calls with
// expressions other than library identifiers (e.g. value.x() vs XLib.x(value))
// to the correct FunctionDefinition nodes.
contract MarketStateTest is TestKernel {
  using MarketStateLibExternal for MarketState;

  function test_scaleAmountDown(uint256 scaleFactor, uint256 normalizedAmount) external pure {
    scaleFactor = bound(scaleFactor, RAY, type(uint112).max);
    normalizedAmount = bound(normalizedAmount, 0, type(uint128).max);
    MarketState memory state;
    state.scaleFactor = uint112(scaleFactor);
    uint256 expected = (normalizedAmount * RAY) / uint256(scaleFactor);
    uint256 actual = state.$scaleAmountDown(normalizedAmount);
    assertEq(actual, expected);
  }

  function test_normalizeAmount(uint256 scaledAmount, uint256 scaleFactor) external pure {
    scaledAmount = bound(scaledAmount, 0, type(uint104).max);
    scaleFactor = bound(scaleFactor, RAY, type(uint112).max);
    MarketState memory state;
    state.scaleFactor = uint112(scaleFactor);

    uint256 expected = ((scaledAmount * scaleFactor) + HALF_RAY) / RAY;
    assertEq(state.$normalizeAmount(scaledAmount), expected);
  }

  function test_normalizeAmount(uint112 scaleFactor, uint104 scaledAmount) external pure {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;

    assertEq(state.$normalizeAmount(scaledAmount), uint256(scaledAmount).rayMul(scaleFactor));
  }

  function test_maxScaledSettleableAmount_SaturatesBeforeLiquidityOverflow() external pure {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    uint256 overflowingLiquidity = type(uint256).max / RAY;

    assertEq(state.$maxScaledSettleableAmount(overflowingLiquidity), type(uint104).max);
    assertEq(state.$maxScaledSettleableAmount(type(uint104).max - 1), type(uint104).max - 1);
  }

  function test_totalSupply(uint112 scaleFactor, uint104 scaledTotalSupply) external pure {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;
    state.scaledTotalSupply = scaledTotalSupply;

    assertEq(state.$totalSupply(), state.$normalizeAmount(scaledTotalSupply));
  }

  function test_maximumDeposit() external pure {
    MarketState memory state;
    uint256 expected;
    assertEq(expected, state.$maximumDeposit());
  }

  function test_liquidityRequired(
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 reserveRatioBips,
    uint128 accruedProtocolFees,
    uint128 normalizedUnclaimedWithdrawals
  ) external pure {
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
      normalizedPendingWithdrawals +
        normalizedOutstandingSupply.bipMul(reserveRatioBips) +
        state.normalizedUnclaimedWithdrawals +
        uint256(accruedProtocolFees)
    );
  }

  function test_liquidityRequired_NormalizedSupplyPartition(
    uint112 scaleFactor,
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 reserveRatioBips,
    uint128 accruedProtocolFees,
    uint128 normalizedUnclaimedWithdrawals
  ) external pure {
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
      normalizedPendingWithdrawals +
        normalizedOutstandingSupply.bipMul(reserveRatioBips) +
        otherDebts,
      'normalized partition'
    );

    state.reserveRatioBips = 0;
    assertEq(
      state.$liquidityRequired(),
      normalizedPendingWithdrawals + otherDebts,
      'zero reserve ratio'
    );

    state.reserveRatioBips = uint16(BIP);
    assertEq(state.$liquidityRequired(), state.$totalDebts(), 'full reserve ratio');
  }

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

  function test_hasPendingExpiredBatch(uint32 pendingWithdrawalExpiry, uint32 timestamp) external {
    vm.warp(timestamp);
    MarketState memory state;
    state.pendingWithdrawalExpiry = pendingWithdrawalExpiry;

    assertEq(
      state.$hasPendingExpiredBatch(),
      pendingWithdrawalExpiry > 0 && pendingWithdrawalExpiry < timestamp
    );
  }

  function test_borrowableAssets(
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 reserveRatioBips,
    uint128 accruedProtocolFees,
    uint128 normalizedUnclaimedWithdrawals,
    uint128 totalAssets
  ) external pure {
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
      normalizedPendingWithdrawals +
        normalizedOutstandingSupply.bipMul(reserveRatioBips) +
        state.normalizedUnclaimedWithdrawals +
        uint256(accruedProtocolFees)
    );
    assertEq(
      state.$borrowableAssets(totalAssets),
      totalAssets < state.$liquidityRequired() ? 0 : totalAssets - state.$liquidityRequired()
    );
  }

  function test_withdrawableProtocolFees(
    uint256 accruedProtocolFees,
    uint256 normalizedUnclaimedWithdrawals,
    uint256 totalAssets
  ) external pure {
    accruedProtocolFees = bound(accruedProtocolFees, 0, type(uint128).max);
    normalizedUnclaimedWithdrawals = bound(normalizedUnclaimedWithdrawals, 0, type(uint128).max);
    totalAssets = bound(totalAssets, 0, type(uint128).max);
    MarketState memory state;
    state.accruedProtocolFees = uint128(accruedProtocolFees);
    state.normalizedUnclaimedWithdrawals = uint128(normalizedUnclaimedWithdrawals);
    uint256 availableAssets = totalAssets < normalizedUnclaimedWithdrawals
      ? 0
      : totalAssets - normalizedUnclaimedWithdrawals;
    uint256 expectedWithdrawable = accruedProtocolFees > availableAssets
      ? availableAssets
      : accruedProtocolFees;

    assertEq(state.$withdrawableProtocolFees(totalAssets), expectedWithdrawable);
  }

  function test_totalDebts(
    uint112 scaleFactor,
    uint104 scaledTotalSupply,
    uint128 normalizedUnclaimedWithdrawals,
    uint128 accruedProtocolFees
  ) external pure {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    MarketState memory state;
    state.scaleFactor = scaleFactor;
    state.scaledTotalSupply = scaledTotalSupply;
    state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;
    state.accruedProtocolFees = accruedProtocolFees;

    uint256 expected = ((uint256(scaledTotalSupply) * scaleFactor + HALF_RAY) / RAY) +
      normalizedUnclaimedWithdrawals +
      accruedProtocolFees;
    assertEq(state.$totalDebts(), expected);
  }
}

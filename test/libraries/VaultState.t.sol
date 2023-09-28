// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/libraries/Withdrawal.sol';
import 'src/libraries/MathUtils.sol';
import './wrappers/VaultStateLibExternal.sol';

using MathUtils for uint256;

// Uses an external wrapper library to make forge coverage work for VaultStateLib.
// Forge is currently incapable of mapping MemberAccess function calls with
// expressions other than library identifiers (e.g. value.x() vs XLib.x(value))
// to the correct FunctionDefinition nodes.
contract VaultStateTest is Test {
  WithdrawalData internal _withdrawalData;

  using VaultStateLibExternal for VaultState;

  function test_scaleAmount(uint128 normalizedAmount) external returns (uint256) {
    VaultState memory state;
    state.scaleFactor = uint112(RAY);

    assertEq(state.$scaleAmount(normalizedAmount), normalizedAmount);
  }

  function test_scaleAmount(
    uint256 scaleFactor,
    uint256 normalizedAmount
  ) external returns (uint256) {
    scaleFactor = bound(scaleFactor, RAY, type(uint112).max);
    normalizedAmount = bound(normalizedAmount, 0, type(uint128).max);
    VaultState memory state;
    state.scaleFactor = uint112(scaleFactor);
    uint256 expected = ((normalizedAmount * RAY) + (scaleFactor / 2)) / uint256(scaleFactor);
    uint256 actual = state.$scaleAmount(normalizedAmount);
    assertEq(actual, expected);
  }

  function test_normalizeAmount(uint256 scaledAmount, uint256 scaleFactor) external {
    scaledAmount = bound(scaledAmount, 0, type(uint104).max);
    scaleFactor = bound(scaleFactor, RAY, type(uint112).max);
    VaultState memory state;
    state.scaleFactor = uint112(scaleFactor);

    uint256 expected = ((scaledAmount * scaleFactor) + HALF_RAY) / RAY;
    assertEq(state.$normalizeAmount(scaledAmount), expected);
  }

  function test_normalizeAmount(
    uint112 scaleFactor,
    uint104 scaledAmount
  ) external returns (uint256) {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    VaultState memory state;
    state.scaleFactor = scaleFactor;

    assertEq(state.$normalizeAmount(scaledAmount), uint256(scaledAmount).rayMul(scaleFactor));
  }

  function test_totalSupply(
    uint112 scaleFactor,
    uint104 scaledTotalSupply
  ) external returns (uint256) {
    scaleFactor = uint112(bound(scaleFactor, RAY, type(uint112).max));
    VaultState memory state;
    state.scaleFactor = scaleFactor;
    state.scaledTotalSupply = scaledTotalSupply;

    assertEq(state.$totalSupply(), state.$normalizeAmount(scaledTotalSupply));
  }

  function test_maximumDeposit() external returns (uint256) {
    VaultState memory state;
    uint256 expected;
    assertEq(expected, state.$maximumDeposit());
  }

  function test_liquidityRequired(
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 liquidityCoverageRatio,
    uint128 accruedProtocolFees,
    uint128 reservedAssets
  ) external {
    liquidityCoverageRatio = uint16(bound(liquidityCoverageRatio, 1, 10000));
    scaledPendingWithdrawals = uint104(bound(scaledPendingWithdrawals, 0, scaledTotalSupply));

    VaultState memory state;
    state.scaledPendingWithdrawals = scaledPendingWithdrawals;
    state.scaledTotalSupply = scaledTotalSupply;
    state.liquidityCoverageRatio = liquidityCoverageRatio;
    state.accruedProtocolFees = accruedProtocolFees;
    state.reservedAssets = reservedAssets;

    uint256 scaledCoverageLiquidity = (uint256(scaledTotalSupply - scaledPendingWithdrawals) *
      uint256(liquidityCoverageRatio)) / uint256(10000);
    uint256 collateralForOutstanding = state.$normalizeAmount(
      scaledCoverageLiquidity + scaledPendingWithdrawals
    );

    assertEq(
      state.$liquidityRequired(),
      collateralForOutstanding + state.reservedAssets + uint256(accruedProtocolFees)
    );
  }

  function test_hasPendingExpiredBatch(uint32 pendingWithdrawalExpiry, uint32 timestamp) external {
    vm.warp(timestamp);
    VaultState memory state;
    state.pendingWithdrawalExpiry = pendingWithdrawalExpiry;

    assertEq(
      state.$hasPendingExpiredBatch(),
      pendingWithdrawalExpiry > 0 && pendingWithdrawalExpiry <= timestamp
    );
  }

  function test_borrowableAssets(
    uint104 scaledPendingWithdrawals,
    uint104 scaledTotalSupply,
    uint16 liquidityCoverageRatio,
    uint128 accruedProtocolFees,
    uint128 reservedAssets,
    uint128 totalAssets
  ) external {
    liquidityCoverageRatio = uint16(bound(liquidityCoverageRatio, 1, 10000));
    scaledPendingWithdrawals = uint104(bound(scaledPendingWithdrawals, 0, scaledTotalSupply));

    VaultState memory state;
    state.scaledPendingWithdrawals = scaledPendingWithdrawals;
    state.scaledTotalSupply = scaledTotalSupply;
    state.liquidityCoverageRatio = liquidityCoverageRatio;
    state.accruedProtocolFees = accruedProtocolFees;
    state.reservedAssets = reservedAssets;

    uint256 scaledCoverageLiquidity = (uint256(scaledTotalSupply - scaledPendingWithdrawals) *
      uint256(liquidityCoverageRatio)) / uint256(10000);
    uint256 collateralForOutstanding = state.$normalizeAmount(
      scaledCoverageLiquidity + scaledPendingWithdrawals
    );

    assertEq(
      state.$liquidityRequired(),
      collateralForOutstanding + state.reservedAssets + uint256(accruedProtocolFees)
    );
    assertEq(
      state.$borrowableAssets(totalAssets),
      totalAssets < state.$liquidityRequired() ? 0 : totalAssets - state.$liquidityRequired()
    );
  }

  function test_withdrawableProtocolFees(
    uint256 accruedProtocolFees,
    uint256 reservedAssets,
    uint256 totalAssets
  ) external {
    accruedProtocolFees = bound(accruedProtocolFees, 0, type(uint128).max);
    reservedAssets = bound(reservedAssets, 0, type(uint128).max);
    totalAssets = bound(totalAssets, reservedAssets, type(uint128).max);
    VaultState memory state;
    state.accruedProtocolFees = uint128(accruedProtocolFees);
    state.reservedAssets = uint128(reservedAssets);
    uint256 availableAssets = totalAssets - reservedAssets;
    uint256 expectedWithdrawable = accruedProtocolFees > availableAssets
      ? availableAssets
      : accruedProtocolFees;

    assertEq(state.$withdrawableProtocolFees(totalAssets), expectedWithdrawable);
  }
}

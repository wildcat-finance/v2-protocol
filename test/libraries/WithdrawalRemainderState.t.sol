// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY, HALF_RAY, BIP, HALF_BIP } from 'src/libraries/MathUtils.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract WithdrawalRemainderStateTest is TestKernel {
  function test_carryPartitionCannotExceedFullyReservedDebt() external pure {
    MarketState memory s;
    s.scaledTotalSupply = 2;
    s.scaledPendingWithdrawals = 1;
    s.scaleFactor = uint112((5 * RAY) / 4);
    s.withdrawalRemainder = uint128(RAY / 4);
    s.normalizedUnclaimedWithdrawals = 1;
    s.reserveRatioBips = 9999;
    assertEq(s.liquidityRequired(), 4);
    s.reserveRatioBips = 10000;
    assertEq(s.liquidityRequired(), 4);
    assertEq(s.totalDebts(), 4);
  }

  function testFuzz_reservesRemainMonotonicAndBounded(
    uint104 supply,
    uint104 pending,
    uint112 factor,
    uint128 remainder,
    uint16 ratio
  ) external pure {
    MarketState memory s;
    s.scaledTotalSupply = supply;
    s.scaledPendingWithdrawals = uint104(bound(pending, 0, supply));
    s.scaleFactor = uint112(bound(factor, RAY, type(uint112).max));
    s.withdrawalRemainder = remainder;
    s.reserveRatioBips = uint16(bound(ratio, 0, 9999));
    uint256 required = s.liquidityRequired();
    ++s.reserveRatioBips;
    assertTrue(s.liquidityRequired() >= required, 'raising reserves never lowers coverage');
    assertTrue(s.liquidityRequired() <= s.totalDebts(), 'coverage cannot exceed all debt');
    s.reserveRatioBips = 10000;
    assertEq(s.liquidityRequired(), s.totalDebts());
  }

  function testFuzz_unifiedPartitionMatchesOriginalEndpointsAndIntermediateRatios(
    uint104 supply,
    uint104 pending,
    uint112 factor,
    uint128 remainder,
    uint16 ratio,
    uint128 fees,
    uint128 unclaimed
  ) external pure {
    MarketState memory s;
    s.scaledTotalSupply = supply;
    s.scaledPendingWithdrawals = uint104(bound(pending, 0, supply));
    s.scaleFactor = uint112(bound(factor, RAY, type(uint112).max));
    s.withdrawalRemainder = remainder;
    s.reserveRatioBips = ratio;
    s.accruedProtocolFees = fees;
    s.normalizedUnclaimedWithdrawals = unclaimed;
    uint256 total = (uint256(supply) * s.scaleFactor + remainder + HALF_RAY) / RAY;
    uint256 withdrawalValue = (uint256(s.scaledPendingWithdrawals) *
      s.scaleFactor +
      remainder +
      HALF_RAY) / RAY;
    uint256 original;
    if (ratio == 0) original = withdrawalValue;
    else if (ratio == BIP) original = total;
    else original = withdrawalValue + ((total - withdrawalValue) * ratio + HALF_BIP) / BIP;
    assertEq(s.liquidityRequired(), original + fees + unclaimed);
  }
}

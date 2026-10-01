// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'src/libraries/MarketState.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract BoundedMarketStateTest is TestKernel {
  using MathUtils for uint256;

  /// @dev independent checked formulas. The unified partition now checks normalized
  ///      pending <= supply at every reserve ratio, including 0% and 100%.
  function referenceValues(MarketState memory state)
    external
    pure
    returns (uint256 supply, uint256 liquidity, uint256 debts)
  {
    supply = uint256(state.scaledTotalSupply).rayMul(state.scaleFactor);
    uint256 pending = uint256(state.scaledPendingWithdrawals).rayMul(state.scaleFactor);
    uint256 outstanding = supply - pending;
    if (state.reserveRatioBips == 0) {
      liquidity = pending;
    } else if (state.reserveRatioBips == BIP) {
      liquidity = supply;
    } else {
      liquidity = pending + outstanding.bipMul(state.reserveRatioBips);
    }
    liquidity += state.accruedProtocolFees + uint256(state.normalizedUnclaimedWithdrawals);
    debts = supply + state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees;
  }

  function candidateValues(MarketState memory state) external pure returns (uint256, uint256, uint256) {
    return (state.totalSupply(), state.liquidityRequired(), state.totalDebts());
  }

  function _compare(MarketState memory state) internal view {
    (bool expectedSuccess, bytes memory expectedData) =
      address(this).staticcall(abi.encodeCall(this.referenceValues, (state)));
    (bool actualSuccess, bytes memory actualData) =
      address(this).staticcall(abi.encodeCall(this.candidateValues, (state)));
    assertEq(actualSuccess, expectedSuccess);
    assertEq(actualData, expectedData);
  }

  function testFuzz_liabilitiesMatchCheckedFormulas(
    uint104 supply,
    uint104 pending,
    uint112 scale,
    uint16 reserve,
    uint128 fees,
    uint128 unclaimed
  )
    external
    view
  {
    MarketState memory state;
    state.scaledTotalSupply = supply;
    state.scaledPendingWithdrawals = pending;
    state.scaleFactor = scale;
    state.reserveRatioBips = reserve;
    state.accruedProtocolFees = fees;
    state.normalizedUnclaimedWithdrawals = unclaimed;
    _compare(state);
  }

  function test_liabilitiesAtEveryFieldMaximumAndReserveEdges() external view {
    MarketState memory state;
    state.scaledTotalSupply = type(uint104).max;
    state.scaleFactor = type(uint112).max;
    state.accruedProtocolFees = type(uint128).max;
    state.normalizedUnclaimedWithdrawals = type(uint128).max;
    uint16[6] memory reserves = [uint16(0), 1, 9999, 10000, 10001, type(uint16).max];
    for (uint256 i; i < reserves.length; ++i) {
      state.reserveRatioBips = reserves[i];
      state.scaledPendingWithdrawals = 0;
      _compare(state);
      state.scaledPendingWithdrawals = type(uint104).max;
      _compare(state);
    }
    state.scaleFactor = 0;
    _compare(state);
  }

  function test_invalidPendingSupplyKeepsArithmeticPanic() external {
    MarketState memory state;
    state.scaledTotalSupply = 1;
    state.scaledPendingWithdrawals = 2;
    state.scaleFactor = uint112(RAY);
    uint16[3] memory reserves = [uint16(0), 5000, 10000];
    for (uint256 i; i < reserves.length; ++i) {
      state.reserveRatioBips = reserves[i];
      _compare(state);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      this.candidateValues(state);
    }
  }
}

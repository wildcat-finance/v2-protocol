// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { FeeMath } from 'src/libraries/FeeMath.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY, BIP } from 'src/libraries/MathUtils.sol';
import { FeeMathExternal } from '../libraries/wrappers/FeeMathExternal.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

/// Characterization of the existing fee model, not a proposed production fix.
contract ProtocolFeeRoundingReviewTest is MarketFixture {
  using FeeMathExternal for MarketState;
  address internal constant Lender = address(0x1EAD);
  address internal constant Checkpointer = address(0xC0FFEE);
  uint256 internal constant DayBaseRay = uint256(1e26) / 365;
  uint256 internal constant ExactDenominator = RAY * RAY * BIP;

  event MeasuredFees(uint256 supply, uint256 observed, uint256 samePathRoundedReference);

  function _fixture(uint256 kind, uint16 feeBips) private returns (Fixture memory f) {
    Options memory o = _defaultOptions(HooksKind(kind % 2));
    o.revolving = kind >= 2;
    // Both model types have a 10% base rate. Revolving uses only commitment
    // interest here, avoiding changes in utilization as its scale factor grows.
    o.annualInterestBips = o.revolving ? 0 : 1000;
    o.commitmentFeeBips = o.revolving ? 1000 : 0;
    o.protocolFeeBips = feeBips;
    o.delinquencyFeeBips = 0;
    o.reserveRatioBips = 0;
    f = _newMarket(o);
  }

  function _runDaily(uint256 kind, uint104 amount) private returns (Fixture memory f, uint256 exactNumerator) {
    f = _fixture(kind, 1000);
    Fixture memory control = _fixture(kind, 0);
    _deposit(f, Lender, amount);
    _deposit(control, Lender, amount);
    uint256 start = vm.getBlockTimestamp();
    for (uint256 i = 1; i <= 365; ++i) {
      MarketState memory beforeState = f.market.previousState();
      // Independent rational fee before the two intermediate ray roundings.
      // These small fixtures keep this complete product far below uint256.
      exactNumerator += uint256(amount) * beforeState.scaleFactor * DayBaseRay * 1000;
      vm.warp(start + i * 1 days);
      vm.prank(Checkpointer);
      f.market.updateState();
      vm.prank(Checkpointer);
      control.market.updateState();
      assertEq(
        f.market.previousState().scaleFactor,
        control.market.previousState().scaleFactor,
        'fee rounding does not change lender-interest path'
      );
      assertEq(f.market.previousState().scaledTotalSupply, amount);
    }
  }

  function test_dailyCheckpoints_SubUnitFeesDisappear_AcrossMarketAndHookKinds() external {
    for (uint256 kind; kind < 4; ++kind) {
      (Fixture memory f, uint256 sum) = _runDaily(kind, 1000);
      uint256 expected = (sum + ExactDenominator / 2) / ExactDenominator;
      emit MeasuredFees(1000, f.market.previousState().accruedProtocolFees, expected);
      assertEq(expected, 11, 'round the same-path accumulated fraction once');
      assertEq(f.market.previousState().accruedProtocolFees, 0, 'daily fee rounded away');
      vm.expectRevert(bytes4(keccak256('NullFeeAmount()')));
      f.market.collectFees();
    }
  }

  function test_dailyCheckpoints_NearestRoundingCanOvercharge_AcrossMarketAndHookKinds() external {
    for (uint256 kind; kind < 4; ++kind) {
      (Fixture memory f, uint256 sum) = _runDaily(kind, 20_000);
      uint256 expected = (sum + ExactDenominator / 2) / ExactDenominator;
      emit MeasuredFees(20_000, f.market.previousState().accruedProtocolFees, expected);
      assertEq(expected, 210, 'same daily compounding path, round once');
      assertEq(f.market.previousState().accruedProtocolFees, 365, 'one unit charged per day');
      uint256 factor = f.market.previousState().scaleFactor;
      vm.prank(Checkpointer);
      f.market.updateState();
      assertEq(f.market.previousState().accruedProtocolFees, 365, 'same timestamp accrues nothing');
      f.market.collectFees();
      assertEq(f.asset.balanceOf(FeeRecipient), 365, 'whole rounded fees are actually collectible');
      assertEq(f.market.previousState().accruedProtocolFees, 0);
      assertEq(f.market.previousState().scaleFactor, factor, 'collection preserves factor');
    }
  }

  function test_intermediateFeeRateRounding_CanExceedHalfAnAtomicUnit() external pure {
    MarketState memory state;
    state.scaleFactor = uint112(RAY);
    state.scaledTotalSupply = type(uint104).max;
    state.protocolFeeBips = 1000;
    uint256 baseRay = FeeMath.calculateLinearInterestFromBips(1, 12);
    uint256 expectedNumerator = uint256(state.scaledTotalSupply) * baseRay * 1000;
    uint256 denominator = RAY * BIP;
    uint256 expected = (expectedNumerator + denominator / 2) / denominator;
    (, uint256 observed) = state.$applyProtocolFee(baseRay);
    assertTrue(expected > observed + 6000, 'rounding fee rate in ray amplifies with supply');
  }
}

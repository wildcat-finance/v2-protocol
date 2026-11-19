// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // FeeMath.t
//  \ ^ /   Accrual, protocol fee, and delinquency boundary tests.
//    V
//
//  ACCRUAL
//  test_updateScaleFactorAndFees_WithFees()
//  test_updateScaleFactorAndFees_WithoutFeesWithPenalties()
//  test_updateScaleFactorAndFees_WithFeesAndPenalties()
//  test_updateScaleFactorAndFees_WithoutFeesOrPenalties()
//  test_updateScaleFactorAndFees_ZeroDelinquencyFeeAccumulatesTime()
//  test_updateScaleFactorAndFees_ZeroDelinquencyFeeDecaysTime()
//  test_updateScaleFactorAndFees_AcceptedUint112LimitReverts()
//  test_updateScaleFactorAndFees_Uint112MaxStableAtZeroRate()
//  test_updateScaleFactorAndFees_NoTimeDelta(...)
//
//  DELINQUENCY
//  test_updateTimeDelinquentAndGetPenaltyTime(...)
//  testUpdateTimeDelinquentAndGetPenaltyTime()
// ═════

import { FeeMath, MathUtils, MarketState } from 'src/libraries/FeeMath.sol';
import { RAY } from 'src/libraries/MathUtils.sol';
import './wrappers/FeeMathExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// coverage workaround for FeeMath: the external wrapper uses library-qualified calls
// (XLib.x(value)), so the mapper sees the library identifier instead of value.x().
// ┌─ FeeMathTest ──────────────────────────────────────────────────────────────
contract FeeMathTest is TestKernel {
  using MathUtils for uint256;
  using FeeMathExternal for MarketState;

  // ░░▒▒▓▓██ [ ACCRUAL ] ──────────────────────────────────────────────────────

  // ┌─ test_updateScaleFactorAndFees_WithFees ─────
  function test_updateScaleFactorAndFees_WithFees() external {
    MarketState memory state;
    state.protocolFeeBips = 1000;
    state.timeDelinquent = 1000;
    state.isDelinquent = true;
    uint256 delinquencyGracePeriod = 0;
    state.annualInterestBips = 1000;
    state.scaledTotalSupply = uint104(uint256(1e18).rayDiv(RAY));
    vm.warp(365 days);
    state.scaleFactor = uint112(RAY);
    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(0, delinquencyGracePeriod, vm.getBlockTimestamp());

    assertEq(state.lastInterestAccruedTimestamp, vm.getBlockTimestamp());
    assertEq(protocolFee, 1e16, 'incorrect protocolFee');
    assertEq(state.scaleFactor, 1.1e27, 'incorrect scaleFactor');
    assertEq(baseInterestRay, 1e26, 'incorrect baseInterestRay');
    assertEq(delinquencyFeeRay, 0, 'incorrect delinquencyFeeRay');
  }

  // ┌─ test_updateScaleFactorAndFees_WithoutFeesWithPenalties ─────
  function test_updateScaleFactorAndFees_WithoutFeesWithPenalties() external {
    MarketState memory state;
    state.timeDelinquent = 1000;
    state.isDelinquent = true;
    uint256 delinquencyGracePeriod = 0;
    state.annualInterestBips = 1000;
    state.scaledTotalSupply = uint104(uint256(1e18).rayDiv(RAY));
    vm.warp(365 days);
    state.scaleFactor = uint112(RAY);
    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(1000, delinquencyGracePeriod, vm.getBlockTimestamp());

    assertEq(state.lastInterestAccruedTimestamp, vm.getBlockTimestamp());
    assertEq(protocolFee, 0, 'incorrect protocolFee');
    assertEq(state.scaleFactor, 1.2e27, 'incorrect scaleFactor');
    assertEq(baseInterestRay, 1e26, 'incorrect baseInterestRay');
    assertEq(delinquencyFeeRay, 1e26, 'incorrect delinquencyFeeRay');
  }

  // ┌─ test_updateScaleFactorAndFees_WithFeesAndPenalties ─────
  function test_updateScaleFactorAndFees_WithFeesAndPenalties() external {
    MarketState memory state;
    state.protocolFeeBips = 1000;
    state.timeDelinquent = 1000;
    state.isDelinquent = true;
    uint256 delinquencyGracePeriod = 0;
    state.annualInterestBips = 1000;
    state.scaledTotalSupply = uint104(uint256(1e18).rayDiv(RAY));
    vm.warp(365 days);
    state.scaleFactor = uint112(RAY);
    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(1000, delinquencyGracePeriod, vm.getBlockTimestamp());
    assertEq(state.lastInterestAccruedTimestamp, vm.getBlockTimestamp());

    assertEq(protocolFee, 1e16, 'incorrect feesAccrued');
    assertEq(state.scaleFactor, 1.2e27, 'incorrect scaleFactor');
    assertEq(baseInterestRay, 1e26, 'incorrect baseInterestRay');
    assertEq(delinquencyFeeRay, 1e26, 'incorrect delinquencyFeeRay');
  }

  // ┌─ test_updateScaleFactorAndFees_WithoutFeesOrPenalties ─────
  function test_updateScaleFactorAndFees_WithoutFeesOrPenalties() external {
    MarketState memory state;
    state.timeDelinquent = 1000;
    state.isDelinquent = true;
    uint256 delinquencyGracePeriod = 0;
    state.annualInterestBips = 1000;
    state.scaledTotalSupply = uint104(uint256(1e18).rayDiv(RAY));
    vm.warp(365 days);
    state.scaleFactor = uint112(RAY);
    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(0, delinquencyGracePeriod, vm.getBlockTimestamp());

    assertEq(state.lastInterestAccruedTimestamp, vm.getBlockTimestamp());
    assertEq(protocolFee, 0, 'incorrect protocolFee');
    assertEq(state.scaleFactor, 1.1e27, 'incorrect scaleFactor');
    assertEq(baseInterestRay, 1e26, 'incorrect baseInterestRay');
    assertEq(delinquencyFeeRay, 0, 'incorrect delinquencyFeeRay');
  }

  // ┌─ test_updateScaleFactorAndFees_ZeroDelinquencyFeeAccumulatesTime ─────
  function test_updateScaleFactorAndFees_ZeroDelinquencyFeeAccumulatesTime() external pure {
    MarketState memory state;
    state.isDelinquent = true;
    state.timeDelinquent = 1 days;
    state.scaleFactor = uint112(RAY);
    state.lastInterestAccruedTimestamp = uint32(10 days);

    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(0, 2 days, 10 days + 6 hours);

    assertEq(state.timeDelinquent, 1 days + 6 hours, 'incorrect accumulated delinquency time');
    assertEq(state.lastInterestAccruedTimestamp, 10 days + 6 hours, 'incorrect update timestamp');
    assertEq(state.scaleFactor, RAY, 'zero fee changed scale factor');
    assertEq(baseInterestRay, 0, 'unexpected base interest');
    assertEq(delinquencyFeeRay, 0, 'unexpected delinquency fee');
    assertEq(protocolFee, 0, 'unexpected protocol fee');
  }

  // ┌─ test_updateScaleFactorAndFees_ZeroDelinquencyFeeDecaysTime ─────
  function test_updateScaleFactorAndFees_ZeroDelinquencyFeeDecaysTime() external pure {
    MarketState memory state;
    state.timeDelinquent = 2 days;
    state.scaleFactor = uint112(RAY);
    state.lastInterestAccruedTimestamp = uint32(10 days);

    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(0, 1 days, 10 days + 6 hours);

    assertEq(state.timeDelinquent, 1 days + 18 hours, 'incorrect recovered delinquency time');
    assertEq(state.lastInterestAccruedTimestamp, 10 days + 6 hours, 'incorrect update timestamp');
    assertEq(state.scaleFactor, RAY, 'zero fee changed scale factor');
    assertEq(baseInterestRay, 0, 'unexpected base interest');
    assertEq(delinquencyFeeRay, 0, 'unexpected delinquency fee');
    assertEq(protocolFee, 0, 'unexpected protocol fee');
  }

  // ┌─ test_updateScaleFactorAndFees_AcceptedUint112LimitReverts ─────
  function test_updateScaleFactorAndFees_AcceptedUint112LimitReverts() external {
    MarketState memory state;
    // last safe value after 2,829 daily updates at 100% APR plus a 100% delinquency fee.
    // the next daily update exceeds uint112.
    state.scaleFactor = 5_173_473_415_954_182_535_546_019_067_317_983;
    state.annualInterestBips = 10_000;
    state.lastInterestAccruedTimestamp = 1;
    state.isDelinquent = true;
    state.timeDelinquent = 1;

    vm.expectRevert(abi.encodeWithSelector(bytes4(0x4e487b71), uint256(0x11)));
    state.$updateScaleFactorAndFees(10_000, 0, 1 days + 1);
  }

  // ┌─ test_updateScaleFactorAndFees_Uint112MaxStableAtZeroRate ─────
  function test_updateScaleFactorAndFees_Uint112MaxStableAtZeroRate() external pure {
    MarketState memory state;
    state.scaleFactor = type(uint112).max;
    state.lastInterestAccruedTimestamp = 1;

    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) = state.$updateScaleFactorAndFees(0, 0, 1 days + 1);

    assertEq(state.scaleFactor, type(uint112).max, 'incorrect scaleFactor');
    assertEq(state.lastInterestAccruedTimestamp, 1 days + 1);
    assertEq(baseInterestRay, 0, 'incorrect baseInterestRay');
    assertEq(delinquencyFeeRay, 0, 'incorrect delinquencyFeeRay');
    assertEq(protocolFee, 0, 'incorrect protocolFee');
  }

  // ┌─ test_updateScaleFactorAndFees_NoTimeDelta ─────
  function test_updateScaleFactorAndFees_NoTimeDelta(
    MarketState calldata stateInput,
    uint16 delinquencyFeeBips,
    uint32 delinquencyGracePeriod
  )
    external
    pure
  {
    MarketState memory state = stateInput;
    bytes32 stateHash = keccak256(abi.encode(state));
    uint256 baseInterestRay;
    uint256 delinquencyFeeRay;
    uint256 protocolFee;
    (state, baseInterestRay, delinquencyFeeRay, protocolFee) =
      state.$updateScaleFactorAndFees(delinquencyFeeBips, delinquencyGracePeriod, state.lastInterestAccruedTimestamp);
    assertEq(baseInterestRay, 0, 'incorrect baseInterestRay');
    assertEq(delinquencyFeeRay, 0, 'incorrect delinquencyFeeRay');
    assertEq(protocolFee, 0, 'incorrect protocolFee');
    assertEq(keccak256(abi.encode(state)), stateHash, 'state should not change');
  }

  // ░░▒▒▓▓██ [ DELINQUENCY ] ──────────────────────────────────────────────────

  // ┌─ test_updateTimeDelinquentAndGetPenaltyTime ─────
  function test_updateTimeDelinquentAndGetPenaltyTime(
    bool isCurrentlyDelinquent,
    uint32 previousTimeDelinquent,
    uint32 timeDelta,
    uint32 delinquencyGracePeriod
  )
    external
    pure
  {
    MarketState memory state;
    state.isDelinquent = isCurrentlyDelinquent;
    previousTimeDelinquent = uint32(bound(previousTimeDelinquent, 0, type(uint32).max - timeDelta));
    state.timeDelinquent = previousTimeDelinquent;

    uint256 timeWithPenalty;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(delinquencyGracePeriod, timeDelta);
    if (isCurrentlyDelinquent) {
      if (previousTimeDelinquent >= delinquencyGracePeriod) {
        // already past grace: the full interval incurs a penalty.
        assertEq(timeWithPenalty, timeDelta, 'should be full delta when past grace period');
      } else if (previousTimeDelinquent + timeDelta >= delinquencyGracePeriod) {
        // crossing grace charges only the time after the boundary.
        assertEq(
          timeWithPenalty,
          (previousTimeDelinquent + timeDelta) - delinquencyGracePeriod,
          'incorrect partial delta when crossing grace period'
        );
      } else {
        // no grace crossing, no penalty.
        assertEq(timeWithPenalty, 0, 'should be no penalty when not past grace period');
      }
      assertEq(state.timeDelinquent, previousTimeDelinquent + timeDelta, 'incorrect timeDelinquent');
    } else {
      if (previousTimeDelinquent >= delinquencyGracePeriod) {
        uint32 timeLeftWithPenalty = previousTimeDelinquent - delinquencyGracePeriod;
        if (timeLeftWithPenalty >= timeDelta) {
          // the timer stays above grace for the full interval.
          assertEq(timeWithPenalty, timeDelta, 'should be full delta when time left with penalty is >= delta');
        } else {
          // charge only until the timer decays to grace.
          assertEq(
            timeWithPenalty,
            timeLeftWithPenalty,
            'incorrect partial delta when time left with penalty is less than delta'
          );
        }
      } else {
        // at or below grace, no penalty.
        assertEq(timeWithPenalty, 0, 'should be no penalty when not past grace period');
      }

      if (previousTimeDelinquent <= timeDelta) {
        assertEq(state.timeDelinquent, 0, 'incorrect timeDelinquent');
      } else {
        assertEq(state.timeDelinquent, previousTimeDelinquent - timeDelta, 'incorrect timeDelinquent');
      }
    }
  }

  // ┌─ testUpdateTimeDelinquentAndGetPenaltyTime ─────
  function testUpdateTimeDelinquentAndGetPenaltyTime() external pure {
    MarketState memory state;
    uint256 timeWithPenalty;
    // within grace period, no penalty.
    state.timeDelinquent = 50;
    state.isDelinquent = true;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 25);
    assertEq(timeWithPenalty, 0);
    assertEq(state.timeDelinquent, 75);

    // reach grace period cutoff, no penalty.
    state.timeDelinquent = 50;
    state.isDelinquent = true;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 50);
    assertEq(timeWithPenalty, 0);
    assertEq(state.timeDelinquent, 100);

    // cross over grace period, penalty on delta after crossing.
    state.timeDelinquent = 99;
    state.isDelinquent = true;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 100);
    assertEq(timeWithPenalty, 99);
    assertEq(state.timeDelinquent, 199);

    // at grace period cutoff, penalty on full delta.
    state.timeDelinquent = 100;
    state.isDelinquent = true;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 100);
    assertEq(timeWithPenalty, 100);
    assertEq(state.timeDelinquent, 200);

    // past grace period cutoff, penalty on full delta.
    state.timeDelinquent = 101;
    state.isDelinquent = true;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 100);
    assertEq(timeWithPenalty, 100);
    assertEq(state.timeDelinquent, 201);

    // cross under grace period, penalty on delta before crossing.
    state.timeDelinquent = 100;
    state.isDelinquent = false;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(99, 100);
    assertEq(timeWithPenalty, 1);
    assertEq(state.timeDelinquent, 0);

    // reach grace period cutoff, no penalty.
    state.timeDelinquent = 50;
    state.isDelinquent = false;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 50);
    assertEq(timeWithPenalty, 0);
    assertEq(state.timeDelinquent, 0);

    state.timeDelinquent = 50;
    state.isDelinquent = false;
    (state, timeWithPenalty) = state.$updateTimeDelinquentAndGetPenaltyTime(100, 100);
    assertEq(timeWithPenalty, 0);
    assertEq(state.timeDelinquent, 0);
  }
}

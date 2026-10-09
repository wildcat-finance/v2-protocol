// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // FeeMathExternal
//  \ ^ /   External adapters for accrual, protocol fees, and delinquency.
//    V
//
//  ACCRUAL
//  $updateScaleFactorAndFees(...)
//
//  BASE INTEREST
//  $calculateBaseInterest(...)
//  $calculateLinearInterestFromBips(...)
//
//  PROTOCOL FEES
//  $applyProtocolFee(...)
//
//  DELINQUENCY
//  $updateDelinquency(...)
//  $updateTimeDelinquentAndGetPenaltyTime(...)
//
//  REFERENCE ACCRUAL
//  _updateScaleFactorAndFees(...)
//  _updateDelinquency(...)
// ═════

import { FeeMath } from 'src/libraries/FeeMath.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils } from 'src/libraries/MathUtils.sol';
import { SafeCastLib } from 'src/libraries/SafeCastLib.sol';

// ┌─ FeeMathExternal ──────────────────────────────────────────────────────────
library FeeMathExternal {
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  // ░░▒▒▓▓██ [ ACCRUAL ] ──────────────────────────────────────────────────────

  // ┌─ $updateScaleFactorAndFees ─────
  function $updateScaleFactorAndFees(
    MarketState memory state,
    uint256 delinquencyFeeBips,
    uint256 delinquencyGracePeriod,
    uint256 timestamp
  )
    external
    pure
    returns (MarketState memory newState, uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee)
  {
    newState = state;
    (baseInterestRay, delinquencyFeeRay, protocolFee) =
      _updateScaleFactorAndFees(state, delinquencyFeeBips, delinquencyGracePeriod, timestamp);
  }

  // ░░▒▒▓▓██ [ BASE INTEREST ] ────────────────────────────────────────────────

  // ┌─ $calculateBaseInterest ─────
  function $calculateBaseInterest(
    MarketState memory state,
    uint256 timestamp
  )
    external
    pure
    returns (uint256 baseInterestRay)
  {
    return FeeMath.calculateBaseInterest(state, timestamp);
  }

  // ┌─ $calculateLinearInterestFromBips ─────
  function $calculateLinearInterestFromBips(uint256 rateBip, uint256 timeDelta) external pure returns (uint256 result) {
    return MathUtils.calculateLinearInterestFromBips(rateBip, timeDelta);
  }

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  // ┌─ $applyProtocolFee ─────
  function $applyProtocolFee(
    MarketState memory state,
    uint256 baseInterestRay
  )
    external
    pure
    returns (MarketState memory newState, uint256 protocolFee)
  {
    protocolFee = FeeMath.applyProtocolFee(state, baseInterestRay);
    newState = state;
  }

  // ░░▒▒▓▓██ [ DELINQUENCY ] ──────────────────────────────────────────────────

  // ┌─ $updateDelinquency ─────
  function $updateDelinquency(
    MarketState memory state,
    uint256 timestamp,
    uint256 delinquencyFeeBips,
    uint256 delinquencyGracePeriod
  )
    external
    pure
    returns (MarketState memory newState, uint256 delinquencyFeeRay)
  {
    newState = state;
    delinquencyFeeRay = _updateDelinquency(state, timestamp, delinquencyFeeBips, delinquencyGracePeriod);
  }

  // ┌─ $updateTimeDelinquentAndGetPenaltyTime ─────
  function $updateTimeDelinquentAndGetPenaltyTime(
    MarketState memory state,
    uint256 delinquencyGracePeriod,
    uint256 timeDelta
  )
    external
    pure
    returns (MarketState memory newState, uint256 timeWithPenalty)
  {
    newState = state;
    timeWithPenalty = FeeMath.updateTimeDelinquentAndGetPenaltyTime(state, delinquencyGracePeriod, timeDelta);
  }

  // ░░▒▒▓▓██ [ REFERENCE ACCRUAL ] ────────────────────────────────────────────

  // ┌─ _updateScaleFactorAndFees ─────
  /// @dev standalone accrual model built from the live FeeMath primitives. markets accrue through
  ///      WildcatMarketBase._updateScaleFactorAndFees, which also applies the post-repayment-date
  ///      full penalty.
  function _updateScaleFactorAndFees(
    MarketState memory state,
    uint256 delinquencyFeeBips,
    uint256 delinquencyGracePeriod,
    uint256 timestamp
  )
    private
    pure
    returns (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee)
  {
    baseInterestRay = state.calculateBaseInterest(timestamp);

    if (state.protocolFeeBips > 0) {
      protocolFee = state.applyProtocolFee(baseInterestRay);
    }

    delinquencyFeeRay = _updateDelinquency(state, timestamp, delinquencyFeeBips, delinquencyGracePeriod);

    uint256 prevScaleFactor = state.scaleFactor;
    uint256 scaleFactorDelta = prevScaleFactor.rayMul(baseInterestRay + delinquencyFeeRay);

    // the uint112 scale-factor horizon is finite. keep the checked revert, not truncation.
    state.scaleFactor = (prevScaleFactor + scaleFactorDelta).toUint112();
    state.lastInterestAccruedTimestamp = uint32(timestamp);
  }

  // ┌─ _updateDelinquency ─────
  /// @dev advance or decay the delinquency timer and return the fee rate for its penalized seconds.
  function _updateDelinquency(
    MarketState memory state,
    uint256 timestamp,
    uint256 delinquencyFeeBips,
    uint256 delinquencyGracePeriod
  )
    private
    pure
    returns (uint256 delinquencyFeeRay)
  {
    uint256 timeWithPenalty = FeeMath.updateTimeDelinquentAndGetPenaltyTime(
      state, delinquencyGracePeriod, timestamp - state.lastInterestAccruedTimestamp
    );

    if (timeWithPenalty > 0 && delinquencyFeeBips > 0) {
      delinquencyFeeRay = MathUtils.calculateLinearInterestFromBips(delinquencyFeeBips, timeWithPenalty);
    }
  }
}

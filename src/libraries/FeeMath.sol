// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // FeeMath
//  \ ^ /   Base interest, protocol fees, and delinquency accrual.
//    V
//
//  BASE INTEREST
//  calculateBaseInterest(...)
//
//  PROTOCOL FEES
//  applyProtocolFee(...)
//
//  DELINQUENCY
//  updateTimeDelinquentAndGetPenaltyTime(...)
// ═════

import './MathUtils.sol';
import './SafeCastLib.sol';
import './MarketState.sol';

using SafeCastLib for uint256;
using MathUtils for uint256;

// ┌─ FeeMath ──────────────────────────────────────────────────────────────────
library FeeMath {
  // ░░▒▒▓▓██ [ BASE INTEREST ] ────────────────────────────────────────────────

  // ┌─ calculateBaseInterest ─────
  /// @dev return linear base interest from the last accrual timestamp through `timestamp`, in ray.
  function calculateBaseInterest(
    MarketState memory state,
    uint256 timestamp
  )
    internal
    pure
    returns (uint256 baseInterestRay)
  {
    baseInterestRay = MathUtils.calculateLinearInterestFromBips(
      state.annualInterestBips, timestamp - state.lastInterestAccruedTimestamp
    );
  }

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  // ┌─ applyProtocolFee ─────
  /// @dev accrue the protocol's fee on base interest without increasing lender balances.
  ///
  /// @return protocolFee normalized fee added to `state.accruedProtocolFees`.
  function applyProtocolFee(
    MarketState memory state,
    uint256 baseInterestRay
  )
    internal
    pure
    returns (uint256 protocolFee)
  {
    // protocol fees are added to the borrower's debt, not taken from lender interest.
    uint256 protocolFeeRay = uint(state.protocolFeeBips).bipMul(baseInterestRay);
    protocolFee = uint256(state.scaledTotalSupply).rayMul(uint256(state.scaleFactor).rayMul(protocolFeeRay));
    state.accruedProtocolFees = (state.accruedProtocolFees + protocolFee).toUint128();
  }

  // ░░▒▒▓▓██ [ DELINQUENCY ] ──────────────────────────────────────────────────

  // ┌─ updateTimeDelinquentAndGetPenaltyTime ─────
  /// @notice update `timeDelinquent` and return the interval's penalized seconds.
  ///
  /// @dev when `isDelinquent`, equivalent to:
  ///        max(0, timeDelta - max(0, delinquencyGracePeriod - previousTimeDelinquent))
  ///      when `!isDelinquent`, equivalent to:
  ///        min(timeDelta, max(0, previousTimeDelinquent - delinquencyGracePeriod))
  ///
  /// @param state                  market state to update.
  /// @param delinquencyGracePeriod seconds in delinquency before penalties apply.
  /// @param timeDelta              seconds since the last update.
  ///
  /// @return `timeWithPenalty` seconds in the interval charged a delinquency penalty.
  function updateTimeDelinquentAndGetPenaltyTime(
    MarketState memory state,
    uint256 delinquencyGracePeriod,
    uint256 timeDelta
  )
    internal
    pure
    returns (
      uint256 /* timeWithPenalty */
    )
  {
    uint256 previousTimeDelinquent = state.timeDelinquent;

    if (state.isDelinquent) {
      state.timeDelinquent = (previousTimeDelinquent + timeDelta).toUint32();

      uint256 secondsRemainingWithoutPenalty = delinquencyGracePeriod.satSub(previousTimeDelinquent);

      // only time beyond the remaining grace period incurs a penalty.
      return timeDelta.satSub(secondsRemainingWithoutPenalty);
    }

    // healthy time works the timer down, not straight to zero.
    state.timeDelinquent = previousTimeDelinquent.satSub(timeDelta).toUint32();

    uint256 secondsRemainingWithPenalty = previousTimeDelinquent.satSub(delinquencyGracePeriod);

    // penalties continue only until the timer falls back inside the grace period.
    return MathUtils.min(secondsRemainingWithPenalty, timeDelta);
  }
}

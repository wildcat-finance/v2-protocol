// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // FeeMath
// ║  ██▀▀     ▀▀██   Base interest, protocol fees, and delinquency accrual.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ACCRUAL
// ║  updateScaleFactorAndFees(...)
// ║
// ║  BASE INTEREST
// ║  calculateBaseInterest(...)
// ║  calculateLinearInterestFromBips(...)
// ║
// ║  PROTOCOL FEES
// ║  applyProtocolFee(...)
// ║
// ║  DELINQUENCY
// ║  updateDelinquency(...)
// ║  updateTimeDelinquentAndGetPenaltyTime(...)
// ╚═════

import './MathUtils.sol';
import './SafeCastLib.sol';
import './MarketState.sol';

using SafeCastLib for uint256;
using MathUtils for uint256;

// ┌─ FeeMath ──────────────────────────────────────────────────────────────────
library FeeMath {
  // ░░▒▒▓▓██ [ ACCRUAL ] ──────────────────────────────────────────────────────

  // ┌─ updateScaleFactorAndFees ─────
  /// @dev accrue base interest, delinquency fees, and protocol fees into memory state.
  ///      return the base and penalty rates plus normalized protocol fees for the interval.
  ///      an explicit `timestamp` lets callers split accrual at a batch expiry.
  ///
  /// @param state                  market scale parameters.
  /// @param delinquencyFeeBips     delinquency fee rate, in bips.
  /// @param delinquencyGracePeriod grace period before delinquency fees apply, in seconds.
  /// @param timestamp              accrual endpoint, in seconds.
  ///
  /// @return baseInterestRay base interest accrued to lenders, in ray.
  /// @return delinquencyFeeRay accrued delinquency penalty rate, in ray.
  /// @return protocolFee fee charged on base interest, in normalized tokens.
  function updateScaleFactorAndFees(
    MarketState memory state,
    uint256 delinquencyFeeBips,
    uint256 delinquencyGracePeriod,
    uint256 timestamp
  )
    internal
    pure
    returns (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee)
  {
    baseInterestRay = state.calculateBaseInterest(timestamp);

    if (state.protocolFeeBips > 0) {
      protocolFee = state.applyProtocolFee(baseInterestRay);
    }

    delinquencyFeeRay = state.updateDelinquency(timestamp, delinquencyFeeBips, delinquencyGracePeriod);

    uint256 prevScaleFactor = state.scaleFactor;
    uint256 scaleFactorDelta = prevScaleFactor.rayMul(baseInterestRay + delinquencyFeeRay);

    // the uint112 scale-factor horizon is finite. keep the checked revert, not truncation.
    // accepted boundary; see MarketState and Known Issues.
    state.scaleFactor = (prevScaleFactor + scaleFactorDelta).toUint112();
    state.lastInterestAccruedTimestamp = uint32(timestamp);
  }

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

  // ┌─ calculateLinearInterestFromBips ─────
  /// @dev calculate linear interest over the elapsed interval.
  ///
  /// @param rateBip   annual interest rate, in bips.
  /// @param timeDelta seconds since the last accrual.
  ///
  /// @return result linear interest over `timeDelta`, in ray.
  function calculateLinearInterestFromBips(uint256 rateBip, uint256 timeDelta) internal pure returns (uint256 result) {
    uint256 rate = rateBip.bipToRay();
    uint256 accumulatedInterestRay = rate * timeDelta;
    unchecked {
      return accumulatedInterestRay / SECONDS_IN_365_DAYS;
    }
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

  // ┌─ updateDelinquency ─────
  /// @dev advance or decay the delinquency timer and return the fee rate accrued over the
  ///      interval's penalized seconds, in ray.
  function updateDelinquency(
    MarketState memory state,
    uint256 timestamp,
    uint256 delinquencyFeeBips,
    uint256 delinquencyGracePeriod
  )
    internal
    pure
    returns (uint256 delinquencyFeeRay)
  {
    uint256 timeWithPenalty = updateTimeDelinquentAndGetPenaltyTime(
      state, delinquencyGracePeriod, timestamp - state.lastInterestAccruedTimestamp
    );

    if (timeWithPenalty > 0 && delinquencyFeeBips > 0) {
      delinquencyFeeRay = calculateLinearInterestFromBips(delinquencyFeeBips, timeWithPenalty);
    }
  }

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

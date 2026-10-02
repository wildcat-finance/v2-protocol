// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // FeeMathExternal
// ║  ██▀▀     ▀▀██   External adapters for accrual, protocol fees, and delinquency.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ACCRUAL
// ║  $updateScaleFactorAndFees(...)
// ║
// ║  BASE INTEREST
// ║  $calculateBaseInterest(...)
// ║  $calculateLinearInterestFromBips(...)
// ║
// ║  PROTOCOL FEES
// ║  $applyProtocolFee(...)
// ║
// ║  DELINQUENCY
// ║  $updateDelinquency(...)
// ║  $updateTimeDelinquentAndGetPenaltyTime(...)
// ╚═════

import { FeeMath } from 'src/libraries/FeeMath.sol';
import { MarketState } from 'src/libraries/MarketState.sol';

// ┌─ FeeMathExternal ──────────────────────────────────────────────────────────
library FeeMathExternal {
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
      FeeMath.updateScaleFactorAndFees(state, delinquencyFeeBips, delinquencyGracePeriod, timestamp);
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
    return FeeMath.calculateLinearInterestFromBips(rateBip, timeDelta);
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
    delinquencyFeeRay = FeeMath.updateDelinquency(state, timestamp, delinquencyFeeBips, delinquencyGracePeriod);
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
}

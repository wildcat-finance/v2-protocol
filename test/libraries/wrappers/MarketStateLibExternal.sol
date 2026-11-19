// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketStateLibExternal
//  \ ^ /   External adapters for market state and share conversion.
//    V
//
//  SUPPLY AND CAPACITY
//  $totalSupply(...)
//  $maximumDeposit(...)
//
//  SHARE CONVERSION
//  $normalizeAmount(...)
//  $scaleAmountDown(...)
//  $maxScaledSettleableAmount(...)
//
//  LIABILITIES AND LIQUIDITY
//  $totalDebts(...)
//  $liquidityRequired(...)
//  $borrowableAssets(...)
//  $withdrawableProtocolFees(...)
//
//  WITHDRAWAL STATUS
//  $hasPendingExpiredBatch(...)
// ═════

import { MarketState, MarketStateLib } from 'src/libraries/MarketState.sol';

// ┌─ MarketStateLibExternal ───────────────────────────────────────────────────
library MarketStateLibExternal {
  // ░░▒▒▓▓██ [ SUPPLY AND CAPACITY ] ──────────────────────────────────────────

  // ┌─ $totalSupply ─────
  /// @dev return the normalized total supply of the market.
  function $totalSupply(MarketState memory state) external pure returns (uint256) {
    return MarketStateLib.totalSupply(state);
  }

  // ┌─ $maximumDeposit ─────
  /// @dev return normalized deposit capacity up to the maximum supply.
  function $maximumDeposit(MarketState memory state) external pure returns (uint256) {
    return MarketStateLib.maximumDeposit(state);
  }

  // ░░▒▒▓▓██ [ SHARE CONVERSION ] ─────────────────────────────────────────────

  // ┌─ $normalizeAmount ─────
  /// @dev normalize an amount of scaled tokens using the current scale factor.
  function $normalizeAmount(MarketState memory state, uint256 amount) external pure returns (uint256) {
    return MarketStateLib.normalizeAmount(state, amount);
  }

  // ┌─ $scaleAmountDown ─────
  /// @dev scale an amount of normalized tokens using the current scale factor,
  /// rounding down.
  function $scaleAmountDown(MarketState memory state, uint256 amount) external pure returns (uint256) {
    return MarketStateLib.scaleAmountDown(state, amount);
  }

  // ┌─ $maxScaledSettleableAmount ─────
  function $maxScaledSettleableAmount(MarketState memory state, uint256 amount) external pure returns (uint256) {
    return MarketStateLib.maxScaledSettleableAmount(state, amount);
  }

  // ░░▒▒▓▓██ [ LIABILITIES AND LIQUIDITY ] ────────────────────────────────────

  // ┌─ $totalDebts ─────
  function $totalDebts(MarketState memory state) external pure returns (uint256) {
    return MarketStateLib.totalDebts(state);
  }

  // ┌─ $liquidityRequired ─────
  /// cover pending withdrawals and protocol fees, plus reserves on the remaining supply.
  function $liquidityRequired(MarketState memory state) external pure returns (uint256 _liquidityRequired) {
    return MarketStateLib.liquidityRequired(state);
  }

  // ┌─ $borrowableAssets ─────
  function $borrowableAssets(MarketState memory state, uint256 totalAssets) external pure returns (uint256) {
    return MarketStateLib.borrowableAssets(state, totalAssets);
  }

  // ┌─ $withdrawableProtocolFees ─────
  function $withdrawableProtocolFees(MarketState memory state, uint256 totalAssets) external pure returns (uint256) {
    return MarketStateLib.withdrawableProtocolFees(state, totalAssets);
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL STATUS ] ────────────────────────────────────────────

  // ┌─ $hasPendingExpiredBatch ─────
  function $hasPendingExpiredBatch(MarketState memory state) external view returns (bool result) {
    return MarketStateLib.hasPendingExpiredBatch(state);
  }
}

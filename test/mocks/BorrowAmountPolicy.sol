// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // BorrowAmountPolicy
//  \ ^ /   Per-borrow amount limits for feature integration tests.
//    V
//
//  BORROW LIMITS
//  setBorrowAmountLimit(...)
//  _setBorrowAmountLimit(...)
//
//  BORROW RECORDING
//  _recordBorrowAmount(...)
// ═════

import { FeatureAuthority } from './TransferFeaturePolicies.sol';

// ┌─ BorrowAmountPolicy ───────────────────────────────────────────────────────
/// @dev test-only per-borrow limit, in underlying asset units. no scaled-balance conversion here.
abstract contract BorrowAmountPolicy is FeatureAuthority {
  error BorrowAmountLimitExceeded();

  event BorrowAmountLimitUpdated(address indexed market, uint256 maximumNormalizedAmount);
  event BorrowAmountRecorded(address indexed market, uint256 normalizedAmount);

  mapping(address => uint256) public maximumNormalizedBorrow;
  mapping(address => uint256) public lastNormalizedBorrow;

  // ░░▒▒▓▓██ [ BORROW LIMITS ] ────────────────────────────────────────────────

  // ┌─ setBorrowAmountLimit ─────
  function setBorrowAmountLimit(address market, uint256 maximumNormalizedAmount) external {
    _authorizeFeatureManagement(market);
    _setBorrowAmountLimit(market, maximumNormalizedAmount);
  }

  // ┌─ _setBorrowAmountLimit ─────
  function _setBorrowAmountLimit(address market, uint256 maximumNormalizedAmount) internal {
    // zero disables positive borrows. it doesn't affect deposits, transfers, or withdrawals.
    maximumNormalizedBorrow[market] = maximumNormalizedAmount;
    emit BorrowAmountLimitUpdated(market, maximumNormalizedAmount);
  }

  // ░░▒▒▓▓██ [ BORROW RECORDING ] ─────────────────────────────────────────────

  // ┌─ _recordBorrowAmount ─────
  function _recordBorrowAmount(address market, uint256 normalizedAmount) internal {
    if (normalizedAmount > maximumNormalizedBorrow[market]) revert BorrowAmountLimitExceeded();
    lastNormalizedBorrow[market] = normalizedAmount;
    emit BorrowAmountRecorded(market, normalizedAmount);
  }
}

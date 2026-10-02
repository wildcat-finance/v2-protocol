// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IMarketLensLive
//  \ ^ /   Compact accrued-state and lender query surface.
//    V
//
//  LIVE MARKET DATA
//  getMarketsLiveDataV2(...)
//  getMarketsLiveDataWithLenderStatusV2(...)
// ═════

import '../MarketLiveData.sol';

// ┌─ IMarketLensLive ──────────────────────────────────────────────────────────
/// @title compact live market lens reads
///
/// @notice current accounting data without the heavier static configuration and hooks metadata.
interface IMarketLensLive {
  // ░░▒▒▓▓██ [ LIVE MARKET DATA ] ─────────────────────────────────────────────

  // ┌─ getMarketsLiveDataV2 ─────
  /// @notice return accrued accounting, lifecycle, and liquidity for each market in input order.
  ///
  /// @dev lifecycle.defaultedAt is committed storage; accrued views do not record default.
  function getMarketsLiveDataV2(address[] calldata markets) external view returns (MarketLiveDataV2_5[] memory data);

  // ┌─ getMarketsLiveDataWithLenderStatusV2 ─────
  /// @notice return compact accrued state plus `lender` status for each market.
  function getMarketsLiveDataWithLenderStatusV2(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (MarketLiveDataWithLenderStatusV2_5[] memory data);
}

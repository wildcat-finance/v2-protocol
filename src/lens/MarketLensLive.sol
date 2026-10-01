// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketLensLive
// ║  ██▀▀     ▀▀██   Compact accrued-state and lender queries.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  constructor(...)
// ║
// ║  LIVE MARKET DATA
// ║  getMarketsLiveDataV2(...)
// ║  getMarketsLiveDataWithLenderStatusV2(...)
// ╚═════

import '../IHooksFactory.sol';
import '../market/WildcatMarket.sol';
import './MarketLiveData.sol';
import './interfaces/IMarketLensLive.sol';

// ┌─ MarketLensLive ───────────────────────────────────────────────────────────
/// @title compact live market lens helper
///
/// @notice returns accrued accounting state without building the full hooks and configuration
///         tuple.
contract MarketLensLive is IMarketLensLive {
  /// @notice ArchController configured for this helper.
  WildcatArchController public immutable archController;

  /// @notice default hooks factory configured for this helper.
  IHooksFactory public immutable hooksFactory;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address _archController, address _hooksFactory) {
    archController = WildcatArchController(_archController);
    hooksFactory = IHooksFactory(_hooksFactory);
  }

  // ░░▒▒▓▓██ [ LIVE MARKET DATA ] ─────────────────────────────────────────────

  // ┌─ getMarketsLiveDataV2 ─────
  function getMarketsLiveDataV2(address[] calldata markets) external view returns (MarketLiveDataV2_5[] memory data) {
    data = new MarketLiveDataV2_5[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]));
    }
  }

  // ┌─ getMarketsLiveDataWithLenderStatusV2 ─────
  function getMarketsLiveDataWithLenderStatusV2(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (MarketLiveDataWithLenderStatusV2_5[] memory data)
  {
    data = new MarketLiveDataWithLenderStatusV2_5[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]), lender);
    }
  }
}

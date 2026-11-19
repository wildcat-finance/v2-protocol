// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketLifecycleData
//  \ ^ /   Repayment lifecycle and current underlying-asset capacity.
//    V
//
//  LIFECYCLE AND LIQUIDITY
//  fill(...)
//  fill(...)
// ═════

import '../market/WildcatMarket.sol';
import './OptionalData.sol';

using MarketLifecycleDataLib for MarketLifecycleData global;
using MarketLifecycleDataLib for MarketLiquidityData global;

/// @notice repayment terms and the market's recorded default timestamp.
struct MarketLifecycleData {
  /// @dev true only when all four lifecycle getters return a complete word. zero terms are valid.
  bool isPresent;
  uint256 repaymentDate;
  uint256 repaymentPeriod;
  uint256 repaymentDeadline;

  /// @dev committed storage only. zero does not prove an unwritten deadline was met.
  uint256 defaultedAt;

  /// @dev the date has arrived and accrued state has not closed the market.
  bool isInRepayment;
}

/// @notice current underlying-asset amounts used by deposit, borrow, repayment, and recovery flows.
///
/// @dev these are accounting amounts. hooks, authority checks, sanctions, and token transfers
///      can still prevent an action.
struct MarketLiquidityData {
  uint256 maximumDeposit;
  uint256 borrowableAssets;
  uint256 totalDebts;

  /// @dev assets above every lender/fee liability when accrued state is closed; zero otherwise.
  uint256 recoverableUnderlying;
}

// ┌─ MarketLifecycleDataLib ───────────────────────────────────────────────────
/// @notice shared full/live lens reads for lifecycle and available liquidity.
library MarketLifecycleDataLib {
  // ░░▒▒▓▓██ [ LIFECYCLE AND LIQUIDITY ] ──────────────────────────────────────

  // ┌─ fill ─────
  function fill(MarketLifecycleData memory data, WildcatMarket market, bool isClosed) internal view {
    bytes4[4] memory selectors = [
      WildcatMarketBase.repaymentDate.selector,
      WildcatMarketBase.repaymentPeriod.selector,
      WildcatMarketBase.repaymentDeadline.selector,
      WildcatMarketBase.defaultedAt.selector
    ];
    uint256[4] memory values;
    for (uint256 i; i < selectors.length; i++) {
      (bool success, uint256 value) = OptionalDataLib.readWord(address(market), abi.encodeWithSelector(selectors[i]));
      // don't publish a partially supported lifecycle as complete zero-valued terms.
      if (!success) return;
      values[i] = value;
    }
    data.isPresent = true;
    data.repaymentDate = values[0];
    data.repaymentPeriod = values[1];
    data.repaymentDeadline = values[2];
    data.defaultedAt = values[3];
    data.isInRepayment = !isClosed && values[0] != 0 && block.timestamp >= values[0];
  }

  // ┌─ fill ─────
  function fill(
    MarketLiquidityData memory data,
    WildcatMarket market,
    bool isClosed,
    uint256 totalAssets
  )
    internal
    view
  {
    data.maximumDeposit = market.maximumDeposit();
    data.borrowableAssets = market.borrowableAssets();
    data.totalDebts = market.totalDebts();
    if (isClosed && totalAssets > data.totalDebts) {
      data.recoverableUnderlying = totalAssets - data.totalDebts;
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LenderAccountData
// ║  ██▀▀     ▀▀██   Lender balances, allowances, and current access status.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  VERSION QUERY
// ║  version()
// ║
// ║  LENDER ACCOUNT DATA
// ║  fill(...)
// ║  fill(...)
// ║  fill(...)
// ╚═════

import '../WildcatArchController.sol';
import { OpenTermHooks } from '../access/OpenTermHooks.sol';
import './TokenData.sol';
import '../types/HooksConfig.sol';
import '../types/LenderStatus.sol';
import './HooksConfigData.sol';
import './HooksTemplateData.sol';
import './MarketData.sol';
import './RoleProviderData.sol';

using LenderAccountDataLib for LenderAccountData global;

/// @notice balances, allowance, and access state for one lender in one market.
///
/// @dev values are a point-in-time read. hook callbacks may still depend on calldata the lens does
///      not have, so this is not a promise that a later action succeeds.
struct LenderAccountData {
  address lender;
  uint256 scaledBalance;
  uint256 normalizedBalance;
  uint256 underlyingBalance;
  uint256 underlyingApproval;
  // Hooks data
  bool isBlockedFromDeposits;
  RoleProviderData lastProvider;
  bool canRefresh;
  uint32 lastApprovalTimestamp;
  bool isKnownLender;
}

// ┌─ IVersionedContract ───────────────────────────────────────────────────────
interface IVersionedContract {
  // ░░▒▒▓▓██ [ VERSION QUERY ] ────────────────────────────────────────────────

  // ┌─ version ─────
  /// @notice returns the contract's declared Wildcat version string.
  function version() external view returns (string memory);
}

// ┌─ LenderAccountDataLib ─────────────────────────────────────────────────────
/// @notice fillers for lender balances and access-control status.
library LenderAccountDataLib {
  // ░░▒▒▓▓██ [ LENDER ACCOUNT DATA ] ──────────────────────────────────────────

  // ┌─ fill ─────
  function fill(LenderAccountData memory data, WildcatMarket market, address lenderAddress) internal view {
    IERC20 underlying = IERC20(market.asset());
    OpenTermHooks hooks = OpenTermHooks(market.hooks().hooksAddress());
    data.fill(market, underlying, hooks, lenderAddress);
  }

  // ┌─ fill ─────
  function fill(LenderAccountData memory data, MarketData memory market, address lenderAddress) internal view {
    data.fill(
      WildcatMarket(market.marketToken.token),
      IERC20(market.underlyingToken.token),
      OpenTermHooks(market.hooksConfig.hooksAddress),
      lenderAddress
    );
  }

  // ┌─ fill ─────
  function fill(
    LenderAccountData memory data,
    WildcatMarket market,
    IERC20 underlying,
    OpenTermHooks hooks,
    address lenderAddress
  )
    internal
    view
  {
    data.lender = lenderAddress;

    data.scaledBalance = market.scaledBalanceOf(lenderAddress);
    data.normalizedBalance = market.balanceOf(lenderAddress);

    data.underlyingBalance = underlying.balanceOf(lenderAddress);
    data.underlyingApproval = underlying.allowance(lenderAddress, address(market));
    if (address(hooks) != address(0)) {
      LenderStatus memory status = hooks.getLenderStatus(lenderAddress);
      data.isBlockedFromDeposits = status.isBlockedFromDeposits;
      if (status.lastProvider != address(0)) {
        data.lastProvider.fill(hooks.getRoleProvider(status.lastProvider));
        data.canRefresh = status.canRefresh;
        data.lastApprovalTimestamp = status.lastApprovalTimestamp;
      }
      data.isKnownLender = hooks.isKnownLenderOnMarket(lenderAddress, address(market));
    }
  }
}

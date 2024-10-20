// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../WildcatArchController.sol';
import { AccessControlHooks } from '../access/AccessControlHooks.sol';
import './TokenData.sol';
import '../types/HooksConfig.sol';
import '../types/LenderStatus.sol';
import './HooksConfigData.sol';
import './HooksTemplateData.sol';
import './MarketData.sol';
import './RoleProviderData.sol';

using LenderAccountDataLib for LenderAccountData global;

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

interface IVersionedContract {
  function version() external view returns (string memory);
}

library LenderAccountDataLib {
  function fill(
    LenderAccountData memory data,
    WildcatMarket market,
    IERC20 underlying,
    AccessControlHooks hooks,
    address lenderAddress
  ) internal view {
    data.lender = lenderAddress;

    data.scaledBalance = market.scaledBalanceOf(lenderAddress);
    data.normalizedBalance = market.balanceOf(lenderAddress);

    data.underlyingBalance = underlying.balanceOf(lenderAddress);
    data.underlyingApproval = underlying.allowance(lenderAddress, address(market));
    if (address(hooks) != address(0)) {
      LenderStatus memory status = hooks.getLenderStatus(lenderAddress);
      if (status.lastProvider != address(0)) {
        data.isBlockedFromDeposits = status.isBlockedFromDeposits;
        data.lastProvider.fill(hooks.getRoleProvider(status.lastProvider));
        data.canRefresh = status.canRefresh;
        data.lastApprovalTimestamp = status.lastApprovalTimestamp;
      }
      data.isKnownLender = hooks.isKnownLenderOnMarket(lenderAddress, address(market));
    }
  }

  function fill(
    LenderAccountData memory data,
    WildcatMarket market,
    address lenderAddress
  ) internal view {
    IERC20 underlying = IERC20(market.asset());
    AccessControlHooks hooks = AccessControlHooks(market.hooks().hooksAddress());
    data.fill(market, underlying, hooks, lenderAddress);
  }

  function fill(
    LenderAccountData memory data,
    MarketData memory market,
    address lenderAddress
  ) internal view {
    data.fill(
      WildcatMarket(market.marketToken.token),
      IERC20(market.underlyingToken.token),
      AccessControlHooks(market.hooksConfig.hooksAddress),
      lenderAddress
    );
  }
}

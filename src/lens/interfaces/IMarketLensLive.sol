// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../MarketLiveData.sol';

/// @title compact live market lens reads
/// @notice current accounting data without the heavier static configuration and hooks metadata.
interface IMarketLensLive {
  /// @notice returns accrued accounting, lifecycle, and liquidity for each market in input order.
  /// @dev lifecycle.defaultedAt is committed storage; accrued views do not record default.
  function getMarketsLiveDataV2(
    address[] calldata markets
  ) external view returns (MarketLiveDataV2_5[] memory data);

  /// @notice returns compact accrued state plus `lender` status for each market.
  function getMarketsLiveDataWithLenderStatusV2(
    address lender,
    address[] calldata markets
  ) external view returns (MarketLiveDataWithLenderStatusV2_5[] memory data);
}

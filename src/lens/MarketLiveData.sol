// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../market/WildcatMarket.sol';
import './LenderAccountData.sol';
import './MarketData.sol';

using MarketLiveDataLib for MarketLiveDataV2_5 global;
using MarketLiveDataLib for MarketLiveDataWithLenderStatusV2_5 global;

/// @notice compact current accounting state for a V2.5 market.
/// @dev omits expensive static configuration, hook metadata, and unpaid-batch enumeration.
struct MarketLiveDataV2_5 {
  address market;
  bool isClosed;
  uint256 protocolFeeBips;
  uint256 reserveRatioBips;
  uint256 annualInterestBips;
  uint256 scaleFactor;
  uint256 totalSupply;
  uint256 maxTotalSupply;
  uint256 scaledTotalSupply;
  uint256 totalAssets;
  /// @dev uncollected accrued protocol fees. the field name is retained for ABI stability.
  uint256 lastAccruedProtocolFees;
  uint256 normalizedUnclaimedWithdrawals;
  uint256 scaledPendingWithdrawals;
  /// @dev current batch expiry, or an expired stored batch that the accrued view can fully fund.
  uint256 pendingWithdrawalExpiry;
  bool isDelinquent;
  uint256 timeDelinquent;
  uint256 lastInterestAccruedTimestamp;
  uint256 coverageLiquidity;
  OptionalUintDataV2_5 commitmentFeeBips;
  OptionalUintDataV2_5 drawnAmount;
}

/// @notice compact market state paired with one lender's current status.
struct MarketLiveDataWithLenderStatusV2_5 {
  MarketLiveDataV2_5 market;
  LenderAccountData lenderStatus;
}

/// @notice fillers for compact live market reads.
library MarketLiveDataLib {
  /// @notice fills accounting state using the market's accrued `currentState()` view.
  function fill(MarketLiveDataV2_5 memory data, WildcatMarket market) internal view {
    data.market = address(market);

    MarketState memory state = market.currentState();
    data.isClosed = state.isClosed;
    data.protocolFeeBips = state.protocolFeeBips;
    data.reserveRatioBips = state.reserveRatioBips;
    data.annualInterestBips = state.annualInterestBips;
    data.scaleFactor = state.scaleFactor;
    data.totalSupply = state.totalSupply();
    data.maxTotalSupply = state.maxTotalSupply;
    data.scaledTotalSupply = state.scaledTotalSupply;
    data.totalAssets = market.totalAssets();
    data.lastAccruedProtocolFees = state.accruedProtocolFees;
    data.normalizedUnclaimedWithdrawals = state.normalizedUnclaimedWithdrawals;
    data.scaledPendingWithdrawals = state.scaledPendingWithdrawals;
    data.pendingWithdrawalExpiry = state.pendingWithdrawalExpiry;
    data.isDelinquent = state.isDelinquent;
    data.timeDelinquent = state.timeDelinquent;
    data.lastInterestAccruedTimestamp = state.lastInterestAccruedTimestamp;

    if (state.pendingWithdrawalExpiry == 0) {
      uint32 expiredBatchExpiry = market.previousState().pendingWithdrawalExpiry;
      if (expiredBatchExpiry > 0) {
        WithdrawalBatch memory expiredBatch = market.getWithdrawalBatch(expiredBatchExpiry);
        if (expiredBatch.scaledTotalAmount == expiredBatch.scaledAmountBurned) {
          data.pendingWithdrawalExpiry = expiredBatchExpiry;
        }
      }
    }

    data.coverageLiquidity = state.liquidityRequired();
    MarketDataLib._tryFillOptionalUint(
      data.commitmentFeeBips,
      address(market),
      MarketDataLib._COMMITMENT_FEE_BIPS_SELECTOR
    );
    MarketDataLib._tryFillOptionalUint(
      data.drawnAmount,
      address(market),
      MarketDataLib._DRAWN_AMOUNT_SELECTOR
    );
  }

  function fill(
    MarketLiveDataWithLenderStatusV2_5 memory data,
    WildcatMarket market,
    address lender
  ) internal view {
    data.market.fill(market);
    data.lenderStatus.fill(market, lender);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../WildcatArchController.sol';
import '../market/WildcatMarket.sol';
import '../types/HooksConfig.sol';
import '../access/MarketConstraintHooks.sol';
import './HooksConfigData.sol';
import './HooksInstanceData.sol';
import './HooksTemplateData.sol';
import './LenderAccountData.sol';
import './TokenData.sol';
import './WithdrawalBatchData.sol';

using MarketDataLib for MarketData global;
using MarketDataLib for MarketDataWithLenderStatus global;
using MarketDataLib for LenderAccountQueryResult global;

struct MarketData {
  // -- Tokens metadata --
  TokenMetadata marketToken;
  TokenMetadata underlyingToken;
  address hooksFactory;
  address borrower;
  MarketHooksData hooksConfig;
  uint256 withdrawalBatchDuration;
  address feeRecipient;
  uint256 delinquencyFeeBips;
  uint256 delinquencyGracePeriod;
  HooksInstanceData hooks;
  // -- Temporary excess reserve ratio --
  bool temporaryReserveRatio;
  uint256 originalAnnualInterestBips;
  uint256 originalReserveRatioBips;
  uint256 temporaryReserveRatioExpiry;
  // -- Market state --
  bool isClosed;
  uint256 protocolFeeBips;
  uint256 reserveRatioBips;
  uint256 annualInterestBips;
  uint256 scaleFactor;
  uint256 totalSupply;
  uint256 maxTotalSupply;
  uint256 scaledTotalSupply;
  uint256 totalAssets;
  uint256 lastAccruedProtocolFees;
  uint256 normalizedUnclaimedWithdrawals;
  uint256 scaledPendingWithdrawals;
  uint256 pendingWithdrawalExpiry;
  bool isDelinquent;
  uint256 timeDelinquent;
  uint256 lastInterestAccruedTimestamp;
  uint32[] unpaidWithdrawalBatchExpiries;
  uint256 coverageLiquidity;
}

struct MarketDataWithLenderStatus {
  MarketData market;
  LenderAccountData lenderStatus;
}

struct LenderAccountQuery {
  address lender;
  address market;
  uint32[] withdrawalBatchExpiries;
}

struct LenderAccountQueryResult {
  MarketData market;
  LenderAccountData lenderStatus;
  WithdrawalBatchDataWithLenderStatus[] withdrawalBatches;
}

library MarketDataLib {
  using MathUtils for uint256;

  error NotV2Market();

  function fill(MarketData memory data, WildcatMarket market) internal view {
    data.marketToken.fill(address(market));
    data.underlyingToken.fill(market.asset());
    string memory version = market.version();
    bool isV2;
    assembly {
      let versionByte := and(mload(add(version, 1)), 0xff)
      isV2 := eq(versionByte, 0x32)
    }
    if (!isV2) {
      revert NotV2Market();
    }
    data.fillConfig();
    data.fillTemporaryExcessReserveRatio();
    data.fillState();
  }

  function fillConfig(MarketData memory data) internal view {
    address marketAddress = address(data.marketToken.token);
    WildcatMarket market = WildcatMarket(marketAddress);
    data.hooksFactory = market.factory();
    data.borrower = market.borrower();
    data.hooksConfig.fill(marketAddress);
    data.withdrawalBatchDuration = market.withdrawalBatchDuration();
    data.feeRecipient = market.feeRecipient();
    data.delinquencyFeeBips = market.delinquencyFeeBips();
    data.delinquencyGracePeriod = market.delinquencyGracePeriod();
    address hooksAddress = data.hooksConfig.hooksAddress;
    data.hooks.fill(hooksAddress, HooksFactory(data.hooksFactory));
  }

  function fillTemporaryExcessReserveRatio(MarketData memory data) internal view {
    address marketAddress = data.marketToken.token;
    address hooksAddress = data.hooks.hooksAddress;
    (
      data.originalAnnualInterestBips,
      data.originalReserveRatioBips,
      data.temporaryReserveRatioExpiry
    ) = MarketConstraintHooks(hooksAddress).temporaryExcessReserveRatio(marketAddress);
    data.temporaryReserveRatio = data.temporaryReserveRatioExpiry > 0;
  }

  function fillState(MarketData memory data) internal view {
    WildcatMarket market = WildcatMarket(data.marketToken.token);
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
    data.lastAccruedProtocolFees = market.accruedProtocolFees();
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
        } else {
          uint32[] memory unpaidWithdrawalBatchExpiries = data.unpaidWithdrawalBatchExpiries;
          data.unpaidWithdrawalBatchExpiries = new uint32[](
            unpaidWithdrawalBatchExpiries.length + 1
          );
          for (uint256 i; i < unpaidWithdrawalBatchExpiries.length; i++) {
            data.unpaidWithdrawalBatchExpiries[i] = unpaidWithdrawalBatchExpiries[i];
          }
          data.unpaidWithdrawalBatchExpiries[
            unpaidWithdrawalBatchExpiries.length
          ] = expiredBatchExpiry;
        }
      }
    }

    data.coverageLiquidity = state.liquidityRequired();
  }

  function getUnpaidAndPendingWithdrawalBatches(
    MarketData memory data
  ) internal view returns (WithdrawalBatchData[] memory unpaidAndPendingWithdrawalBatches) {
    WildcatMarket market = WildcatMarket(data.marketToken.token);
    bool hasPendingWithdrawalBatch = data.pendingWithdrawalExpiry > 0;
    uint256 unpaidExpiriesCount = data.unpaidWithdrawalBatchExpiries.length;
    unpaidAndPendingWithdrawalBatches = new WithdrawalBatchData[](
      unpaidExpiriesCount + (hasPendingWithdrawalBatch ? 1 : 0)
    );
    for (uint256 i; i < unpaidExpiriesCount; i++) {
      unpaidAndPendingWithdrawalBatches[i].fill(market, data.unpaidWithdrawalBatchExpiries[i]);
    }
    if (data.pendingWithdrawalExpiry > 0) {
      unpaidAndPendingWithdrawalBatches[unpaidExpiriesCount].fill(
        market,
        uint32(data.pendingWithdrawalExpiry)
      );
    }
  }

  function fill(
    MarketDataWithLenderStatus memory data,
    WildcatMarket market,
    address lender
  ) internal view {
    data.market.fill(market);
    data.lenderStatus.fill(data.market, lender);
  }

  function fill(
    LenderAccountQueryResult memory result,
    LenderAccountQuery memory query
  ) internal view {
    WildcatMarket market = WildcatMarket(query.market);
    result.market.fill(market);
    result.lenderStatus.fill(result.market, query.lender);

    result.withdrawalBatches = new WithdrawalBatchDataWithLenderStatus[](
      query.withdrawalBatchExpiries.length
    );
    for (uint256 i; i < query.withdrawalBatchExpiries.length; i++) {
      result.withdrawalBatches[i].fill(market, query.withdrawalBatchExpiries[i], query.lender);
    }
  }
}

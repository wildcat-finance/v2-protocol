// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../WildcatArchController.sol';
import '../IHooksFactory.sol';
import '../market/WildcatMarket.sol';
import '../types/HooksConfig.sol';
import '../interfaces/IWildcatMarketRevolving.sol';
import './HooksConfigData.sol';
import './HooksInstanceData.sol';
import './HooksTemplateData.sol';
import './LenderAccountData.sol';
import './TokenData.sol';
import './WithdrawalBatchData.sol';

using MarketDataLib for MarketData global;
using MarketDataLib for MarketDataV2_5 global;
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

struct OptionalUintDataV2_5 {
  bool isPresent;
  uint256 value;
}

struct MarketDataV2_5 {
  MarketData market;
  address borrowerPrincipal;
  address pendingBorrower;
  address pendingBorrowerPrincipal;
  address borrowerIdentityRegistry;
  OptionalUintDataV2_5 commitmentFeeBips;
  OptionalUintDataV2_5 drawnAmount;
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

  bytes4 internal constant _COMMITMENT_FEE_BIPS_SELECTOR =
    IWildcatMarketRevolving.commitmentFeeBips.selector;
  bytes4 internal constant _DRAWN_AMOUNT_SELECTOR = IWildcatMarketRevolving.drawnAmount.selector;
  bytes4 internal constant _TEMPORARY_EXCESS_RESERVE_RATIO_SELECTOR =
    bytes4(keccak256('temporaryExcessReserveRatio(address)'));
  uint256 internal constant _VERSION_SELECTOR = uint32(IVersionedContract.version.selector);

  function _isV2Market(address market) internal view returns (bool isV2) {
    uint256 selector = _VERSION_SELECTOR;
    assembly ('memory-safe') {
      let ptr := mload(0x40)
      mstore(ptr, shl(224, selector))
      let success := staticcall(gas(), market, ptr, 4, ptr, 0x60)
      let size := returndatasize()
      if iszero(success) {
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
      if lt(size, 0x40) {
        revert(0, 0)
      }
      if iszero(eq(mload(ptr), 0x20)) {
        revert(0, 0)
      }
      let length := mload(add(ptr, 0x20))
      if length {
        if lt(size, 0x60) {
          revert(0, 0)
        }
        isV2 := eq(byte(0, mload(add(ptr, 0x40))), 0x32)
      }
    }
  }

  function fill(MarketData memory data, WildcatMarket market) internal view {
    data.marketToken.fill(address(market));
    data.underlyingToken.fill(market.asset());
    if (!_isV2Market(address(market))) {
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
    data.hooks.fill(
      hooksAddress,
      IHooksFactory(data.hooksFactory),
      address(0),
      data.hooksConfig.kind
    );
  }

  function fill(MarketDataV2_5 memory data, WildcatMarket market) internal view {
    data.market.fill(market);
    data.borrowerPrincipal = market.borrowerPrincipal();
    data.pendingBorrower = market.pendingBorrower();
    data.pendingBorrowerPrincipal = market.pendingBorrowerPrincipal();
    data.borrowerIdentityRegistry = market.borrowerIdentityRegistry();
    _tryFillOptionalUint(data.commitmentFeeBips, address(market), _COMMITMENT_FEE_BIPS_SELECTOR);
    _tryFillOptionalUint(data.drawnAmount, address(market), _DRAWN_AMOUNT_SELECTOR);
  }

  function fillMarketsData(
    address[] memory markets
  ) internal view returns (MarketData[] memory data) {
    data = new MarketData[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]));
    }
  }

  function fillMarketsDataV2(
    address[] memory markets
  ) internal view returns (MarketDataV2_5[] memory data) {
    data = new MarketDataV2_5[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]));
    }
  }

  function _tryFillOptionalUint(
    OptionalUintDataV2_5 memory data,
    address target,
    bytes4 selector
  ) internal view {
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      let ptr := mload(0x40)
      mstore(ptr, shl(224, selectorWord))
      let success := staticcall(gas(), target, ptr, 4, ptr, 0x20)
      if and(success, iszero(lt(returndatasize(), 0x20))) {
        mstore(data, 1)
        mstore(add(data, 0x20), mload(ptr))
      }
    }
  }

  function fillTemporaryExcessReserveRatio(MarketData memory data) internal view {
    address marketAddress = data.marketToken.token;
    address hooksAddress = data.hooks.hooksAddress;
    uint256 selectorWord = uint32(_TEMPORARY_EXCESS_RESERVE_RATIO_SELECTOR);
    bool success;
    uint256 originalAnnualInterestBips;
    uint256 originalReserveRatioBips;
    uint256 temporaryReserveRatioExpiry;
    assembly ('memory-safe') {
      let ptr := mload(0x40)
      mstore(ptr, shl(224, selectorWord))
      mstore(add(ptr, 4), marketAddress)
      success := staticcall(gas(), hooksAddress, ptr, 0x24, ptr, 0x60)
      success := and(success, iszero(lt(returndatasize(), 0x60)))
      if success {
        originalAnnualInterestBips := mload(ptr)
        originalReserveRatioBips := mload(add(ptr, 0x20))
        temporaryReserveRatioExpiry := mload(add(ptr, 0x40))
      }
    }
    if (!success) {
      return;
    }
    data.originalAnnualInterestBips = originalAnnualInterestBips;
    data.originalReserveRatioBips = originalReserveRatioBips;
    data.temporaryReserveRatioExpiry = temporaryReserveRatioExpiry;
    data.temporaryReserveRatio = data.temporaryReserveRatioExpiry > 0;
  }

  function fillState(MarketData memory data) internal view {
    WildcatMarket market = WildcatMarket(data.marketToken.token);
    data.unpaidWithdrawalBatchExpiries = market.getUnpaidBatchExpiries();
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
    LenderAccountQuery calldata query
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

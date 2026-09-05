// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../IHooksFactory.sol';
import './FactoryScopedHooksTemplateData.sol';
import './HooksDataForBorrower.sol';
import './HooksInstanceData.sol';
import './MarketData.sol';
import './MarketLiveData.sol';
import './TokenData.sol';
import './interfaces/IMarketLensAggregator.sol';
import './interfaces/IMarketLensCore.sol';
import './interfaces/IMarketLensLive.sol';

/// @title Wildcat market lens
/// @notice stable read facade over separate core, aggregation, and live-data helpers.
/// @dev each function forwards its original calldata by `staticcall` and passes the helper's exact
///      result through. splitting the implementation keeps the facade under the code-size limit.
contract MarketLens is IMarketLensAggregator, IMarketLensCore, IMarketLensLive {
  /// @dev Declared for ABI completeness: raised in the data-filling libraries
  ///      and bubbled up to callers through `_delegate`.
  error NotV2Market();

  /// @notice ArchController configured for this facade.
  WildcatArchController public immutable archController;
  /// @notice default hooks factory configured for this facade.
  IHooksFactory public immutable hooksFactory;
  /// @notice helper used for strict market, token, and lender reads.
  IMarketLensCore public immutable coreHelper;
  /// @notice helper used for cross-factory aggregation reads.
  IMarketLensAggregator public immutable aggregationHelper;
  /// @notice helper used for compact accrued-state reads.
  IMarketLensLive public immutable liveHelper;

  constructor(
    address _archController,
    address _hooksFactory,
    address _coreHelper,
    address _aggregationHelper,
    address _liveHelper
  ) {
    archController = WildcatArchController(_archController);
    hooksFactory = IHooksFactory(_hooksFactory);
    coreHelper = IMarketLensCore(_coreHelper);
    aggregationHelper = IMarketLensAggregator(_aggregationHelper);
    liveHelper = IMarketLensLive(_liveHelper);
  }

  // ========================================================================== //
  //                              Internal helpers                              //
  // ========================================================================== //

  /// @dev forwards the original calldata to `helper` and passes its complete result through.
  ///      the helper has to expose the same function signature. there is no fallback routing.
  function _delegate(address helper) internal view {
    assembly ('memory-safe') {
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize())
      let success := staticcall(gas(), helper, ptr, calldatasize(), 0, 0)
      let size := returndatasize()
      returndatacopy(ptr, 0, size)
      if iszero(success) {
        revert(ptr, size)
      }
      return(ptr, size)
    }
  }

  function _delegateCoreHelper() internal view {
    _delegate(address(coreHelper));
  }

  function _delegateAggregationHelper() internal view {
    _delegate(address(aggregationHelper));
  }

  function _delegateLiveHelper() internal view {
    _delegate(address(liveHelper));
  }

  // ========================================================================== //
  //                         All hooks data for borrower                        //
  // ========================================================================== //

  function getHooksDataForBorrower(
    address borrower
  ) external view returns (HooksDataForBorrower memory data) {
    _delegateAggregationHelper();
  }

  function getHooksDataForBorrower(
    address hooksFactoryAddress,
    address borrower
  ) external view returns (HooksDataForBorrower memory data) {
    _delegateAggregationHelper();
  }

  function getAggregatedHooksDataForBorrower(
    address borrower
  ) external view returns (HooksDataForBorrower memory data) {
    _delegateAggregationHelper();
  }

  // ========================================================================== //
  //                        Hooks instances for borrower                        //
  // ========================================================================== //

  function getHooksInstancesForBorrower(
    address borrower
  ) external view returns (HooksInstanceData[] memory arr) {
    _delegateAggregationHelper();
  }

  function getHooksInstancesForBorrower(
    address hooksFactoryAddress,
    address borrower
  ) external view returns (HooksInstanceData[] memory arr) {
    _delegateAggregationHelper();
  }

  /// @inheritdoc IMarketLensAggregator
  function getAggregatedHooksInstancesForBorrower(
    address borrower
  ) external view returns (HooksInstanceData[] memory arr) {
    _delegateAggregationHelper();
  }

  // ========================================================================== //
  //                        Hooks templates for borrower                        //
  // ========================================================================== //

  function getHooksTemplateForBorrower(
    address borrower,
    address hooksTemplate
  ) external view returns (HooksTemplateData memory data) {
    _delegateAggregationHelper();
  }

  function getHooksTemplateForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address hooksTemplate
  ) external view returns (HooksTemplateData memory data) {
    _delegateAggregationHelper();
  }

  function getHooksTemplatesForBorrower(
    address borrower,
    address[] memory hooksTemplates
  ) external view returns (HooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  function getHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address[] memory hooksTemplates
  ) external view returns (HooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  function getAllHooksTemplatesForBorrower(
    address borrower
  ) external view returns (HooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  function getAllHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower
  ) external view returns (HooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  /// @inheritdoc IMarketLensAggregator
  function getAggregatedAllHooksTemplatesForBorrower(
    address borrower
  ) external view returns (HooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  /// @inheritdoc IMarketLensAggregator
  function getAggregatedHooksTemplatesForBorrowerWithFactory(
    address borrower
  ) external view returns (FactoryScopedHooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  // ========================================================================== //
  //                                 Token info                                 //
  // ========================================================================== //

  function getTokenInfo(address token) external view returns (TokenMetadata memory info) {
    _delegateCoreHelper();
  }

  function getTokensInfo(
    address[] calldata tokens
  ) external view returns (TokenMetadata[] memory info) {
    _delegateCoreHelper();
  }

  // ========================================================================== //
  //                                   Markets                                  //
  // ========================================================================== //

  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
    _delegateAggregationHelper();
  }

  function getMarketsForHooksTemplateCount(
    address hooksFactoryAddress,
    address hooksTemplate
  ) external view returns (uint256) {
    _delegateAggregationHelper();
  }

  function getAggregatedMarketsForHooksTemplateCount(
    address hooksTemplate
  ) external view returns (uint256 count) {
    _delegateAggregationHelper();
  }

  function getMarketData(address market) external view returns (MarketData memory data) {
    _delegateCoreHelper();
  }

  function getMarketsData(
    address[] calldata markets
  ) external view returns (MarketData[] memory data) {
    _delegateCoreHelper();
  }

  function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data) {
    _delegateCoreHelper();
  }

  function getMarketsDataV2(
    address[] calldata markets
  ) external view returns (MarketDataV2_5[] memory data) {
    _delegateCoreHelper();
  }

  function getPaginatedMarketsDataForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketData[] memory data) {
    _delegateAggregationHelper();
  }

  function getPaginatedMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketData[] memory data) {
    _delegateAggregationHelper();
  }

  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketDataV2_5[] memory data) {
    _delegateAggregationHelper();
  }

  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view returns (MarketDataV2_5[] memory data) {
    _delegateAggregationHelper();
  }

  function getAllMarketsDataForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketData[] memory data) {
    _delegateAggregationHelper();
  }

  function getAllMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  ) external view returns (MarketData[] memory data) {
    _delegateAggregationHelper();
  }

  function getAllMarketsDataV2ForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketDataV2_5[] memory data) {
    _delegateAggregationHelper();
  }

  function getAllMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  ) external view returns (MarketDataV2_5[] memory data) {
    _delegateAggregationHelper();
  }

  function getAggregatedAllMarketsDataForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketData[] memory data) {
    _delegateAggregationHelper();
  }

  function getAggregatedAllMarketsDataV2ForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketDataV2_5[] memory data) {
    _delegateAggregationHelper();
  }

  // ========================================================================== //
  //                              Live market reads                             //
  // ========================================================================== //

  function getMarketsLiveDataV2(
    address[] calldata markets
  ) external view returns (MarketLiveDataV2_5[] memory data) {
    _delegateLiveHelper();
  }

  function getMarketsLiveDataWithLenderStatusV2(
    address lender,
    address[] calldata markets
  ) external view returns (MarketLiveDataWithLenderStatusV2_5[] memory data) {
    _delegateLiveHelper();
  }

  // ========================================================================== //
  //                         Markets with lender status                         //
  // ========================================================================== //

  function getMarketDataWithLenderStatus(
    address lender,
    address market
  ) external view returns (MarketDataWithLenderStatus memory data) {
    _delegateCoreHelper();
  }

  function getMarketsDataWithLenderStatus(
    address lender,
    address[] calldata markets
  ) external view returns (MarketDataWithLenderStatus[] memory data) {
    _delegateCoreHelper();
  }

  // ========================================================================== //
  //                        Lender status in market only                        //
  // ========================================================================== //

  function getLenderAccountData(
    address lender,
    address market
  ) external view returns (LenderAccountData memory data) {
    _delegateCoreHelper();
  }

  function getLenderAccountData(
    address lender,
    address[] calldata markets
  ) external view returns (LenderAccountData[] memory arr) {
    _delegateCoreHelper();
  }

  function getLenderAccountsData(
    address marketAddress,
    address[] calldata lenders
  ) external view returns (LenderAccountData[] memory data) {
    _delegateCoreHelper();
  }

  function queryLenderAccount(
    LenderAccountQuery calldata query
  ) external view returns (LenderAccountQueryResult memory result) {
    _delegateCoreHelper();
  }

  function queryLenderAccounts(
    LenderAccountQuery[] calldata queries
  ) external view returns (LenderAccountQueryResult[] memory result) {
    _delegateCoreHelper();
  }

  // ========================================================================== //
  //                          Withdrawal batch queries                          //
  // ========================================================================== //

  function getWithdrawalBatchData(
    address market,
    uint32 expiry
  ) external view returns (WithdrawalBatchData memory data) {
    _delegateCoreHelper();
  }

  function getWithdrawalBatchesData(
    address market,
    uint32[] calldata expiries
  ) external view returns (WithdrawalBatchData[] memory data) {
    _delegateCoreHelper();
  }

  // ========================================================================== //
  //                    Withdrawal batch queries with account                   //
  // ========================================================================== //

  function getWithdrawalBatchesDataWithLenderStatus(
    address market,
    uint32[] calldata expiries,
    address lender
  ) external view returns (WithdrawalBatchDataWithLenderStatus[] memory statuses) {
    _delegateCoreHelper();
  }

  function getWithdrawalBatchDataWithLenderStatus(
    address market,
    uint32 expiry,
    address lender
  ) external view returns (WithdrawalBatchDataWithLenderStatus memory status) {
    _delegateCoreHelper();
  }

  function getWithdrawalBatchDataWithLendersStatus(
    address market,
    uint32 expiry,
    address[] calldata lenders
  )
    external
    view
    returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses)
  {
    _delegateCoreHelper();
  }
}

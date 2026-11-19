// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketLens
//  \ ^ /   Read facade over core, aggregation, and live-data helpers.
//    V
//
//  SETUP
//  constructor(...)
//
//  BORROWER HOOKS DATA
//  getHooksDataForBorrower(...)
//  getHooksDataForBorrower(...)
//  getAggregatedHooksDataForBorrower(...)
//
//  HOOKS INSTANCES
//  getHooksInstancesForBorrower(...)
//  getHooksInstancesForBorrower(...)
//  getAggregatedHooksInstancesForBorrower(...)
//
//  HOOKS TEMPLATES
//  getHooksTemplateForBorrower(...)
//  getHooksTemplateForBorrower(...)
//  getHooksTemplatesForBorrower(...)
//  getHooksTemplatesForBorrower(...)
//  getAllHooksTemplatesForBorrower(...)
//  getAllHooksTemplatesForBorrower(...)
//  getAggregatedAllHooksTemplatesForBorrower(...)
//  getAggregatedHooksTemplatesForBorrowerWithFactory(...)
//
//  TOKEN METADATA
//  getTokenInfo(...)
//  getTokensInfo(...)
//
//  MARKET DATA
//  getMarketData(...)
//  getMarketsData(...)
//  getMarketDataV2(...)
//  getMarketsDataV2(...)
//
//  TEMPLATE MARKETS
//  getMarketsForHooksTemplateCount(...)
//  getMarketsForHooksTemplateCount(...)
//  getAggregatedMarketsForHooksTemplateCount(...)
//  getPaginatedMarketsDataForHooksTemplate(...)
//  getPaginatedMarketsDataForHooksTemplate(...)
//  getPaginatedMarketsDataV2ForHooksTemplate(...)
//  getPaginatedMarketsDataV2ForHooksTemplate(...)
//  getAllMarketsDataForHooksTemplate(...)
//  getAllMarketsDataForHooksTemplate(...)
//  getAllMarketsDataV2ForHooksTemplate(...)
//  getAllMarketsDataV2ForHooksTemplate(...)
//  getAggregatedAllMarketsDataForHooksTemplate(...)
//  getAggregatedAllMarketsDataV2ForHooksTemplate(...)
//
//  LIVE MARKET DATA
//  getMarketsLiveDataV2(...)
//  getMarketsLiveDataWithLenderStatusV2(...)
//
//  LENDER DATA
//  getMarketDataWithLenderStatus(...)
//  getMarketsDataWithLenderStatus(...)
//  getLenderAccountData(...)
//  getLenderAccountData(...)
//  getLenderAccountsData(...)
//  queryLenderAccount(...)
//  queryLenderAccounts(...)
//
//  WITHDRAWAL BATCHES
//  getWithdrawalBatchData(...)
//  getWithdrawalBatchesData(...)
//  getWithdrawalBatchDataWithLenderStatus(...)
//  getWithdrawalBatchesDataWithLenderStatus(...)
//  getWithdrawalBatchDataWithLendersStatus(...)
//
//  QUERY FORWARDING
//  _delegateCoreHelper()
//  _delegateAggregationHelper()
//  _delegateLiveHelper()
//  _delegate(...)
// ═════

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

// ┌─ MarketLens ───────────────────────────────────────────────────────────────
/// @title Wildcat market lens
///
/// @notice read facade over separate core, aggregation, and live-data helpers.
///
/// @dev each function forwards its original calldata by `staticcall` and passes the helper's exact
///      result through. splitting the implementation keeps the facade under the code-size limit.
contract MarketLens is IMarketLensAggregator, IMarketLensCore, IMarketLensLive {
  /// @dev declared for ABI completeness: raised in the data-filling libraries
  ///      and bubbled up to callers through `_delegate`.
  error NotV2Market();
  error InvalidParameterConstraints();

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

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
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

  // ░░▒▒▓▓██ [ BORROWER HOOKS DATA ] ──────────────────────────────────────────

  // ┌─ getHooksDataForBorrower ─────
  function getHooksDataForBorrower(address borrower) external view returns (HooksDataForBorrower memory data) {
    _delegateAggregationHelper();
  }

  // ┌─ getHooksDataForBorrower ─────
  function getHooksDataForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    external
    view
    returns (HooksDataForBorrower memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedHooksDataForBorrower ─────
  function getAggregatedHooksDataForBorrower(address borrower)
    external
    view
    returns (HooksDataForBorrower memory data)
  {
    _delegateAggregationHelper();
  }

  // ░░▒▒▓▓██ [ HOOKS INSTANCES ] ──────────────────────────────────────────────

  // ┌─ getHooksInstancesForBorrower ─────
  function getHooksInstancesForBorrower(address borrower) external view returns (HooksInstanceData[] memory arr) {
    _delegateAggregationHelper();
  }

  // ┌─ getHooksInstancesForBorrower ─────
  function getHooksInstancesForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    external
    view
    returns (HooksInstanceData[] memory arr)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedHooksInstancesForBorrower ─────
  /// @inheritdoc IMarketLensAggregator
  function getAggregatedHooksInstancesForBorrower(address borrower)
    external
    view
    returns (HooksInstanceData[] memory arr)
  {
    _delegateAggregationHelper();
  }

  // ░░▒▒▓▓██ [ HOOKS TEMPLATES ] ──────────────────────────────────────────────

  // ┌─ getHooksTemplateForBorrower ─────
  function getHooksTemplateForBorrower(
    address borrower,
    address hooksTemplate
  )
    external
    view
    returns (HooksTemplateData memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getHooksTemplateForBorrower ─────
  function getHooksTemplateForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address hooksTemplate
  )
    external
    view
    returns (HooksTemplateData memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getHooksTemplatesForBorrower ─────
  function getHooksTemplatesForBorrower(
    address borrower,
    address[] memory hooksTemplates
  )
    external
    view
    returns (HooksTemplateData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getHooksTemplatesForBorrower ─────
  function getHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address[] memory hooksTemplates
  )
    external
    view
    returns (HooksTemplateData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAllHooksTemplatesForBorrower ─────
  function getAllHooksTemplatesForBorrower(address borrower) external view returns (HooksTemplateData[] memory data) {
    _delegateAggregationHelper();
  }

  // ┌─ getAllHooksTemplatesForBorrower ─────
  function getAllHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    external
    view
    returns (HooksTemplateData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedAllHooksTemplatesForBorrower ─────
  /// @inheritdoc IMarketLensAggregator
  function getAggregatedAllHooksTemplatesForBorrower(address borrower)
    external
    view
    returns (HooksTemplateData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedHooksTemplatesForBorrowerWithFactory ─────
  /// @inheritdoc IMarketLensAggregator
  function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
    external
    view
    returns (FactoryScopedHooksTemplateData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ░░▒▒▓▓██ [ TOKEN METADATA ] ───────────────────────────────────────────────

  // ┌─ getTokenInfo ─────
  function getTokenInfo(address token) external view returns (TokenMetadata memory info) {
    _delegateCoreHelper();
  }

  // ┌─ getTokensInfo ─────
  function getTokensInfo(address[] calldata tokens) external view returns (TokenMetadata[] memory info) {
    _delegateCoreHelper();
  }

  // ░░▒▒▓▓██ [ MARKET DATA ] ──────────────────────────────────────────────────

  // ┌─ getMarketData ─────
  function getMarketData(address market) external view returns (MarketData memory data) {
    _delegateCoreHelper();
  }

  // ┌─ getMarketsData ─────
  function getMarketsData(address[] calldata markets) external view returns (MarketData[] memory data) {
    _delegateCoreHelper();
  }

  // ┌─ getMarketDataV2 ─────
  function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data) {
    _delegateCoreHelper();
  }

  // ┌─ getMarketsDataV2 ─────
  function getMarketsDataV2(address[] calldata markets) external view returns (MarketDataV2_5[] memory data) {
    _delegateCoreHelper();
  }

  // ░░▒▒▓▓██ [ TEMPLATE MARKETS ] ─────────────────────────────────────────────

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
    _delegateAggregationHelper();
  }

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    external
    view
    returns (uint256)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedMarketsForHooksTemplateCount ─────
  function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count) {
    _delegateAggregationHelper();
  }

  // ┌─ getPaginatedMarketsDataForHooksTemplate ─────
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getPaginatedMarketsDataForHooksTemplate ─────
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getPaginatedMarketsDataV2ForHooksTemplate ─────
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getPaginatedMarketsDataV2ForHooksTemplate ─────
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAllMarketsDataForHooksTemplate ─────
  function getAllMarketsDataForHooksTemplate(address hooksTemplate) external view returns (MarketData[] memory data) {
    _delegateAggregationHelper();
  }

  // ┌─ getAllMarketsDataForHooksTemplate ─────
  function getAllMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    external
    view
    returns (MarketData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAllMarketsDataV2ForHooksTemplate ─────
  function getAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAllMarketsDataV2ForHooksTemplate ─────
  function getAllMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedAllMarketsDataForHooksTemplate ─────
  function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketData[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ┌─ getAggregatedAllMarketsDataV2ForHooksTemplate ─────
  function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    _delegateAggregationHelper();
  }

  // ░░▒▒▓▓██ [ LIVE MARKET DATA ] ─────────────────────────────────────────────

  // ┌─ getMarketsLiveDataV2 ─────
  function getMarketsLiveDataV2(address[] calldata markets) external view returns (MarketLiveDataV2_5[] memory data) {
    _delegateLiveHelper();
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
    _delegateLiveHelper();
  }

  // ░░▒▒▓▓██ [ LENDER DATA ] ──────────────────────────────────────────────────

  // ┌─ getMarketDataWithLenderStatus ─────
  function getMarketDataWithLenderStatus(
    address lender,
    address market
  )
    external
    view
    returns (MarketDataWithLenderStatus memory data)
  {
    _delegateCoreHelper();
  }

  // ┌─ getMarketsDataWithLenderStatus ─────
  function getMarketsDataWithLenderStatus(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (MarketDataWithLenderStatus[] memory data)
  {
    _delegateCoreHelper();
  }

  // ┌─ getLenderAccountData ─────
  function getLenderAccountData(address lender, address market) external view returns (LenderAccountData memory data) {
    _delegateCoreHelper();
  }

  // ┌─ getLenderAccountData ─────
  function getLenderAccountData(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (LenderAccountData[] memory arr)
  {
    _delegateCoreHelper();
  }

  // ┌─ getLenderAccountsData ─────
  function getLenderAccountsData(
    address marketAddress,
    address[] calldata lenders
  )
    external
    view
    returns (LenderAccountData[] memory data)
  {
    _delegateCoreHelper();
  }

  // ┌─ queryLenderAccount ─────
  function queryLenderAccount(LenderAccountQuery calldata query)
    external
    view
    returns (LenderAccountQueryResult memory result)
  {
    _delegateCoreHelper();
  }

  // ┌─ queryLenderAccounts ─────
  function queryLenderAccounts(LenderAccountQuery[] calldata queries)
    external
    view
    returns (LenderAccountQueryResult[] memory result)
  {
    _delegateCoreHelper();
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL BATCHES ] ───────────────────────────────────────────

  // ┌─ getWithdrawalBatchData ─────
  function getWithdrawalBatchData(
    address market,
    uint32 expiry
  )
    external
    view
    returns (WithdrawalBatchData memory data)
  {
    _delegateCoreHelper();
  }

  // ┌─ getWithdrawalBatchesData ─────
  function getWithdrawalBatchesData(
    address market,
    uint32[] calldata expiries
  )
    external
    view
    returns (WithdrawalBatchData[] memory data)
  {
    _delegateCoreHelper();
  }

  // ┌─ getWithdrawalBatchDataWithLenderStatus ─────
  function getWithdrawalBatchDataWithLenderStatus(
    address market,
    uint32 expiry,
    address lender
  )
    external
    view
    returns (WithdrawalBatchDataWithLenderStatus memory status)
  {
    _delegateCoreHelper();
  }

  // ┌─ getWithdrawalBatchesDataWithLenderStatus ─────
  function getWithdrawalBatchesDataWithLenderStatus(
    address market,
    uint32[] calldata expiries,
    address lender
  )
    external
    view
    returns (WithdrawalBatchDataWithLenderStatus[] memory statuses)
  {
    _delegateCoreHelper();
  }

  // ┌─ getWithdrawalBatchDataWithLendersStatus ─────
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

  // ░░▒▒▓▓██ [ QUERY FORWARDING ] ─────────────────────────────────────────────

  // ┌─ _delegateCoreHelper ─────
  function _delegateCoreHelper() internal view {
    _delegate(address(coreHelper));
  }

  // ┌─ _delegateAggregationHelper ─────
  function _delegateAggregationHelper() internal view {
    _delegate(address(aggregationHelper));
  }

  // ┌─ _delegateLiveHelper ─────
  function _delegateLiveHelper() internal view {
    _delegate(address(liveHelper));
  }

  // ┌─ _delegate ─────
  /// @dev forward the original calldata to `helper` and pass its complete result through.
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
}

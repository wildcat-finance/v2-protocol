// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../IHooksFactory.sol";
import "./FactoryScopedHooksTemplateData.sol";
import "./HooksDataForBorrower.sol";
import "./HooksInstanceData.sol";
import "./MarketData.sol";
import "./MarketLiveData.sol";
import "./TokenData.sol";
import "./interfaces/IMarketLensAggregator.sol";
import "./interfaces/IMarketLensCore.sol";
import "./interfaces/IMarketLensLive.sol";

contract MarketLens {
    WildcatArchController public immutable archController;
    IHooksFactory public immutable hooksFactory;
    IMarketLensCore public immutable coreHelper;
    IMarketLensAggregator public immutable aggregationHelper;
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

    function _asFactory(address hooksFactoryAddress) internal pure returns (IHooksFactory) {
        return IHooksFactory(hooksFactoryAddress);
    }

    function _delegateCoreHelper() internal view {
        address helper = address(coreHelper);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let success := staticcall(gas(), helper, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            if iszero(success) { revert(ptr, size) }
            return(ptr, size)
        }
    }

    function _delegateAggregationHelper() internal view {
        address helper = address(aggregationHelper);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let success := staticcall(gas(), helper, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            if iszero(success) { revert(ptr, size) }
            return(ptr, size)
        }
    }

    function _delegateLiveHelper() internal view {
        address helper = address(liveHelper);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let success := staticcall(gas(), helper, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            if iszero(success) { revert(ptr, size) }
            return(ptr, size)
        }
    }

    function _getMarketsDataInternal(address[] memory markets) internal view returns (MarketData[] memory data) {
        data = new MarketData[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
    }

    function _getMarketsDataV2Internal(address[] memory markets) internal view returns (MarketDataV2_5[] memory data) {
        data = new MarketDataV2_5[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
    }

    // ========================================================================== //
    //                         All hooks data for borrower                        //
    // ========================================================================== //

    function getHooksDataForBorrower(address borrower) public view returns (HooksDataForBorrower memory data) {
        return getHooksDataForBorrower(address(hooksFactory), borrower);
    }

    function getHooksDataForBorrower(address hooksFactoryAddress, address borrower)
        public
        view
        returns (HooksDataForBorrower memory data)
    {
        data.fill(archController, _asFactory(hooksFactoryAddress), borrower);
    }

    function getAggregatedHooksDataForBorrower(address borrower)
        external
        view
        returns (HooksDataForBorrower memory data)
    {
        _delegateAggregationHelper();
    }

    // ========================================================================== //
    //                        Hooks instances for borrower                        //
    // ========================================================================== //

    function getHooksInstancesForBorrower(address borrower) public view returns (HooksInstanceData[] memory arr) {
        return getHooksInstancesForBorrower(address(hooksFactory), borrower);
    }

    function getHooksInstancesForBorrower(address hooksFactoryAddress, address borrower)
        public
        view
        returns (HooksInstanceData[] memory arr)
    {
        IHooksFactory factory = _asFactory(hooksFactoryAddress);
        address[] memory hooksInstances = factory.getHooksInstancesForBorrower(borrower);
        arr = new HooksInstanceData[](hooksInstances.length);
        for (uint256 i; i < hooksInstances.length; i++) {
            arr[i].fill(hooksInstances[i], factory);
        }
    }

    // Dedupes by hooks instance address while preserving first-seen order:
    // controller order from ArchController, then per-factory instance order.
    function getAggregatedHooksInstancesForBorrower(address borrower)
        external
        view
        returns (HooksInstanceData[] memory arr)
    {
        _delegateAggregationHelper();
    }

    // ========================================================================== //
    //                        Hooks templates for borrower                        //
    // ========================================================================== //

    function getHooksTemplateForBorrower(address borrower, address hooksTemplate)
        public
        view
        returns (HooksTemplateData memory data)
    {
        return getHooksTemplateForBorrower(address(hooksFactory), borrower, hooksTemplate);
    }

    function getHooksTemplateForBorrower(address hooksFactoryAddress, address borrower, address hooksTemplate)
        public
        view
        returns (HooksTemplateData memory data)
    {
        data.fill(_asFactory(hooksFactoryAddress), hooksTemplate, borrower);
    }

    function getHooksTemplatesForBorrower(address borrower, address[] memory hooksTemplates)
        public
        view
        returns (HooksTemplateData[] memory data)
    {
        return getHooksTemplatesForBorrower(address(hooksFactory), borrower, hooksTemplates);
    }

    function getHooksTemplatesForBorrower(
        address hooksFactoryAddress,
        address borrower,
        address[] memory hooksTemplates
    ) public view returns (HooksTemplateData[] memory data) {
        IHooksFactory factory = _asFactory(hooksFactoryAddress);
        data = new HooksTemplateData[](hooksTemplates.length);
        for (uint256 i; i < hooksTemplates.length; i++) {
            data[i].fill(factory, hooksTemplates[i], borrower);
        }
    }

    function getAllHooksTemplatesForBorrower(address borrower) public view returns (HooksTemplateData[] memory data) {
        return getAllHooksTemplatesForBorrower(address(hooksFactory), borrower);
    }

    function getAllHooksTemplatesForBorrower(address hooksFactoryAddress, address borrower)
        public
        view
        returns (HooksTemplateData[] memory data)
    {
        IHooksFactory factory = _asFactory(hooksFactoryAddress);
        address[] memory hooksTemplates = factory.getHooksTemplates();
        return getHooksTemplatesForBorrower(hooksFactoryAddress, borrower, hooksTemplates);
    }

    // Dedupes by hooks template address while preserving first-seen order:
    // controller order from ArchController, then per-factory template order.
    function getAggregatedAllHooksTemplatesForBorrower(address borrower)
        external
        view
        returns (HooksTemplateData[] memory data)
    {
        _delegateAggregationHelper();
    }

    // Returns one row per (factory, hooksTemplate) pair with factory-scoped template data.
    // Unlike `getAggregatedAllHooksTemplatesForBorrower`, this intentionally does not
    // dedupe across factories.
    function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
        external
        view
        returns (FactoryScopedHooksTemplateData[] memory data)
    {
        _delegateAggregationHelper();
    }

    // ========================================================================== //
    //                                 Token info                                 //
    // ========================================================================== //

    function getTokenInfo(address token) external view returns (TokenMetadata memory info) {
        _delegateCoreHelper();
    }

    function getTokensInfo(address[] memory tokens) external view returns (TokenMetadata[] memory info) {
        _delegateCoreHelper();
    }

    // ========================================================================== //
    //                                   Markets                                  //
    // ========================================================================== //

    function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
        return getMarketsForHooksTemplateCount(address(hooksFactory), hooksTemplate);
    }

    function getMarketsForHooksTemplateCount(address hooksFactoryAddress, address hooksTemplate)
        public
        view
        returns (uint256)
    {
        return _asFactory(hooksFactoryAddress).getMarketsForHooksTemplateCount(hooksTemplate);
    }

    function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count) {
        _delegateAggregationHelper();
    }

    function getMarketData(address market) external view returns (MarketData memory data) {
        _delegateCoreHelper();
    }

    function getMarketsData(address[] memory markets) external view returns (MarketData[] memory data) {
        _delegateCoreHelper();
    }

    function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data) {
        _delegateCoreHelper();
    }

    function getMarketsDataV2(address[] memory markets) external view returns (MarketDataV2_5[] memory data) {
        _delegateCoreHelper();
    }

    function getPaginatedMarketsDataForHooksTemplate(address hooksTemplate, uint256 start, uint256 end)
        public
        view
        returns (MarketData[] memory data)
    {
        return getPaginatedMarketsDataForHooksTemplate(address(hooksFactory), hooksTemplate, start, end);
    }

    function getPaginatedMarketsDataForHooksTemplate(
        address hooksFactoryAddress,
        address hooksTemplate,
        uint256 start,
        uint256 end
    ) public view returns (MarketData[] memory data) {
        address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate, start, end);
        return _getMarketsDataInternal(markets);
    }

    function getPaginatedMarketsDataV2ForHooksTemplate(address hooksTemplate, uint256 start, uint256 end)
        public
        view
        returns (MarketDataV2_5[] memory data)
    {
        return getPaginatedMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate, start, end);
    }

    function getPaginatedMarketsDataV2ForHooksTemplate(
        address hooksFactoryAddress,
        address hooksTemplate,
        uint256 start,
        uint256 end
    ) public view returns (MarketDataV2_5[] memory data) {
        address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate, start, end);
        return _getMarketsDataV2Internal(markets);
    }

    function getAllMarketsDataForHooksTemplate(address hooksTemplate) external view returns (MarketData[] memory data) {
        return getAllMarketsDataForHooksTemplate(address(hooksFactory), hooksTemplate);
    }

    function getAllMarketsDataForHooksTemplate(address hooksFactoryAddress, address hooksTemplate)
        public
        view
        returns (MarketData[] memory data)
    {
        address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate);
        return _getMarketsDataInternal(markets);
    }

    function getAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2_5[] memory data)
    {
        return getAllMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate);
    }

    function getAllMarketsDataV2ForHooksTemplate(address hooksFactoryAddress, address hooksTemplate)
        public
        view
        returns (MarketDataV2_5[] memory data)
    {
        address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate);
        return _getMarketsDataV2Internal(markets);
    }

    function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketData[] memory data)
    {
        _delegateAggregationHelper();
    }

    function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2_5[] memory data)
    {
        _delegateAggregationHelper();
    }

    // ========================================================================== //
    //                              Live market reads                             //
    // ========================================================================== //

    function getMarketsLiveDataV2(address[] calldata markets) external view returns (MarketLiveDataV2_5[] memory data) {
        _delegateLiveHelper();
    }

    function getMarketsLiveDataWithLenderStatusV2(address lender, address[] calldata markets)
        external
        view
        returns (MarketLiveDataWithLenderStatusV2_5[] memory data)
    {
        _delegateLiveHelper();
    }

    // ========================================================================== //
    //                         Markets with lender status                         //
    // ========================================================================== //

    function getMarketDataWithLenderStatus(address lender, address market)
        external
        view
        returns (MarketDataWithLenderStatus memory data)
    {
        _delegateCoreHelper();
    }

    function getMarketsDataWithLenderStatus(address lender, address[] memory markets)
        external
        view
        returns (MarketDataWithLenderStatus[] memory data)
    {
        _delegateCoreHelper();
    }

    // ========================================================================== //
    //                        Lender status in market only                        //
    // ========================================================================== //

    function getLenderAccountData(address lender, address market)
        external
        view
        returns (LenderAccountData memory data)
    {
        _delegateCoreHelper();
    }

    function getLenderAccountData(address lender, address[] memory markets)
        external
        view
        returns (LenderAccountData[] memory arr)
    {
        _delegateCoreHelper();
    }

    function getLenderAccountsData(address marketAddress, address[] memory lenders)
        external
        view
        returns (LenderAccountData[] memory data)
    {
        _delegateCoreHelper();
    }

    function queryLenderAccount(LenderAccountQuery memory query)
        external
        view
        returns (LenderAccountQueryResult memory result)
    {
        _delegateCoreHelper();
    }

    function queryLenderAccounts(LenderAccountQuery[] memory queries)
        external
        view
        returns (LenderAccountQueryResult[] memory result)
    {
        _delegateCoreHelper();
    }

    // ========================================================================== //
    //                          Withdrawal batch queries                          //
    // ========================================================================== //
    // ========================================================================== //
    //                          Withdrawal batch queries                          //
    // ========================================================================== //

    function getWithdrawalBatchData(address market, uint32 expiry)
        external
        view
        returns (WithdrawalBatchData memory data)
    {
        _delegateCoreHelper();
    }

    function getWithdrawalBatchesData(address market, uint32[] memory expiries)
        external
        view
        returns (WithdrawalBatchData[] memory data)
    {
        _delegateCoreHelper();
    }

    // ========================================================================== //
    //                    Withdrawal batch queries with account                   //
    // ========================================================================== //
    // ========================================================================== //
    //                    Withdrawal batch queries with account                   //
    // ========================================================================== //

    function getWithdrawalBatchesDataWithLenderStatus(address market, uint32[] memory expiries, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus[] memory statuses)
    {
        _delegateCoreHelper();
    }

    function getWithdrawalBatchDataWithLenderStatus(address market, uint32 expiry, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus memory status)
    {
        _delegateCoreHelper();
    }

    function getWithdrawalBatchDataWithLendersStatus(address market, uint32 expiry, address[] calldata lenders)
        external
        view
        returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses)
    {
        _delegateCoreHelper();
    }
}

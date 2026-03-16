// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../IHooksFactory.sol";
import "./MarketData.sol";
import "./TokenData.sol";
import "./HooksInstanceData.sol";
import "./HooksDataForBorrower.sol";

struct FactoryScopedHooksTemplateData {
    address hooksFactory;
    HooksTemplateData hooksTemplateData;
}

contract MarketLens {
    WildcatArchController public immutable archController;
    IHooksFactory public immutable hooksFactory;

    constructor(address _archController, address _hooksFactory) {
        archController = WildcatArchController(_archController);
        hooksFactory = IHooksFactory(_hooksFactory);
    }

    // ========================================================================== //
    //                              Internal helpers                              //
    // ========================================================================== //

    function _asFactory(address hooksFactoryAddress) internal pure returns (IHooksFactory) {
        return IHooksFactory(hooksFactoryAddress);
    }

    function _containsAddress(address[] memory arr, uint256 length, address value) internal pure returns (bool) {
        for (uint256 i; i < length; i++) {
            if (arr[i] == value) return true;
        }
        return false;
    }

    function _containsHooksInstanceAddress(HooksInstanceData[] memory arr, uint256 length, address hooksAddress)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < length; i++) {
            if (arr[i].hooksAddress == hooksAddress) return true;
        }
        return false;
    }

    function _containsHooksTemplateAddress(HooksTemplateData[] memory arr, uint256 length, address hooksTemplate)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < length; i++) {
            if (arr[i].hooksTemplate == hooksTemplate) return true;
        }
        return false;
    }

    function _isHooksFactory(address candidate) internal view returns (bool isFactory) {
        try IHooksFactory(candidate).getHooksTemplatesCount() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _shrinkAddressArray(address[] memory arr, uint256 newLength) internal pure returns (address[] memory) {
        assembly {
            mstore(arr, newLength)
        }
        return arr;
    }

    function _shrinkHooksInstanceArray(HooksInstanceData[] memory arr, uint256 newLength)
        internal
        pure
        returns (HooksInstanceData[] memory)
    {
        assembly {
            mstore(arr, newLength)
        }
        return arr;
    }

    function _shrinkHooksTemplateArray(HooksTemplateData[] memory arr, uint256 newLength)
        internal
        pure
        returns (HooksTemplateData[] memory)
    {
        assembly {
            mstore(arr, newLength)
        }
        return arr;
    }

    function _shrinkFactoryScopedHooksTemplateArray(FactoryScopedHooksTemplateData[] memory arr, uint256 newLength)
        internal
        pure
        returns (FactoryScopedHooksTemplateData[] memory)
    {
        assembly {
            mstore(arr, newLength)
        }
        return arr;
    }

    function _getActiveHooksFactories() internal view returns (address[] memory factories) {
        address[] memory controllers = archController.getRegisteredControllers();
        address[] memory tmp = new address[](controllers.length + 1);
        uint256 count;

        for (uint256 i; i < controllers.length; i++) {
            address controller = controllers[i];
            if (_isHooksFactory(controller)) {
                tmp[count++] = controller;
            }
        }

        address defaultFactory = address(hooksFactory);
        if (!_containsAddress(tmp, count, defaultFactory) && _isHooksFactory(defaultFactory)) {
            tmp[count++] = defaultFactory;
        }

        return _shrinkAddressArray(tmp, count);
    }

    function _getAggregatedMarketsForHooksTemplate(address hooksTemplate)
        internal
        view
        returns (address[] memory markets)
    {
        address[] memory factories = _getActiveHooksFactories();
        uint256 numFactories = factories.length;
        if (numFactories == 0) {
            return new address[](0);
        }
        if (numFactories == 1) {
            try IHooksFactory(factories[0]).getMarketsForHooksTemplate(hooksTemplate) returns (
                address[] memory singleFactoryMarkets
            ) {
                return singleFactoryMarkets;
            } catch {
                return new address[](0);
            }
        }

        address[][] memory marketsByFactory = new address[][](numFactories);
        uint256 totalMarkets = 0;

        for (uint256 i = 0; i < numFactories; i++) {
            try IHooksFactory(factories[i]).getMarketsForHooksTemplate(hooksTemplate) returns (
                address[] memory factoryMarkets
            ) {
                marketsByFactory[i] = factoryMarkets;
                totalMarkets += factoryMarkets.length;
            } catch {}
        }

        markets = new address[](totalMarkets);
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < numFactories; i++) {
            address[] memory factoryMarkets = marketsByFactory[i];
            for (uint256 j = 0; j < factoryMarkets.length; j++) {
                address marketAddress = factoryMarkets[j];
                if (!_containsAddress(markets, uniqueCount, marketAddress)) {
                    markets[uniqueCount++] = marketAddress;
                }
            }
        }

        return _shrinkAddressArray(markets, uniqueCount);
    }

    function _collectHooksTemplatesByFactory(address[] memory factories)
        internal
        view
        returns (address[][] memory templatesByFactory, uint256 totalTemplates)
    {
        uint256 numFactories = factories.length;
        templatesByFactory = new address[][](numFactories);

        for (uint256 i = 0; i < numFactories; i++) {
            try IHooksFactory(factories[i]).getHooksTemplates() returns (address[] memory hooksTemplates) {
                templatesByFactory[i] = hooksTemplates;
                totalTemplates += hooksTemplates.length;
            } catch {}
        }
    }

    function _getAggregatedHooksInstancesForBorrowerInternal(address borrower, address[] memory factories)
        internal
        view
        returns (HooksInstanceData[] memory arr)
    {
        uint256 numFactories = factories.length;
        if (numFactories == 0) {
            return new HooksInstanceData[](0);
        }
        if (numFactories == 1) {
            IHooksFactory factory = IHooksFactory(factories[0]);
            try factory.getHooksInstancesForBorrower(borrower) returns (address[] memory hooksInstances) {
                arr = new HooksInstanceData[](hooksInstances.length);
                for (uint256 i = 0; i < hooksInstances.length; i++) {
                    arr[i].fill(hooksInstances[i], factory);
                }
                return arr;
            } catch {
                return new HooksInstanceData[](0);
            }
        }

        address[][] memory hooksInstancesByFactory = new address[][](numFactories);
        uint256 totalInstances = 0;

        for (uint256 i = 0; i < numFactories; i++) {
            try IHooksFactory(factories[i]).getHooksInstancesForBorrower(borrower) returns (
                address[] memory hooksInstances
            ) {
                hooksInstancesByFactory[i] = hooksInstances;
                totalInstances += hooksInstances.length;
            } catch {}
        }

        arr = new HooksInstanceData[](totalInstances);
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < numFactories; i++) {
            IHooksFactory factory = IHooksFactory(factories[i]);
            address[] memory hooksInstances = hooksInstancesByFactory[i];
            for (uint256 j = 0; j < hooksInstances.length; j++) {
                address hooksAddress = hooksInstances[j];
                if (!_containsHooksInstanceAddress(arr, uniqueCount, hooksAddress)) {
                    arr[uniqueCount].fill(hooksAddress, factory);
                    uniqueCount++;
                }
            }
        }

        return _shrinkHooksInstanceArray(arr, uniqueCount);
    }

    function _getAggregatedAllHooksTemplatesForBorrowerInternal(address borrower, address[] memory factories)
        internal
        view
        returns (HooksTemplateData[] memory data)
    {
        uint256 numFactories = factories.length;
        if (numFactories == 0) {
            return new HooksTemplateData[](0);
        }
        if (numFactories == 1) {
            IHooksFactory factory = IHooksFactory(factories[0]);
            try factory.getHooksTemplates() returns (address[] memory hooksTemplates) {
                data = new HooksTemplateData[](hooksTemplates.length);
                for (uint256 i = 0; i < hooksTemplates.length; i++) {
                    data[i].fill(factory, hooksTemplates[i], borrower);
                }
                return data;
            } catch {
                return new HooksTemplateData[](0);
            }
        }

        (address[][] memory templatesByFactory, uint256 totalTemplates) = _collectHooksTemplatesByFactory(factories);

        data = new HooksTemplateData[](totalTemplates);
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < numFactories; i++) {
            IHooksFactory factory = IHooksFactory(factories[i]);
            address[] memory hooksTemplates = templatesByFactory[i];
            for (uint256 j = 0; j < hooksTemplates.length; j++) {
                address hooksTemplate = hooksTemplates[j];
                if (!_containsHooksTemplateAddress(data, uniqueCount, hooksTemplate)) {
                    data[uniqueCount].fill(factory, hooksTemplate, borrower);
                    uniqueCount++;
                }
            }
        }

        return _shrinkHooksTemplateArray(data, uniqueCount);
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
        public
        view
        returns (HooksDataForBorrower memory data)
    {
        address[] memory factories = _getActiveHooksFactories();
        data.borrower = borrower;
        data.isRegisteredBorrower = archController.isRegisteredBorrower(borrower);
        data.hooksInstances = _getAggregatedHooksInstancesForBorrowerInternal(borrower, factories);
        data.hooksTemplates = _getAggregatedAllHooksTemplatesForBorrowerInternal(borrower, factories);
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
        public
        view
        returns (HooksInstanceData[] memory arr)
    {
        return _getAggregatedHooksInstancesForBorrowerInternal(borrower, _getActiveHooksFactories());
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
        public
        view
        returns (HooksTemplateData[] memory data)
    {
        return _getAggregatedAllHooksTemplatesForBorrowerInternal(borrower, _getActiveHooksFactories());
    }

    // Returns one row per (factory, hooksTemplate) pair with factory-scoped template data.
    // Unlike `getAggregatedAllHooksTemplatesForBorrower`, this intentionally does not
    // dedupe across factories.
    function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
        public
        view
        returns (FactoryScopedHooksTemplateData[] memory data)
    {
        address[] memory factories = _getActiveHooksFactories();
        uint256 numFactories = factories.length;
        if (numFactories == 0) {
            return new FactoryScopedHooksTemplateData[](0);
        }

        (address[][] memory templatesByFactory, uint256 totalTemplates) = _collectHooksTemplatesByFactory(factories);

        data = new FactoryScopedHooksTemplateData[](totalTemplates);
        uint256 count = 0;
        for (uint256 i = 0; i < numFactories; i++) {
            IHooksFactory factory = IHooksFactory(factories[i]);
            address[] memory hooksTemplates = templatesByFactory[i];
            for (uint256 j = 0; j < hooksTemplates.length; j++) {
                data[count].hooksFactory = factories[i];
                data[count].hooksTemplateData.fill(factory, hooksTemplates[j], borrower);
                count++;
            }
        }

        return _shrinkFactoryScopedHooksTemplateArray(data, count);
    }

    // ========================================================================== //
    //                                 Token info                                 //
    // ========================================================================== //

    function getTokenInfo(address token) public view returns (TokenMetadata memory info) {
        info.fill(token);
    }

    function getTokensInfo(address[] memory tokens) public view returns (TokenMetadata[] memory info) {
        info = new TokenMetadata[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            info[i].fill(tokens[i]);
        }
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

    function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
        return _getAggregatedMarketsForHooksTemplate(hooksTemplate).length;
    }

    function getMarketData(address market) public view returns (MarketData memory data) {
        data.fill(WildcatMarket(market));
    }

    function getMarketsData(address[] memory markets) public view returns (MarketData[] memory data) {
        data = new MarketData[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
    }

    function getMarketDataV2(address market) public view returns (MarketDataV2 memory data) {
        data.fill(WildcatMarket(market));
    }

    function getMarketsDataV2(address[] memory markets) public view returns (MarketDataV2[] memory data) {
        data = new MarketDataV2[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
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
        return getMarketsData(markets);
    }

    function getPaginatedMarketsDataV2ForHooksTemplate(address hooksTemplate, uint256 start, uint256 end)
        public
        view
        returns (MarketDataV2[] memory data)
    {
        return getPaginatedMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate, start, end);
    }

    function getPaginatedMarketsDataV2ForHooksTemplate(
        address hooksFactoryAddress,
        address hooksTemplate,
        uint256 start,
        uint256 end
    ) public view returns (MarketDataV2[] memory data) {
        address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate, start, end);
        return getMarketsDataV2(markets);
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
        return getMarketsData(markets);
    }

    function getAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2[] memory data)
    {
        return getAllMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate);
    }

    function getAllMarketsDataV2ForHooksTemplate(address hooksFactoryAddress, address hooksTemplate)
        public
        view
        returns (MarketDataV2[] memory data)
    {
        address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate);
        return getMarketsDataV2(markets);
    }

    function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketData[] memory data)
    {
        return getMarketsData(_getAggregatedMarketsForHooksTemplate(hooksTemplate));
    }

    function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2[] memory data)
    {
        return getMarketsDataV2(_getAggregatedMarketsForHooksTemplate(hooksTemplate));
    }

    // ========================================================================== //
    //                         Markets with lender status                         //
    // ========================================================================== //

    function getMarketDataWithLenderStatus(address lender, address market)
        public
        view
        returns (MarketDataWithLenderStatus memory data)
    {
        data.fill(WildcatMarket(market), lender);
    }

    function getMarketsDataWithLenderStatus(address lender, address[] memory markets)
        public
        view
        returns (MarketDataWithLenderStatus[] memory data)
    {
        data = new MarketDataWithLenderStatus[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]), lender);
        }
    }

    // ========================================================================== //
    //                        Lender status in market only                        //
    // ========================================================================== //

    function getLenderAccountData(address lender, address market)
        external
        view
        returns (LenderAccountData memory data)
    {
        data.fill(WildcatMarket(market), lender);
    }

  function getLenderAccountData(
    address lender,
    address[] memory markets
  ) external view returns (LenderAccountData[] memory arr) {
    arr = new LenderAccountData[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      arr[i].fill(WildcatMarket(markets[i]), lender);
    }
  }

  function getLenderAccountsData(
    address marketAddress,
    address[] memory lenders
  ) external view returns (LenderAccountData[] memory data) {
    data = new LenderAccountData[](lenders.length);
    WildcatMarket market = WildcatMarket(marketAddress);
    for (uint256 i; i < lenders.length; i++) {
      data[i].fill(market, lenders[i]);
    }
  }

    function queryLenderAccount(LenderAccountQuery memory query)
        external
        view
        returns (LenderAccountQueryResult memory result)
    {
        result.fill(query);
    }

    function queryLenderAccounts(LenderAccountQuery[] memory queries)
        external
        view
        returns (LenderAccountQueryResult[] memory result)
    {
        result = new LenderAccountQueryResult[](queries.length);
        for (uint256 i; i < queries.length; i++) {
            result[i].fill(queries[i]);
        }
    }

  // ========================================================================== //
  //                          Withdrawal batch queries                          //
  // ========================================================================== //

    function getWithdrawalBatchData(address market, uint32 expiry)
        public
        view
        returns (WithdrawalBatchData memory data)
    {
        data.fill(WildcatMarket(market), expiry);
    }

    function getWithdrawalBatchesData(address market, uint32[] memory expiries)
        public
        view
        returns (WithdrawalBatchData[] memory data)
    {
        data = new WithdrawalBatchData[](expiries.length);
        for (uint256 i; i < expiries.length; i++) {
            data[i].fill(WildcatMarket(market), expiries[i]);
        }
    }

  // ========================================================================== //
  //                    Withdrawal batch queries with account                   //
  // ========================================================================== //

    function getWithdrawalBatchesDataWithLenderStatus(address market, uint32[] memory expiries, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus[] memory statuses)
    {
        statuses = new WithdrawalBatchDataWithLenderStatus[](expiries.length);
        for (uint256 i; i < expiries.length; i++) {
            statuses[i].fill(WildcatMarket(market), expiries[i], lender);
        }
    }

    function getWithdrawalBatchDataWithLenderStatus(address market, uint32 expiry, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus memory status)
    {
        status.fill(WildcatMarket(market), expiry, lender);
    }

    function getWithdrawalBatchDataWithLendersStatus(address market, uint32 expiry, address[] calldata lenders)
        external
        view
        returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses)
    {
        batch.fill(WildcatMarket(market), expiry);

        statuses = new WithdrawalBatchLenderStatus[](lenders.length);
        for (uint256 i; i < lenders.length; i++) {
            statuses[i].fill(WildcatMarket(market), batch, lenders[i]);
        }
    }
}

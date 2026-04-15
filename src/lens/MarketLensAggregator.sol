// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../IHooksFactory.sol";
import "./FactoryScopedHooksTemplateData.sol";
import "./HooksDataForBorrower.sol";
import "./HooksInstanceData.sol";
import "./HooksTemplateData.sol";
import "./MarketData.sol";
import "./interfaces/IMarketLensAggregator.sol";

contract MarketLensAggregator {
    WildcatArchController public immutable archController;
    IHooksFactory public immutable hooksFactory;

    constructor(address _archController, address _hooksFactory) {
        archController = WildcatArchController(_archController);
        hooksFactory = IHooksFactory(_hooksFactory);
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

    function _collectHooksTemplatesByFactory(address[] memory factories)
        internal
        view
        returns (address[][] memory templatesByFactory, uint256 totalTemplates)
    {
        uint256 numFactories = factories.length;
        templatesByFactory = new address[][](numFactories);

        for (uint256 i; i < numFactories; i++) {
            try IHooksFactory(factories[i]).getHooksTemplates() returns (address[] memory hooksTemplates) {
                templatesByFactory[i] = hooksTemplates;
                totalTemplates += hooksTemplates.length;
            } catch {}
        }
    }

    function getActiveHooksFactories() public view returns (address[] memory factories) {
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

    function getAggregatedHooksInstancesForBorrowerWithFactories(address borrower, address[] memory factories)
        public
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
                for (uint256 i; i < hooksInstances.length; i++) {
                    arr[i].fill(hooksInstances[i], factory);
                }
                return arr;
            } catch {
                return new HooksInstanceData[](0);
            }
        }

        address[][] memory hooksInstancesByFactory = new address[][](numFactories);
        uint256 totalInstances = 0;

        for (uint256 i; i < numFactories; i++) {
            try IHooksFactory(factories[i]).getHooksInstancesForBorrower(borrower) returns (
                address[] memory hooksInstances
            ) {
                hooksInstancesByFactory[i] = hooksInstances;
                totalInstances += hooksInstances.length;
            } catch {}
        }

        arr = new HooksInstanceData[](totalInstances);
        uint256 uniqueCount = 0;
        for (uint256 i; i < numFactories; i++) {
            IHooksFactory factory = IHooksFactory(factories[i]);
            address[] memory hooksInstances = hooksInstancesByFactory[i];
            for (uint256 j; j < hooksInstances.length; j++) {
                address hooksAddress = hooksInstances[j];
                if (!_containsHooksInstanceAddress(arr, uniqueCount, hooksAddress)) {
                    arr[uniqueCount].fill(hooksAddress, factory);
                    uniqueCount++;
                }
            }
        }

        return _shrinkHooksInstanceArray(arr, uniqueCount);
    }

    function getAggregatedAllHooksTemplatesForBorrowerWithFactories(address borrower, address[] memory factories)
        public
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
                for (uint256 i; i < hooksTemplates.length; i++) {
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
        for (uint256 i; i < numFactories; i++) {
            IHooksFactory factory = IHooksFactory(factories[i]);
            address[] memory hooksTemplates = templatesByFactory[i];
            for (uint256 j; j < hooksTemplates.length; j++) {
                address hooksTemplate = hooksTemplates[j];
                if (!_containsHooksTemplateAddress(data, uniqueCount, hooksTemplate)) {
                    data[uniqueCount].fill(factory, hooksTemplate, borrower);
                    uniqueCount++;
                }
            }
        }

        return _shrinkHooksTemplateArray(data, uniqueCount);
    }

    function getAggregatedHooksDataForBorrower(address borrower)
        external
        view
        returns (HooksDataForBorrower memory data)
    {
        address[] memory factories = getActiveHooksFactories();
        data.borrower = borrower;
        data.isRegisteredBorrower = archController.isRegisteredBorrower(borrower);
        data.hooksInstances = getAggregatedHooksInstancesForBorrowerWithFactories(borrower, factories);
        data.hooksTemplates = getAggregatedAllHooksTemplatesForBorrowerWithFactories(borrower, factories);
    }

    function getAggregatedHooksInstancesForBorrower(address borrower)
        external
        view
        returns (HooksInstanceData[] memory arr)
    {
        return getAggregatedHooksInstancesForBorrowerWithFactories(borrower, getActiveHooksFactories());
    }

    function getAggregatedAllHooksTemplatesForBorrower(address borrower)
        external
        view
        returns (HooksTemplateData[] memory data)
    {
        return getAggregatedAllHooksTemplatesForBorrowerWithFactories(borrower, getActiveHooksFactories());
    }

    function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
        external
        view
        returns (FactoryScopedHooksTemplateData[] memory data)
    {
        address[] memory factories = getActiveHooksFactories();
        uint256 numFactories = factories.length;
        if (numFactories == 0) {
            return new FactoryScopedHooksTemplateData[](0);
        }

        (address[][] memory templatesByFactory, uint256 totalTemplates) = _collectHooksTemplatesByFactory(factories);

        data = new FactoryScopedHooksTemplateData[](totalTemplates);
        uint256 count = 0;
        for (uint256 i; i < numFactories; i++) {
            IHooksFactory factory = IHooksFactory(factories[i]);
            address[] memory hooksTemplates = templatesByFactory[i];
            for (uint256 j; j < hooksTemplates.length; j++) {
                data[count].hooksFactory = factories[i];
                data[count].hooksTemplateData.fill(factory, hooksTemplates[j], borrower);
                count++;
            }
        }

        return _shrinkFactoryScopedHooksTemplateArray(data, count);
    }

    function _getAggregatedMarketsForHooksTemplate(address hooksTemplate)
        internal
        view
        returns (address[] memory markets)
    {
        address[] memory factories = getActiveHooksFactories();
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

        for (uint256 i; i < numFactories; i++) {
            try IHooksFactory(factories[i]).getMarketsForHooksTemplate(hooksTemplate) returns (
                address[] memory factoryMarkets
            ) {
                marketsByFactory[i] = factoryMarkets;
                totalMarkets += factoryMarkets.length;
            } catch {}
        }

        markets = new address[](totalMarkets);
        uint256 uniqueCount = 0;
        for (uint256 i; i < numFactories; i++) {
            address[] memory factoryMarkets = marketsByFactory[i];
            for (uint256 j; j < factoryMarkets.length; j++) {
                address marketAddress = factoryMarkets[j];
                if (!_containsAddress(markets, uniqueCount, marketAddress)) {
                    markets[uniqueCount++] = marketAddress;
                }
            }
        }

        return _shrinkAddressArray(markets, uniqueCount);
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

    function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count) {
        return _getAggregatedMarketsForHooksTemplate(hooksTemplate).length;
    }

    function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketData[] memory data)
    {
        return _getMarketsDataInternal(_getAggregatedMarketsForHooksTemplate(hooksTemplate));
    }

    function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
        external
        view
        returns (MarketDataV2_5[] memory data)
    {
        return _getMarketsDataV2Internal(_getAggregatedMarketsForHooksTemplate(hooksTemplate));
    }
}

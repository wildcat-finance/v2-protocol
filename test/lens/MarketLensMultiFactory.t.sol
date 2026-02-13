// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import "../BaseMarketTest.sol";
import "src/HooksFactoryRevolving.sol";
import "src/IHooksFactoryRevolving.sol";
import "src/interfaces/IWildcatMarketRevolving.sol";
import "src/libraries/LibStoredInitCode.sol";
import "src/lens/MarketLens.sol";
import "src/market/WildcatMarketRevolving.sol";

contract MarketLensMultiFactoryTest is BaseMarketTest {
    MarketLens internal lens;
    IHooksFactoryRevolving internal hooksFactoryRevolving;
    WildcatMarketRevolving internal revolvingMarket;
    address internal revolvingHooksInstance;

    uint16 internal constant _COMMITMENT_FEE_BIPS = 321;

    function _storeRevolvingMarketInitCode() internal returns (address initCodeStorage, uint256 initCodeHash) {
        bytes memory marketInitCode = type(WildcatMarketRevolving).creationCode;
        initCodeHash = uint256(keccak256(marketInitCode));
        initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
    }

    function setUp() public override {
        super.setUp();

        lens = new MarketLens(address(archController), address(hooksFactory));

        (address marketTemplate, uint256 marketInitCodeHash) = _storeRevolvingMarketInitCode();
        hooksFactoryRevolving = new HooksFactoryRevolving(
            address(archController), address(sanctionsSentinel), marketTemplate, marketInitCodeHash
        );

        archController.registerControllerFactory(address(hooksFactoryRevolving));
        hooksFactoryRevolving.registerWithArchController();

        hooksFactoryRevolving.addHooksTemplate(
            hooksTemplate, "SingleBorrowerAccessControlHooks", address(0), address(0), 0, 0
        );
        hooksFactoryRevolving.addHooksTemplate(
            fixedTermHooksTemplate, "FixedTermLoanHooks", address(0), address(0), 0, 0
        );

        _deployRevolvingMarket();
    }

    function _deployRevolvingMarket() internal {
        vm.startPrank(borrower);

        revolvingHooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, "");

        DeployMarketInputs memory inputs = DeployMarketInputs({
            asset: address(asset),
            namePrefix: "Wildcat ",
            symbolPrefix: "WC",
            maxTotalSupply: parameters.maxTotalSupply,
            annualInterestBips: parameters.annualInterestBips,
            delinquencyFeeBips: parameters.delinquencyFeeBips,
            withdrawalBatchDuration: parameters.withdrawalBatchDuration,
            reserveRatioBips: parameters.reserveRatioBips,
            delinquencyGracePeriod: parameters.delinquencyGracePeriod,
            hooks: EmptyHooksConfig.setHooksAddress(revolvingHooksInstance)
        });

        bytes32 salt = bytes32((uint256(uint160(borrower)) << 96) | uint256(111));
        address revolvingMarketAddress = hooksFactoryRevolving.deployMarket(
            inputs,
            abi.encode(uint128(0), false, false),
            abi.encode(uint8(1), _COMMITMENT_FEE_BIPS),
            salt,
            address(0),
            0
        );

        vm.stopPrank();

        revolvingMarket = WildcatMarketRevolving(revolvingMarketAddress);
    }

    function _containsAddress(address[] memory values, address expected) internal pure returns (bool) {
        for (uint256 i; i < values.length; i++) {
            if (values[i] == expected) return true;
        }
        return false;
    }

    function _containsHooksInstance(HooksInstanceData[] memory values, address expected) internal pure returns (bool) {
        for (uint256 i; i < values.length; i++) {
            if (values[i].hooksAddress == expected) return true;
        }
        return false;
    }

    function _containsHooksTemplate(HooksTemplateData[] memory values, address expected) internal pure returns (bool) {
        for (uint256 i; i < values.length; i++) {
            if (values[i].hooksTemplate == expected) return true;
        }
        return false;
    }

    function test_getMarketDataV2_presenceFlagsForLegacyAndRevolving() external view {
        MarketDataV2 memory legacyData = lens.getMarketDataV2(address(market));
        assertEq(legacyData.market.hooksFactory, address(hooksFactory), "legacy hooksFactory");
        assertEq(legacyData.commitmentFeeBips.isPresent, false, "legacy commitment presence");
        assertEq(legacyData.drawnAmount.isPresent, false, "legacy drawn presence");

        MarketDataV2 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.market.hooksFactory, address(hooksFactoryRevolving), "revolving hooksFactory");
        assertEq(revolvingData.commitmentFeeBips.isPresent, true, "revolving commitment presence");
        assertEq(revolvingData.commitmentFeeBips.value, _COMMITMENT_FEE_BIPS, "revolving commitment value");
        assertEq(revolvingData.drawnAmount.isPresent, true, "revolving drawn presence");
        assertEq(revolvingData.drawnAmount.value, 0, "revolving drawn value");
    }

    function test_getMarketDataV2_treatsZeroAsValidWhenPresent() external {
        MarketDataV2 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.drawnAmount.isPresent, true, "drawn presence");
        assertEq(revolvingData.drawnAmount.value, 0, "drawn value should be zero");
    }

    function test_getMarketDataV2_fallbackWhenOptionalGetterIsMalformed() external {
        vm.mockCall(
            address(revolvingMarket),
            abi.encodeWithSelector(IWildcatMarketRevolving.commitmentFeeBips.selector),
            hex"01"
        );

        MarketDataV2 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.commitmentFeeBips.isPresent, false, "malformed commitment presence");
        assertEq(revolvingData.drawnAmount.isPresent, true, "drawn presence");
    }

    function test_factoryParameterizedBorrowerAndTemplateReads() external view {
        HooksInstanceData[] memory legacyInstances = lens.getHooksInstancesForBorrower(address(hooksFactory), borrower);
        assertEq(legacyInstances.length, 1, "legacy instances length");
        assertEq(legacyInstances[0].hooksAddress, address(hooks), "legacy hooks address");

        HooksInstanceData[] memory revolvingInstances =
            lens.getHooksInstancesForBorrower(address(hooksFactoryRevolving), borrower);
        assertEq(revolvingInstances.length, 1, "revolving instances length");
        assertEq(revolvingInstances[0].hooksAddress, revolvingHooksInstance, "revolving hooks address");

        HooksTemplateData memory templateData =
            lens.getHooksTemplateForBorrower(address(hooksFactoryRevolving), borrower, hooksTemplate);
        assertEq(templateData.hooksTemplate, hooksTemplate, "template address");
        assertEq(templateData.exists, true, "template exists");
        assertEq(templateData.totalMarkets, 1, "revolving template market count");

        HooksTemplateData[] memory templates =
            lens.getAllHooksTemplatesForBorrower(address(hooksFactoryRevolving), borrower);
        assertEq(templates.length, 2, "revolving templates length");
    }

    function test_aggregatedBorrowerAndTemplateReads() external view {
        HooksInstanceData[] memory instances = lens.getAggregatedHooksInstancesForBorrower(borrower);
        assertEq(instances.length, 2, "aggregated instances length");
        assertTrue(_containsHooksInstance(instances, address(hooks)), "contains legacy hooks instance");
        assertTrue(_containsHooksInstance(instances, revolvingHooksInstance), "contains revolving hooks instance");

        HooksTemplateData[] memory templates = lens.getAggregatedAllHooksTemplatesForBorrower(borrower);
        assertEq(templates.length, 2, "aggregated templates length");
        assertTrue(_containsHooksTemplate(templates, hooksTemplate), "contains access-control template");
        assertTrue(_containsHooksTemplate(templates, fixedTermHooksTemplate), "contains fixed-term template");

        HooksDataForBorrower memory hooksData = lens.getAggregatedHooksDataForBorrower(borrower);
        assertEq(hooksData.borrower, borrower, "borrower");
        assertEq(hooksData.isRegisteredBorrower, true, "registered borrower");
        assertEq(hooksData.hooksInstances.length, 2, "aggregated hooksData instances length");
        assertEq(hooksData.hooksTemplates.length, 2, "aggregated hooksData templates length");
    }

    function test_aggregatedMarketsDataForTemplate_hasStableOrder() external view {
        assertEq(lens.getAggregatedMarketsForHooksTemplateCount(hooksTemplate), 2, "market count");

        MarketData[] memory marketsData = lens.getAggregatedAllMarketsDataForHooksTemplate(hooksTemplate);
        assertEq(marketsData.length, 2, "aggregated market data length");
        assertEq(marketsData[0].hooksFactory, address(hooksFactory), "first factory");
        assertEq(marketsData[1].hooksFactory, address(hooksFactoryRevolving), "second factory");

        MarketDataV2[] memory marketsDataV2 = lens.getAggregatedAllMarketsDataV2ForHooksTemplate(hooksTemplate);
        assertEq(marketsDataV2.length, 2, "aggregated market data v2 length");
        assertEq(marketsDataV2[0].market.hooksFactory, address(hooksFactory), "first v2 factory");
        assertEq(marketsDataV2[1].market.hooksFactory, address(hooksFactoryRevolving), "second v2 factory");
        assertEq(marketsDataV2[0].commitmentFeeBips.isPresent, false, "legacy v2 commitment presence");
        assertEq(marketsDataV2[1].commitmentFeeBips.isPresent, true, "revolving v2 commitment presence");
    }

    function test_aggregatedMarketsDataForTemplate_containsBothMarkets() external view {
        MarketData[] memory marketsData = lens.getAggregatedAllMarketsDataForHooksTemplate(hooksTemplate);

        address[] memory marketAddresses = new address[](marketsData.length);
        for (uint256 i; i < marketsData.length; i++) {
            marketAddresses[i] = marketsData[i].marketToken.token;
        }

        assertTrue(_containsAddress(marketAddresses, address(market)), "contains legacy market");
        assertTrue(_containsAddress(marketAddresses, address(revolvingMarket)), "contains revolving market");
    }
}

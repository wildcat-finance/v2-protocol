// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import "../BaseMarketTest.sol";
import "src/HooksFactoryRevolving.sol";
import "src/IHooksFactoryRevolving.sol";
import "src/interfaces/IWildcatMarketRevolving.sol";
import "src/libraries/LibStoredInitCode.sol";
import "src/lens/MarketLens.sol";
import "src/market/WildcatMarketRevolving.sol";

contract MockNonHooksController {}

contract MockRevertingHooksFactory {
    function getHooksTemplatesCount() external pure returns (uint256) {
        return 1;
    }

    function getHooksInstancesForBorrower(address) external pure returns (address[] memory) {
        revert("mock-revert");
    }

    function getHooksTemplates() external pure returns (address[] memory) {
        revert("mock-revert");
    }

    function getMarketsForHooksTemplate(address) external pure returns (address[] memory) {
        revert("mock-revert");
    }
}

contract MarketLensMultiFactoryTest is BaseMarketTest {
    MarketLens internal lens;
    IHooksFactoryRevolving internal hooksFactoryRevolving;
    WildcatMarketRevolving internal revolvingMarket;
    address internal revolvingHooksInstance;

    uint16 internal constant _COMMITMENT_FEE_BIPS = 321;
    uint16 internal constant _REVOLVING_TEMPLATE_PROTOCOL_FEE_BIPS = 42;

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
        hooksFactoryRevolving.updateHooksTemplateFees(
            hooksTemplate, address(this), address(0), 0, _REVOLVING_TEMPLATE_PROTOCOL_FEE_BIPS
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

    function _getFactoryScopedTemplateData(
        FactoryScopedHooksTemplateData[] memory values,
        address factoryAddress,
        address templateAddress
    ) internal pure returns (bool found, HooksTemplateData memory templateData) {
        for (uint256 i; i < values.length; i++) {
            if (
                values[i].hooksFactory == factoryAddress && values[i].hooksTemplateData.hooksTemplate == templateAddress
            ) {
                return (true, values[i].hooksTemplateData);
            }
        }
    }

    function test_getMarketDataV2_presenceFlagsForLegacyAndRevolving() external view {
        MarketDataV2_5 memory legacyData = lens.getMarketDataV2(address(market));
        assertEq(legacyData.market.hooksFactory, address(hooksFactory), "legacy hooksFactory");
        assertEq(legacyData.commitmentFeeBips.isPresent, false, "legacy commitment presence");
        assertEq(legacyData.drawnAmount.isPresent, false, "legacy drawn presence");

        MarketDataV2_5 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.market.hooksFactory, address(hooksFactoryRevolving), "revolving hooksFactory");
        assertEq(revolvingData.commitmentFeeBips.isPresent, true, "revolving commitment presence");
        assertEq(revolvingData.commitmentFeeBips.value, _COMMITMENT_FEE_BIPS, "revolving commitment value");
        assertEq(revolvingData.drawnAmount.isPresent, true, "revolving drawn presence");
        assertEq(revolvingData.drawnAmount.value, 0, "revolving drawn value");
    }

    function test_getMarketDataV2_treatsZeroAsValidWhenPresent() external {
        MarketDataV2_5 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.drawnAmount.isPresent, true, "drawn presence");
        assertEq(revolvingData.drawnAmount.value, 0, "drawn value should be zero");
    }

    function test_getMarketDataV2_fallbackWhenOptionalGetterIsMalformed() external {
        vm.mockCall(
            address(revolvingMarket),
            abi.encodeWithSelector(IWildcatMarketRevolving.commitmentFeeBips.selector),
            hex"01"
        );

        MarketDataV2_5 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.commitmentFeeBips.isPresent, false, "malformed commitment presence");
        assertEq(revolvingData.drawnAmount.isPresent, true, "drawn presence");
    }

    function test_getMarketDataV2_fallbackWhenDrawnAmountGetterIsMalformed() external {
        vm.mockCall(
            address(revolvingMarket), abi.encodeWithSelector(IWildcatMarketRevolving.drawnAmount.selector), hex"01"
        );

        MarketDataV2_5 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.commitmentFeeBips.isPresent, true, "commitment presence");
        assertEq(revolvingData.drawnAmount.isPresent, false, "malformed drawn presence");
    }

    function test_getMarketDataV2_fallbackWhenDrawnAmountGetterReverts() external {
        vm.mockCallRevert(
            address(revolvingMarket),
            abi.encodeWithSelector(IWildcatMarketRevolving.drawnAmount.selector),
            abi.encodeWithSignature("MockFailure()")
        );

        MarketDataV2_5 memory revolvingData = lens.getMarketDataV2(address(revolvingMarket));
        assertEq(revolvingData.commitmentFeeBips.isPresent, true, "commitment presence");
        assertEq(revolvingData.drawnAmount.isPresent, false, "reverting drawn presence");
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

    function test_aggregatedFactoryScopedTemplates_preservePerFactoryData() external view {
        uint16 legacyProtocolFeeBipsExpected = hooksFactory.getHooksTemplateDetails(hooksTemplate).protocolFeeBips;
        uint16 revolvingProtocolFeeBipsExpected =
            hooksFactoryRevolving.getHooksTemplateDetails(hooksTemplate).protocolFeeBips;

        HooksTemplateData[] memory dedupedTemplates = lens.getAggregatedAllHooksTemplatesForBorrower(borrower);
        assertEq(dedupedTemplates.length, 2, "deduped templates length");

        FactoryScopedHooksTemplateData[] memory factoryScopedTemplates =
            lens.getAggregatedHooksTemplatesForBorrowerWithFactory(borrower);
        assertEq(factoryScopedTemplates.length, 4, "factory-scoped templates length");

        (bool foundLegacy, HooksTemplateData memory legacyTemplate) =
            _getFactoryScopedTemplateData(factoryScopedTemplates, address(hooksFactory), hooksTemplate);
        assertTrue(foundLegacy, "missing legacy template row");
        assertEq(legacyTemplate.totalMarkets, 1, "legacy total markets");
        assertEq(legacyTemplate.fees.protocolFeeBips, legacyProtocolFeeBipsExpected, "legacy protocol fee bips");

        (bool foundRevolving, HooksTemplateData memory revolvingTemplate) =
            _getFactoryScopedTemplateData(factoryScopedTemplates, address(hooksFactoryRevolving), hooksTemplate);
        assertTrue(foundRevolving, "missing revolving template row");
        assertEq(revolvingTemplate.totalMarkets, 1, "revolving total markets");
        assertEq(
            legacyTemplate.fees.protocolFeeBips != revolvingTemplate.fees.protocolFeeBips,
            true,
            "protocol fee bips should differ across factories"
        );
        assertEq(
            revolvingTemplate.fees.protocolFeeBips, revolvingProtocolFeeBipsExpected, "revolving protocol fee bips"
        );
    }

    function test_aggregatedMarketsDataForTemplate_hasStableOrder() external view {
        assertEq(lens.getAggregatedMarketsForHooksTemplateCount(hooksTemplate), 2, "market count");

        MarketData[] memory marketsData = lens.getAggregatedAllMarketsDataForHooksTemplate(hooksTemplate);
        assertEq(marketsData.length, 2, "aggregated market data length");
        assertEq(marketsData[0].hooksFactory, address(hooksFactory), "first factory");
        assertEq(marketsData[1].hooksFactory, address(hooksFactoryRevolving), "second factory");

        MarketDataV2_5[] memory marketsDataV2 = lens.getAggregatedAllMarketsDataV2ForHooksTemplate(hooksTemplate);
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

    function test_aggregatedReads_ignoreNonHooksController() external {
        MockNonHooksController nonHooksController = new MockNonHooksController();
        archController.registerControllerFactory(address(this));
        archController.registerController(address(nonHooksController));

        HooksInstanceData[] memory instances = lens.getAggregatedHooksInstancesForBorrower(borrower);
        assertEq(instances.length, 2, "instances length");
        assertTrue(_containsHooksInstance(instances, address(hooks)), "contains legacy hooks instance");
        assertTrue(_containsHooksInstance(instances, revolvingHooksInstance), "contains revolving hooks instance");

        HooksTemplateData[] memory templates = lens.getAggregatedAllHooksTemplatesForBorrower(borrower);
        assertEq(templates.length, 2, "templates length");
        assertTrue(_containsHooksTemplate(templates, hooksTemplate), "contains access-control template");
        assertTrue(_containsHooksTemplate(templates, fixedTermHooksTemplate), "contains fixed-term template");

        MarketData[] memory marketsData = lens.getAggregatedAllMarketsDataForHooksTemplate(hooksTemplate);
        assertEq(marketsData.length, 2, "markets length");
    }

    function test_aggregatedReads_tolerateRevertingHooksFactory() external {
        MockRevertingHooksFactory revertingFactory = new MockRevertingHooksFactory();
        archController.registerControllerFactory(address(this));
        archController.registerController(address(revertingFactory));

        HooksInstanceData[] memory instances = lens.getAggregatedHooksInstancesForBorrower(borrower);
        assertEq(instances.length, 2, "instances length");
        assertTrue(_containsHooksInstance(instances, address(hooks)), "contains legacy hooks instance");
        assertTrue(_containsHooksInstance(instances, revolvingHooksInstance), "contains revolving hooks instance");

        HooksTemplateData[] memory templates = lens.getAggregatedAllHooksTemplatesForBorrower(borrower);
        assertEq(templates.length, 2, "templates length");
        assertTrue(_containsHooksTemplate(templates, hooksTemplate), "contains access-control template");
        assertTrue(_containsHooksTemplate(templates, fixedTermHooksTemplate), "contains fixed-term template");

        MarketData[] memory marketsData = lens.getAggregatedAllMarketsDataForHooksTemplate(hooksTemplate);
        assertEq(marketsData.length, 2, "markets length");
    }

    function test_factoryParameterizedV2Reads() external view {
        MarketDataV2_5[] memory legacyV2 = lens.getAllMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate);
        assertEq(legacyV2.length, 1, "legacy length");
        assertEq(legacyV2[0].market.hooksFactory, address(hooksFactory), "legacy factory");
        assertEq(legacyV2[0].commitmentFeeBips.isPresent, false, "legacy commitment presence");
        assertEq(legacyV2[0].drawnAmount.isPresent, false, "legacy drawn presence");

        MarketDataV2_5[] memory revolvingV2 =
            lens.getAllMarketsDataV2ForHooksTemplate(address(hooksFactoryRevolving), hooksTemplate);
        assertEq(revolvingV2.length, 1, "revolving length");
        assertEq(revolvingV2[0].market.hooksFactory, address(hooksFactoryRevolving), "revolving factory");
        assertEq(revolvingV2[0].commitmentFeeBips.isPresent, true, "revolving commitment presence");
        assertEq(revolvingV2[0].drawnAmount.isPresent, true, "revolving drawn presence");
    }

    function test_paginatedV2Reads() external view {
        MarketDataV2_5[] memory legacyPage =
            lens.getPaginatedMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate, 0, 1);
        assertEq(legacyPage.length, 1, "legacy page length");
        assertEq(legacyPage[0].market.marketToken.token, address(market), "legacy market address");

        MarketDataV2_5[] memory revolvingPage =
            lens.getPaginatedMarketsDataV2ForHooksTemplate(address(hooksFactoryRevolving), hooksTemplate, 0, 1);
        assertEq(revolvingPage.length, 1, "revolving page length");
        assertEq(revolvingPage[0].market.marketToken.token, address(revolvingMarket), "revolving market address");
        assertEq(revolvingPage[0].commitmentFeeBips.isPresent, true, "revolving commitment presence");
    }

    function test_defaultFactoryV2EndpointsRemainLegacyScoped() external view {
        MarketDataV2_5[] memory allDefault = lens.getAllMarketsDataV2ForHooksTemplate(hooksTemplate);
        assertEq(allDefault.length, 1, "default all length");
        assertEq(allDefault[0].market.hooksFactory, address(hooksFactory), "default all factory");

        MarketDataV2_5[] memory paginatedDefault = lens.getPaginatedMarketsDataV2ForHooksTemplate(hooksTemplate, 0, 1);
        assertEq(paginatedDefault.length, 1, "default paginated length");
        assertEq(paginatedDefault[0].market.hooksFactory, address(hooksFactory), "default paginated factory");
    }
}

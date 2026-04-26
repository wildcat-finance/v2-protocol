// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import "src/WildcatArchController.sol";
import "src/HooksFactoryRevolving.sol";
import "src/IHooksFactoryRevolving.sol";
import "src/libraries/LibStoredInitCode.sol";
import "src/market/WildcatMarketRevolving.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "src/types/HooksConfig.sol";
import "./helpers/Assertions.sol";
import "./shared/mocks/MockHooks.sol";

contract HooksFactoryRevolvingTest is Test, Assertions {
    WildcatArchController archController;
    IHooksFactoryRevolving hooksFactoryRevolving;
    address hooksTemplate;
    MockERC20 underlying = new MockERC20("Underlying", "UND", 18);

    address internal constant nullAddress = address(0);
    address internal constant sanctionsSentinel = address(1);
    uint16 internal constant defaultCommitmentFeeBips = 100;

    function _storeMarketInitCode() internal virtual returns (address initCodeStorage, uint256 initCodeHash) {
        bytes memory marketInitCode = type(WildcatMarketRevolving).creationCode;
        initCodeHash = uint256(keccak256(marketInitCode));
        initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
    }

    function setUp() public {
        archController = new WildcatArchController();

        (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode();
        hooksFactoryRevolving =
            new HooksFactoryRevolving(address(archController), sanctionsSentinel, marketTemplate, marketInitCodeHash);
        hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
        archController.registerControllerFactory(address(hooksFactoryRevolving));
        hooksFactoryRevolving.registerWithArchController();
    }

    function _defaultDeployMarketInputs(address hooksInstance) internal view returns (DeployMarketInputs memory) {
        return DeployMarketInputs({
            asset: address(underlying),
            namePrefix: "Wildcat ",
            symbolPrefix: "wc",
            maxTotalSupply: 1_000_000e18,
            annualInterestBips: 1_000,
            delinquencyFeeBips: 100,
            withdrawalBatchDuration: 1 days,
            reserveRatioBips: 1_000,
            delinquencyGracePeriod: 1 days,
            hooks: EmptyHooksConfig.setHooksAddress(hooksInstance)
        });
    }

    function _defaultMarketData() internal pure returns (bytes memory) {
        return abi.encode(uint8(1), defaultCommitmentFeeBips);
    }

    function test_nameAndRegistrationWiring() external view {
        assertEq(hooksFactoryRevolving.name(), "WildcatHooksFactoryRevolving");
        assertEq(hooksFactoryRevolving.archController(), address(archController));
        assertTrue(archController.isRegisteredControllerFactory(address(hooksFactoryRevolving)));
        assertTrue(archController.isRegisteredController(address(hooksFactoryRevolving)));
    }

    function test_addHooksTemplate() external {
        string memory name_ = "revolving-template";
        vm.expectEmit(address(hooksFactoryRevolving));
        emit IHooksFactoryEventsAndErrors.HooksTemplateAdded(hooksTemplate, name_, nullAddress, nullAddress, 0, 0);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, name_, nullAddress, nullAddress, 0, 0);

        address[] memory hooksTemplates = hooksFactoryRevolving.getHooksTemplates();
        assertEq(hooksTemplates.length, 1);
        assertEq(hooksTemplates[0], hooksTemplate);
        assertEq(hooksFactoryRevolving.getHooksTemplatesCount(), 1);
        assertTrue(hooksFactoryRevolving.isHooksTemplate(hooksTemplate));

        HooksTemplate memory details = hooksFactoryRevolving.getHooksTemplateDetails(hooksTemplate);
        assertEq(
            details,
            HooksTemplate({
                exists: true,
                enabled: true,
                index: 0,
                name: name_,
                feeRecipient: nullAddress,
                originationFeeAsset: nullAddress,
                originationFeeAmount: 0,
                protocolFeeBips: 0
            })
        );
    }

    function test_addHooksTemplate_CallerNotArchControllerOwner() external {
        vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
        vm.prank(address(0xBEEF));
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
    }

    function test_addHooksTemplate_HooksTemplateAlreadyExists() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateAlreadyExists.selector);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
    }

    function test_addHooksTemplate_InvalidFeeConfiguration() external {
        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 1);

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.addHooksTemplate(
            hooksTemplate, "revolving-template", nullAddress, address(underlying), 1, 0
        );

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", address(0xBEEF), nullAddress, 1, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.addHooksTemplate(
            hooksTemplate, "revolving-template", address(0xBEEF), nullAddress, 0, 1_001
        );
    }

    function test_updateHooksTemplateFees() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);

        address feeRecipient = address(0xBEEF);
        address originationFeeAsset = address(underlying);
        uint80 originationFeeAmount = 123;
        uint16 protocolFeeBips = 10;

        vm.expectEmit(address(hooksFactoryRevolving));
        emit IHooksFactoryEventsAndErrors.HooksTemplateFeesUpdated(
            hooksTemplate, feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips
        );
        hooksFactoryRevolving.updateHooksTemplateFees(
            hooksTemplate, feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips
        );

        HooksTemplate memory details = hooksFactoryRevolving.getHooksTemplateDetails(hooksTemplate);
        assertEq(details.feeRecipient, feeRecipient);
        assertEq(details.originationFeeAsset, originationFeeAsset);
        assertEq(details.originationFeeAmount, originationFeeAmount);
        assertEq(details.protocolFeeBips, protocolFeeBips);
    }

    function test_updateHooksTemplateFees_CallerNotArchControllerOwner() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
        vm.prank(address(0xBEEF));
        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, address(0xBEEF), address(underlying), 1, 10);
    }

    function test_updateHooksTemplateFees_HooksTemplateNotFound() external {
        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, address(0xBEEF), address(underlying), 1, 10);
    }

    function test_updateHooksTemplateFees_InvalidFeeConfiguration() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, nullAddress, nullAddress, 0, 1);

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, nullAddress, address(underlying), 1, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, address(0xBEEF), nullAddress, 1, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, address(0xBEEF), nullAddress, 0, 1_001);
    }

    function test_disableHooksTemplate() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);

        vm.expectEmit(address(hooksFactoryRevolving));
        emit IHooksFactoryEventsAndErrors.HooksTemplateDisabled(hooksTemplate);
        hooksFactoryRevolving.disableHooksTemplate(hooksTemplate);

        HooksTemplate memory details = hooksFactoryRevolving.getHooksTemplateDetails(hooksTemplate);
        assertEq(details.enabled, false);
    }

    function test_disableHooksTemplate_CallerNotArchControllerOwner() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);

        vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
        vm.prank(address(0xBEEF));
        hooksFactoryRevolving.disableHooksTemplate(hooksTemplate);
    }

    function test_disableHooksTemplate_HooksTemplateNotFound() external {
        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
        hooksFactoryRevolving.disableHooksTemplate(hooksTemplate);
    }

    function test_deployHooksInstance_NotApprovedBorrower() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
        hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
    }

    function test_deployHooksInstance() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));

        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, abi.encode(uint256(123)));

        assertEq(hooksFactoryRevolving.getHooksTemplateForInstance(hooksInstance), hooksTemplate);
        assertTrue(hooksFactoryRevolving.isHooksInstance(hooksInstance));

        address[] memory hooksInstances = hooksFactoryRevolving.getHooksInstancesForBorrower(address(this));
        assertEq(hooksInstances.length, 1);
        assertEq(hooksInstances[0], hooksInstance);
        assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 1);
    }

    function test_deployHooksInstance_HooksTemplateNotAvailableWhenDisabled() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        hooksFactoryRevolving.disableHooksTemplate(hooksTemplate);
        archController.registerBorrower(address(this));

        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotAvailable.selector);
        hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
    }

    function test_deployMarketAndHooks_HooksTemplateNotAvailableWhenDisabled() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        hooksFactoryRevolving.disableHooksTemplate(hooksTemplate);
        archController.registerBorrower(address(this));

        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));
        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotAvailable.selector);
        hooksFactoryRevolving.deployMarketAndHooks(
            hooksTemplate,
            bytes(""),
            parameters,
            bytes("hook-data"),
            _defaultMarketData(),
            bytes32(uint256(1)),
            nullAddress,
            0
        );
    }

    function test_deployMarket_PassesHooksDataThroughAndRegistersMarket() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));

        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
        bytes memory hooksData = abi.encodePacked(bytes1(0xAB), bytes("hook-bytes"));

        address market = hooksFactoryRevolving.deployMarket(
            parameters, hooksData, _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );

        assertTrue(archController.isRegisteredMarket(market));
        assertEq(hooksFactoryRevolving.getMarketsForHooksTemplateCount(hooksTemplate), 1);
        assertEq(hooksFactoryRevolving.getMarketsForHooksInstanceCount(hooksInstance), 1);

        bytes memory observedHooksData = MockHooks(hooksInstance).lastCreateMarketHooksData();
        assertEq(observedHooksData, hooksData);
    }

    function test_deployMarket_NotApprovedBorrower() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        address hooksInstance = address(0xBEEF);
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
        hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarket_HooksInstanceNotFound() external {
        archController.registerBorrower(address(this));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0xBEEF));

        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksInstanceNotFound.selector);
        hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarket_SaltDoesNotContainSender() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        bytes32 invalidSalt = bytes32(uint256(uint160(address(0xBEEF))) << 96);
        vm.expectRevert(IHooksFactoryEventsAndErrors.SaltDoesNotContainSender.selector);
        hooksFactoryRevolving.deployMarket(parameters, bytes(""), _defaultMarketData(), invalidSalt, nullAddress, 0);
    }

    function test_deployMarket_FeeMismatch() external {
        address feeRecipient = address(0xFEE);
        hooksFactoryRevolving.addHooksTemplate(
            hooksTemplate, "revolving-template", feeRecipient, address(underlying), 123, 0
        );
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        vm.expectRevert(IHooksFactoryEventsAndErrors.FeeMismatch.selector);
        hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), address(underlying), 122
        );
    }

    function test_deployMarket_AssetBlacklisted() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
        archController.addBlacklist(address(underlying));

        vm.expectRevert(IHooksFactoryEventsAndErrors.AssetBlacklisted.selector);
        hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarket_InvalidMarketData_Empty() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        vm.expectRevert(IHooksFactoryRevolving.InvalidMarketData.selector);
        hooksFactoryRevolving.deployMarket(parameters, bytes(""), bytes(""), bytes32(uint256(1)), nullAddress, 0);
    }

    function test_deployMarket_InvalidMarketData_LengthMismatch() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
        bytes memory badLengthPayload = abi.encodePacked(uint8(1), uint16(defaultCommitmentFeeBips));

        vm.expectRevert(IHooksFactoryRevolving.InvalidMarketData.selector);
        hooksFactoryRevolving.deployMarket(parameters, bytes(""), badLengthPayload, bytes32(uint256(1)), nullAddress, 0);
    }

    function test_deployMarket_InvalidMarketData_UnsupportedVersion() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        vm.expectRevert(IHooksFactoryRevolving.UnsupportedMarketDataVersion.selector);
        hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), abi.encode(uint8(2), defaultCommitmentFeeBips), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarket_InvalidMarketData_CommitmentFeeTooHigh() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        vm.expectRevert(IHooksFactoryRevolving.InvalidCommitmentFeeBips.selector);
        hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), abi.encode(uint8(1), uint16(10_001)), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarketAndHooks_InvalidMarketData_DoesNotDeployHooksInstance() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));

        assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 0);
        vm.expectRevert(IHooksFactoryRevolving.InvalidMarketData.selector);
        hooksFactoryRevolving.deployMarketAndHooks(
            hooksTemplate, bytes(""), parameters, bytes(""), bytes(""), bytes32(uint256(1)), nullAddress, 0
        );
        assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 0);
    }

    function test_deployMarketAndHooks_NotApprovedBorrower() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));

        vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
        hooksFactoryRevolving.deployMarketAndHooks(
            hooksTemplate, bytes(""), parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarketAndHooks_HooksTemplateNotFound() external {
        archController.registerBorrower(address(this));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));
        address unknownTemplate = address(0xCAFE);

        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
        hooksFactoryRevolving.deployMarketAndHooks(
            unknownTemplate, bytes(""), parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
    }

    function test_deployMarketAndHooks_SaltDoesNotContainSender() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));

        bytes32 invalidSalt = bytes32(uint256(uint160(address(0xBEEF))) << 96);
        vm.expectRevert(IHooksFactoryEventsAndErrors.SaltDoesNotContainSender.selector);
        hooksFactoryRevolving.deployMarketAndHooks(
            hooksTemplate, bytes(""), parameters, bytes(""), _defaultMarketData(), invalidSalt, nullAddress, 0
        );
    }

    function test_deployMarketAndHooks_SucceedsWithValidMarketData() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));

        (address market, address hooksInstance) = hooksFactoryRevolving.deployMarketAndHooks(
            hooksTemplate,
            bytes(""),
            parameters,
            bytes("hook-data"),
            _defaultMarketData(),
            bytes32(uint256(1)),
            nullAddress,
            0
        );

        assertTrue(hooksInstance != address(0));
        assertTrue(archController.isRegisteredMarket(market));
        assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 1);
        assertEq(hooksFactoryRevolving.getMarketsForHooksTemplateCount(hooksTemplate), 1);
        assertEq(hooksFactoryRevolving.getMarketsForHooksInstanceCount(hooksInstance), 1);
    }

    function test_pushProtocolFeeBipsUpdates() external {
        address feeRecipient = address(0xFEE);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", feeRecipient, nullAddress, 0, 0);
        archController.registerBorrower(address(this));

        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

        address market0 = hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
        address market1 = hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(2)), nullAddress, 0
        );

        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, feeRecipient, nullAddress, 0, 1_000);
        hooksFactoryRevolving.pushProtocolFeeBipsUpdates(hooksTemplate);
        assertEq(WildcatMarketRevolving(market0).previousState().protocolFeeBips, 1_000);
        assertEq(WildcatMarketRevolving(market1).previousState().protocolFeeBips, 1_000);

        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, feeRecipient, nullAddress, 0, 500);
        hooksFactoryRevolving.pushProtocolFeeBipsUpdates(hooksTemplate, 0, 1);
        assertEq(WildcatMarketRevolving(market0).previousState().protocolFeeBips, 500);
        assertEq(WildcatMarketRevolving(market1).previousState().protocolFeeBips, 1_000);

        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, feeRecipient, nullAddress, 0, 100);
        hooksFactoryRevolving.pushProtocolFeeBipsUpdates(hooksTemplate, 1, 2);
        assertEq(WildcatMarketRevolving(market0).previousState().protocolFeeBips, 500);
        assertEq(WildcatMarketRevolving(market1).previousState().protocolFeeBips, 100);
    }

    function test_pushProtocolFeeBipsUpdates_HooksTemplateNotFound() external {
        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
        hooksFactoryRevolving.pushProtocolFeeBipsUpdates(hooksTemplate);
    }

    function test_pushProtocolFeeBipsUpdates_SetProtocolFeeBipsFailed() external {
        address feeRecipient = address(0xFEE);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", feeRecipient, nullAddress, 0, 0);
        archController.registerBorrower(address(this));

        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
        address market = hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );

        hooksFactoryRevolving.updateHooksTemplateFees(hooksTemplate, feeRecipient, nullAddress, 0, 100);
        vm.etch(market, hex"fd");

        vm.expectRevert(IHooksFactoryEventsAndErrors.SetProtocolFeeBipsFailed.selector);
        hooksFactoryRevolving.pushProtocolFeeBipsUpdates(hooksTemplate);
    }

    function test_getHooksTemplates_Pagination() external {
        address hooksTemplate2 = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template-1", nullAddress, nullAddress, 0, 0);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate2, "revolving-template-2", nullAddress, nullAddress, 0, 0);

        {
            address[] memory slice0 = hooksFactoryRevolving.getHooksTemplates(0, 1);
            assertEq(slice0.length, 1);
            assertEq(slice0[0], hooksTemplate);
        }
        {
            address[] memory slice1 = hooksFactoryRevolving.getHooksTemplates(1, 2);
            assertEq(slice1.length, 1);
            assertEq(slice1[0], hooksTemplate2);
        }
        {
            address[] memory clamped = hooksFactoryRevolving.getHooksTemplates(0, 10);
            assertEq(clamped.length, 2);
            assertEq(clamped[0], hooksTemplate);
            assertEq(clamped[1], hooksTemplate2);
        }
        {
            address[] memory emptyAtEnd = hooksFactoryRevolving.getHooksTemplates(2, 2);
            assertEq(emptyAtEnd.length, 0);
        }
        {
            address[] memory emptyInverted = hooksFactoryRevolving.getHooksTemplates(2, 1);
            assertEq(emptyInverted.length, 0);
        }
        {
            address[] memory emptyPastEnd = hooksFactoryRevolving.getHooksTemplates(3, 10);
            assertEq(emptyPastEnd.length, 0);
        }
    }

    function test_getMarketsForHooksTemplateAndInstance_Pagination() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));

        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
        address market0 = hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(1)), nullAddress, 0
        );
        address market1 = hooksFactoryRevolving.deployMarket(
            parameters, bytes(""), _defaultMarketData(), bytes32(uint256(2)), nullAddress, 0
        );

        {
            address[] memory templateSlice0 = hooksFactoryRevolving.getMarketsForHooksTemplate(hooksTemplate, 0, 1);
            assertEq(templateSlice0.length, 1);
            assertEq(templateSlice0[0], market0);
        }
        {
            address[] memory templateSlice1 = hooksFactoryRevolving.getMarketsForHooksTemplate(hooksTemplate, 1, 2);
            assertEq(templateSlice1.length, 1);
            assertEq(templateSlice1[0], market1);
        }
        {
            address[] memory templateClamped = hooksFactoryRevolving.getMarketsForHooksTemplate(hooksTemplate, 0, 10);
            assertEq(templateClamped.length, 2);
            assertEq(templateClamped[0], market0);
            assertEq(templateClamped[1], market1);
        }
        {
            address[] memory templateEmptyAtEnd = hooksFactoryRevolving.getMarketsForHooksTemplate(hooksTemplate, 2, 2);
            assertEq(templateEmptyAtEnd.length, 0);
        }
        {
            address[] memory templateEmptyInverted = hooksFactoryRevolving.getMarketsForHooksTemplate(hooksTemplate, 2, 1);
            assertEq(templateEmptyInverted.length, 0);
        }
        {
            address[] memory templateEmptyPastEnd = hooksFactoryRevolving.getMarketsForHooksTemplate(hooksTemplate, 3, 10);
            assertEq(templateEmptyPastEnd.length, 0);
        }
        {
            address[] memory instanceSlice0 = hooksFactoryRevolving.getMarketsForHooksInstance(hooksInstance, 0, 1);
            assertEq(instanceSlice0.length, 1);
            assertEq(instanceSlice0[0], market0);
        }
        {
            address[] memory instanceSlice1 = hooksFactoryRevolving.getMarketsForHooksInstance(hooksInstance, 1, 2);
            assertEq(instanceSlice1.length, 1);
            assertEq(instanceSlice1[0], market1);
        }
        {
            address[] memory instanceClamped = hooksFactoryRevolving.getMarketsForHooksInstance(hooksInstance, 0, 10);
            assertEq(instanceClamped.length, 2);
            assertEq(instanceClamped[0], market0);
            assertEq(instanceClamped[1], market1);
        }
        {
            address[] memory instanceEmptyAtEnd = hooksFactoryRevolving.getMarketsForHooksInstance(hooksInstance, 2, 2);
            assertEq(instanceEmptyAtEnd.length, 0);
        }
        {
            address[] memory instanceEmptyInverted = hooksFactoryRevolving.getMarketsForHooksInstance(hooksInstance, 2, 1);
            assertEq(instanceEmptyInverted.length, 0);
        }
        {
            address[] memory instanceEmptyPastEnd = hooksFactoryRevolving.getMarketsForHooksInstance(hooksInstance, 3, 10);
            assertEq(instanceEmptyPastEnd.length, 0);
        }
    }

    function test_computeMarketAddress_MatchesDeployedAddress() external {
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", nullAddress, nullAddress, 0, 0);
        archController.registerBorrower(address(this));

        address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));
        DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
        bytes32 salt = bytes32(uint256(123));

        address expected = hooksFactoryRevolving.computeMarketAddress(salt);
        address deployed =
            hooksFactoryRevolving.deployMarket(parameters, bytes(""), _defaultMarketData(), salt, nullAddress, 0);

        assertEq(deployed, expected);
    }

    function test_getRevolvingMarketCommitmentFeeBips_OutsideDeploymentContextReverts() external {
        vm.expectRevert();
        hooksFactoryRevolving.getRevolvingMarketCommitmentFeeBips();
    }
}

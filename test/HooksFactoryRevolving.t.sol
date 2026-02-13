// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import 'forge-std/Test.sol';
import 'src/WildcatArchController.sol';
import 'src/HooksFactoryRevolving.sol';
import 'src/IHooksFactoryRevolving.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/market/WildcatMarket.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import 'src/types/HooksConfig.sol';
import './helpers/Assertions.sol';
import './shared/mocks/MockHooks.sol';

contract HooksFactoryRevolvingTest is Test, Assertions {
  WildcatArchController archController;
  IHooksFactoryRevolving hooksFactoryRevolving;
  address hooksTemplate;
  MockERC20 underlying = new MockERC20('Underlying', 'UND', 18);

  address internal constant nullAddress = address(0);
  address internal constant sanctionsSentinel = address(1);
  uint16 internal constant defaultCommitmentFeeBips = 100;

  function _storeMarketInitCode()
    internal
    virtual
    returns (address initCodeStorage, uint256 initCodeHash)
  {
    bytes memory marketInitCode = type(WildcatMarket).creationCode;
    initCodeHash = uint256(keccak256(marketInitCode));
    initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
  }

  function setUp() public {
    archController = new WildcatArchController();

    (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode();
    hooksFactoryRevolving = new HooksFactoryRevolving(
      address(archController),
      sanctionsSentinel,
      marketTemplate,
      marketInitCodeHash
    );
    hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
    archController.registerControllerFactory(address(hooksFactoryRevolving));
    hooksFactoryRevolving.registerWithArchController();
  }

  function _defaultDeployMarketInputs(
    address hooksInstance
  ) internal view returns (DeployMarketInputs memory) {
    return
      DeployMarketInputs({
        asset: address(underlying),
        namePrefix: 'Wildcat ',
        symbolPrefix: 'wc',
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
    assertEq(hooksFactoryRevolving.name(), 'WildcatHooksFactoryRevolving');
    assertEq(hooksFactoryRevolving.archController(), address(archController));
    assertTrue(archController.isRegisteredControllerFactory(address(hooksFactoryRevolving)));
    assertTrue(archController.isRegisteredController(address(hooksFactoryRevolving)));
  }

  function test_addHooksTemplate() external {
    string memory name_ = 'revolving-template';
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
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
  }

  function test_deployHooksInstance_NotApprovedBorrower() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
    hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(''));
  }

  function test_deployHooksInstance() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));

    address hooksInstance = hooksFactoryRevolving.deployHooksInstance(
      hooksTemplate,
      abi.encode(uint256(123))
    );

    assertEq(hooksFactoryRevolving.getHooksTemplateForInstance(hooksInstance), hooksTemplate);
    assertTrue(hooksFactoryRevolving.isHooksInstance(hooksInstance));

    address[] memory hooksInstances = hooksFactoryRevolving.getHooksInstancesForBorrower(address(this));
    assertEq(hooksInstances.length, 1);
    assertEq(hooksInstances[0], hooksInstance);
    assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 1);
  }

  function test_deployMarket_PassesHooksDataThroughAndRegistersMarket() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));

    address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(''));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
    bytes memory hooksData = abi.encodePacked(bytes1(0xAB), bytes('hook-bytes'));

    address market = hooksFactoryRevolving.deployMarket(
      parameters,
      hooksData,
      _defaultMarketData(),
      bytes32(uint256(1)),
      nullAddress,
      0
    );

    assertTrue(archController.isRegisteredMarket(market));
    assertEq(hooksFactoryRevolving.getMarketsForHooksTemplateCount(hooksTemplate), 1);
    assertEq(hooksFactoryRevolving.getMarketsForHooksInstanceCount(hooksInstance), 1);

    bytes memory observedHooksData = MockHooks(hooksInstance).lastCreateMarketHooksData();
    assertEq(observedHooksData, hooksData);
  }

  function test_deployMarket_InvalidMarketData_Empty() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));
    address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(''));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

    vm.expectRevert(IHooksFactoryRevolving.InvalidMarketData.selector);
    hooksFactoryRevolving.deployMarket(parameters, bytes(''), bytes(''), bytes32(uint256(1)), nullAddress, 0);
  }

  function test_deployMarket_InvalidMarketData_LengthMismatch() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));
    address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(''));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);
    bytes memory badLengthPayload = abi.encodePacked(uint8(1), uint16(defaultCommitmentFeeBips));

    vm.expectRevert(IHooksFactoryRevolving.InvalidMarketData.selector);
    hooksFactoryRevolving.deployMarket(
      parameters,
      bytes(''),
      badLengthPayload,
      bytes32(uint256(1)),
      nullAddress,
      0
    );
  }

  function test_deployMarket_InvalidMarketData_UnsupportedVersion() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));
    address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(''));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

    vm.expectRevert(IHooksFactoryRevolving.UnsupportedMarketDataVersion.selector);
    hooksFactoryRevolving.deployMarket(
      parameters,
      bytes(''),
      abi.encode(uint8(2), defaultCommitmentFeeBips),
      bytes32(uint256(1)),
      nullAddress,
      0
    );
  }

  function test_deployMarket_InvalidMarketData_CommitmentFeeTooHigh() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));
    address hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(''));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(hooksInstance);

    vm.expectRevert(IHooksFactoryRevolving.InvalidCommitmentFeeBips.selector);
    hooksFactoryRevolving.deployMarket(
      parameters,
      bytes(''),
      abi.encode(uint8(1), uint16(10_001)),
      bytes32(uint256(1)),
      nullAddress,
      0
    );
  }

  function test_deployMarketAndHooks_InvalidMarketData_DoesNotDeployHooksInstance() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));

    assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 0);
    vm.expectRevert(IHooksFactoryRevolving.InvalidMarketData.selector);
    hooksFactoryRevolving.deployMarketAndHooks(
      hooksTemplate,
      bytes(''),
      parameters,
      bytes(''),
      bytes(''),
      bytes32(uint256(1)),
      nullAddress,
      0
    );
    assertEq(hooksFactoryRevolving.getHooksInstancesCountForBorrower(address(this)), 0);
  }

  function test_deployMarketAndHooks_SucceedsWithValidMarketData() external {
    hooksFactoryRevolving.addHooksTemplate(
      hooksTemplate,
      'revolving-template',
      nullAddress,
      nullAddress,
      0,
      0
    );
    archController.registerBorrower(address(this));
    DeployMarketInputs memory parameters = _defaultDeployMarketInputs(address(0));

    (address market, address hooksInstance) = hooksFactoryRevolving.deployMarketAndHooks(
      hooksTemplate,
      bytes(''),
      parameters,
      bytes('hook-data'),
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
}

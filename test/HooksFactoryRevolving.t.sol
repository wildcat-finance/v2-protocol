// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import 'forge-std/Test.sol';
import 'src/WildcatArchController.sol';
import 'src/HooksFactoryRevolving.sol';
import 'src/IHooksFactoryRevolving.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/market/WildcatMarket.sol';
import './helpers/Assertions.sol';
import './shared/mocks/MockHooks.sol';

contract HooksFactoryRevolvingTest is Test, Assertions {
  WildcatArchController archController;
  IHooksFactoryRevolving hooksFactoryRevolving;
  address hooksTemplate;

  address internal constant nullAddress = address(0);
  address internal constant sanctionsSentinel = address(1);

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
}

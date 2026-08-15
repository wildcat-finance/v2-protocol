// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/WildcatArchController.sol';
import 'src/WildcatBorrowerIdentityRegistry.sol';
import 'src/HooksFactory.sol';
import 'src/HooksFactoryRevolving.sol';
import 'src/market/WildcatMarket.sol';
import 'src/market/WildcatMarketRevolving.sol';
import 'src/access/OpenTermHooks.sol';
import 'src/libraries/LibStoredInitCode.sol';

contract HooksAdministratorTransferTest is Test {
  WildcatArchController internal archController;
  WildcatBorrowerIdentityRegistry internal borrowerIdentityRegistry;
  IHooksFactory internal standardFactory;
  IHooksFactory internal revolvingFactory;
  address internal hooksTemplate;

  address internal constant NewAdministrator = address(0xA11CE);
  address internal constant SecondAdministrator = address(0xB0B);

  function setUp() external {
    archController = new WildcatArchController();
    borrowerIdentityRegistry = new WildcatBorrowerIdentityRegistry(address(archController));
    hooksTemplate = LibStoredInitCode.deployInitCode(type(OpenTermHooks).creationCode);

    address standardMarketInitCode = LibStoredInitCode.deployInitCode(
      type(WildcatMarket).creationCode
    );
    address revolvingMarketInitCode = LibStoredInitCode.deployInitCode(
      type(WildcatMarketRevolving).creationCode
    );
    standardFactory = IHooksFactory(
      address(
        new HooksFactory(
          address(archController),
          address(1),
          address(this),
          standardMarketInitCode,
          uint256(keccak256(type(WildcatMarket).creationCode)),
          address(borrowerIdentityRegistry)
        )
      )
    );
    revolvingFactory = IHooksFactory(
      address(
        new HooksFactoryRevolving(
          address(archController),
          address(1),
          address(this),
          revolvingMarketInitCode,
          uint256(keccak256(type(WildcatMarketRevolving).creationCode)),
          address(borrowerIdentityRegistry)
        )
      )
    );

    archController.registerControllerFactory(address(standardFactory));
    archController.registerControllerFactory(address(revolvingFactory));
    standardFactory.registerWithArchController();
    revolvingFactory.registerWithArchController();
    standardFactory.addHooksTemplate(hooksTemplate, 'Open Term', address(0), address(0), 0, 0);
    revolvingFactory.addHooksTemplate(hooksTemplate, 'Open Term', address(0), address(0), 0, 0);

    archController.registerBorrower(address(this));
    archController.registerBorrower(NewAdministrator);
    archController.registerBorrower(SecondAdministrator);
  }

  function _deployHooks(IHooksFactory factory) internal returns (OpenTermHooks hooks) {
    hooks = OpenTermHooks(factory.deployHooksInstance(hooksTemplate, ''));
  }

  function _assertInitialAssociation(IHooksFactory factory) internal {
    OpenTermHooks hooks = _deployHooks(factory);
    address[] memory instances = factory.getHooksInstancesForAdministrator(address(this));

    assertEq(hooks.administrator(), address(this), 'administrator');
    assertEq(hooks.pendingAdministrator(), address(0), 'pending administrator');
    assertEq(factory.getHooksAdministrator(address(hooks)), address(this), 'factory administrator');
    assertEq(instances.length, 1, 'administrator instances');
    assertEq(instances[0], address(hooks), 'administrator instance');
    assertEq(
      factory.getHooksInstancesCountForAdministrator(address(this)),
      1,
      'administrator instance count'
    );
    assertEq(
      factory.getHooksInstancesForAdministrator(address(this), 0, 1),
      instances,
      'administrator instance page'
    );
    assertEq(
      factory.getHooksInstancesForBorrower(address(this)),
      instances,
      'borrower compatibility alias'
    );
    assertEq(
      factory.getHooksInstancesCountForBorrower(address(this)),
      1,
      'borrower count compatibility alias'
    );
  }

  function _acceptTransfer(
    IHooksFactory factory,
    OpenTermHooks hooks,
    address newAdministrator
  ) internal {
    hooks.requestAdministratorTransfer(newAdministrator);

    vm.expectEmit(address(hooks));
    emit BaseAccessControls.AdministratorTransferred(address(this), newAdministrator);
    vm.expectEmit(address(factory));
    emit IHooksFactoryEventsAndErrors.HooksInstanceAdministratorTransferred(
      address(hooks),
      address(this),
      newAdministrator
    );
    vm.prank(newAdministrator);
    hooks.acceptAdministratorTransfer();
  }

  function _assertTransfer(IHooksFactory factory) internal {
    OpenTermHooks hooks = _deployHooks(factory);
    hooks.requestAdministratorTransfer(NewAdministrator);

    assertEq(factory.getHooksAdministrator(address(hooks)), address(this), 'pending factory state');
    assertEq(
      factory.getHooksInstancesCountForAdministrator(NewAdministrator),
      0,
      'pending administrator instances'
    );

    vm.expectEmit(address(hooks));
    emit BaseAccessControls.AdministratorTransferred(address(this), NewAdministrator);
    vm.expectEmit(address(factory));
    emit IHooksFactoryEventsAndErrors.HooksInstanceAdministratorTransferred(
      address(hooks),
      address(this),
      NewAdministrator
    );
    vm.prank(NewAdministrator);
    hooks.acceptAdministratorTransfer();

    assertEq(hooks.administrator(), NewAdministrator, 'administrator');
    assertEq(factory.getHooksAdministrator(address(hooks)), NewAdministrator, 'factory administrator');
    assertEq(
      factory.getHooksInstancesCountForAdministrator(address(this)),
      0,
      'previous administrator instances'
    );
    address[] memory instances = factory.getHooksInstancesForAdministrator(NewAdministrator);
    assertEq(instances.length, 1, 'new administrator instances');
    assertEq(instances[0], address(hooks), 'new administrator instance');

    vm.prank(address(hooks));
    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidHooksAdministrator.selector);
    factory.onHooksAdministratorTransferred(address(this), NewAdministrator);
  }

  function _assertSwapAndPop(IHooksFactory factory) internal {
    OpenTermHooks firstHooks = _deployHooks(factory);
    OpenTermHooks secondHooks = _deployHooks(factory);

    _acceptTransfer(factory, firstHooks, NewAdministrator);
    address[] memory remainingInstances = factory.getHooksInstancesForAdministrator(address(this));
    assertEq(remainingInstances.length, 1, 'remaining instances');
    assertEq(remainingInstances[0], address(secondHooks), 'moved instance');

    _acceptTransfer(factory, secondHooks, SecondAdministrator);
    assertEq(
      factory.getHooksInstancesCountForAdministrator(address(this)),
      0,
      'previous administrator instances'
    );
    address[] memory secondAdministratorInstances = factory.getHooksInstancesForAdministrator(
      SecondAdministrator
    );
    assertEq(secondAdministratorInstances.length, 1, 'second administrator instances');
    assertEq(secondAdministratorInstances[0], address(secondHooks), 'second administrator instance');
  }

  function _assertCallbackAuthentication(IHooksFactory factory) internal {
    OpenTermHooks hooks = _deployHooks(factory);

    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksInstanceNotFound.selector);
    factory.onHooksAdministratorTransferred(address(this), NewAdministrator);

    vm.prank(address(hooks));
    vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidHooksAdministrator.selector);
    factory.onHooksAdministratorTransferred(address(this), NewAdministrator);

    assertEq(factory.getHooksAdministrator(address(hooks)), address(this), 'factory administrator');
  }

  function _assertDeploymentNonceSurvivesTransfer(IHooksFactory factory) internal {
    OpenTermHooks firstHooks = _deployHooks(factory);
    _acceptTransfer(factory, firstHooks, NewAdministrator);

    OpenTermHooks secondHooks = _deployHooks(factory);
    assertNotEq(address(secondHooks), address(firstHooks), 'hooks instance');
    assertEq(factory.getHooksInstanceDeploymentNonce(address(this)), 2, 'deployment nonce');

    address[] memory previousAdministratorInstances = factory
      .getHooksInstancesForAdministrator(address(this));
    assertEq(previousAdministratorInstances.length, 1, 'previous administrator instances');
    assertEq(previousAdministratorInstances[0], address(secondHooks), 'new hooks instance');
  }

  function test_initialAdministratorAssociation() external {
    _assertInitialAssociation(standardFactory);
    _assertInitialAssociation(revolvingFactory);
  }

  function test_administratorTransferUpdatesFactoryAssociation() external {
    _assertTransfer(standardFactory);
    _assertTransfer(revolvingFactory);
  }

  function test_administratorTransferUpdatesSwapAndPopIndex() external {
    _assertSwapAndPop(standardFactory);
    _assertSwapAndPop(revolvingFactory);
  }

  function test_factoryCallbackAuthentication() external {
    _assertCallbackAuthentication(standardFactory);
    _assertCallbackAuthentication(revolvingFactory);
  }

  function test_deploymentNonceSurvivesAdministratorTransfer() external {
    _assertDeploymentNonceSurvivesTransfer(standardFactory);
    _assertDeploymentNonceSurvivesTransfer(revolvingFactory);
  }
}

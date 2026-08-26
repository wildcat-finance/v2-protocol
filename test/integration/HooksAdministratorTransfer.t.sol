// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { HooksFactory } from 'src/HooksFactory.sol';
import { HooksFactoryRevolving } from 'src/HooksFactoryRevolving.sol';
import 'src/IHooksFactory.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract HooksAdministratorTransferTest is TestKernel {
  struct Fixture {
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    IHooksFactory standardFactory;
    IHooksFactory revolvingFactory;
    address hooksTemplate;
  }

  address internal constant NewAdministrator = address(0xA11CE);
  address internal constant SecondAdministrator = address(0xB0B);

  function _storeInitCode(
    string memory artifact
  ) internal returns (address storageContract, uint256 initCodeHash) {
    bytes memory initCode = vm.getCode(artifact);
    storageContract = LibStoredInitCode.deployInitCode(initCode);
    initCodeHash = uint256(keccak256(initCode));
  }

  function _deployFactory(
    Fixture memory fixture,
    bool revolving
  ) internal returns (IHooksFactory factory) {
    string memory marketArtifact = revolving
      ? 'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
      : 'src/market/WildcatMarket.sol:WildcatMarket';
    (address marketInitCodeStorage, uint256 marketInitCodeHash) = _storeInitCode(marketArtifact);
    bytes memory constructorArguments = abi.encode(
      address(fixture.archController),
      address(1),
      address(this),
      marketInitCodeStorage,
      marketInitCodeHash,
      address(fixture.registry)
    );
    address deployed = revolving
      ? _deployCode('src/HooksFactoryRevolving.sol:HooksFactoryRevolving', constructorArguments)
      : _deployCode('src/HooksFactory.sol:HooksFactory', constructorArguments);
    factory = IHooksFactory(deployed);
  }

  function _configureFactory(Fixture memory fixture, IHooksFactory factory) internal {
    fixture.archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
    factory.addHooksTemplate(fixture.hooksTemplate, 'Open Term', address(0), address(0), 0, 0);
  }

  function _newFixture() internal returns (Fixture memory fixture) {
    fixture.archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
    fixture.registry = WildcatBorrowerIdentityRegistry(
      _deployCode(
        'src/WildcatBorrowerIdentityRegistry.sol:WildcatBorrowerIdentityRegistry',
        abi.encode(address(fixture.archController))
      )
    );
    fixture.hooksTemplate = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/OpenTermHooks.sol:OpenTermHooks')
    );
    fixture.standardFactory = _deployFactory(fixture, false);
    fixture.revolvingFactory = _deployFactory(fixture, true);
    _configureFactory(fixture, fixture.standardFactory);
    _configureFactory(fixture, fixture.revolvingFactory);

    fixture.archController.registerBorrower(address(this));
    fixture.archController.registerBorrower(NewAdministrator);
    fixture.archController.registerBorrower(SecondAdministrator);
  }

  function _factories(
    Fixture memory fixture
  ) internal pure returns (IHooksFactory[2] memory factories) {
    factories[0] = fixture.standardFactory;
    factories[1] = fixture.revolvingFactory;
  }

  function _deployHooks(
    Fixture memory fixture,
    IHooksFactory factory
  ) internal returns (OpenTermHooks hooks) {
    hooks = OpenTermHooks(factory.deployHooksInstance(fixture.hooksTemplate, ''));
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

  function test_initialAdministratorAssociation_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      OpenTermHooks hooks = _deployHooks(fixture, factory);
      address[] memory instances = factory.getHooksInstancesForAdministrator(address(this));

      assertEq(hooks.administrator(), address(this));
      assertEq(hooks.pendingAdministrator(), address(0));
      assertEq(factory.getHooksAdministrator(address(hooks)), address(this));
      assertEq(instances.length, 1);
      assertEq(instances[0], address(hooks));
      assertEq(factory.getHooksInstancesCountForAdministrator(address(this)), 1);

      address[] memory page = factory.getHooksInstancesForAdministrator(address(this), 0, 1);
      assertEq(page.length, 1);
      assertEq(page[0], address(hooks));
      address[] memory compatibilityInstances = factory.getHooksInstancesForBorrower(address(this));
      assertEq(compatibilityInstances.length, 1);
      assertEq(compatibilityInstances[0], address(hooks));
      assertEq(factory.getHooksInstancesCountForBorrower(address(this)), 1);
    }
  }

  function test_administratorTransfer_UpdatesFactoryAssociationAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      OpenTermHooks hooks = _deployHooks(fixture, factory);
      hooks.requestAdministratorTransfer(NewAdministrator);

      assertEq(factory.getHooksAdministrator(address(hooks)), address(this));
      assertEq(factory.getHooksInstancesCountForAdministrator(NewAdministrator), 0);

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

      assertEq(hooks.administrator(), NewAdministrator);
      assertEq(factory.getHooksAdministrator(address(hooks)), NewAdministrator);
      assertEq(factory.getHooksInstancesCountForAdministrator(address(this)), 0);
      address[] memory instances = factory.getHooksInstancesForAdministrator(NewAdministrator);
      assertEq(instances.length, 1);
      assertEq(instances[0], address(hooks));

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidHooksAdministrator.selector);
      vm.prank(address(hooks));
      factory.onHooksAdministratorTransferred(address(this), NewAdministrator);
    }
  }

  function test_administratorTransfer_UpdatesSwapPopIndexAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      OpenTermHooks firstHooks = _deployHooks(fixture, factory);
      OpenTermHooks secondHooks = _deployHooks(fixture, factory);

      _acceptTransfer(factory, firstHooks, NewAdministrator);
      address[] memory remaining = factory.getHooksInstancesForAdministrator(address(this));
      assertEq(remaining.length, 1);
      assertEq(remaining[0], address(secondHooks));

      _acceptTransfer(factory, secondHooks, SecondAdministrator);
      assertEq(factory.getHooksInstancesCountForAdministrator(address(this)), 0);
      address[] memory moved = factory.getHooksInstancesForAdministrator(SecondAdministrator);
      assertEq(moved.length, 1);
      assertEq(moved[0], address(secondHooks));
    }
  }

  function test_factoryCallback_AuthenticatesHooksAndPendingTransferAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      OpenTermHooks hooks = _deployHooks(fixture, factory);

      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksInstanceNotFound.selector);
      factory.onHooksAdministratorTransferred(address(this), NewAdministrator);

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidHooksAdministrator.selector);
      vm.prank(address(hooks));
      factory.onHooksAdministratorTransferred(address(this), NewAdministrator);
      assertEq(factory.getHooksAdministrator(address(hooks)), address(this));
    }
  }

  function test_deploymentNonce_SurvivesAdministratorTransferAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      OpenTermHooks firstHooks = _deployHooks(fixture, factory);
      _acceptTransfer(factory, firstHooks, NewAdministrator);

      OpenTermHooks secondHooks = _deployHooks(fixture, factory);
      assertTrue(address(secondHooks) != address(firstHooks));
      assertEq(factory.getHooksInstanceDeploymentNonce(address(this)), 2);
      address[] memory instances = factory.getHooksInstancesForAdministrator(address(this));
      assertEq(instances.length, 1);
      assertEq(instances[0], address(secondHooks));
    }
  }
}

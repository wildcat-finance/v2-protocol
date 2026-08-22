// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { HooksFactory } from 'src/HooksFactory.sol';
import { HooksFactoryRevolving } from 'src/HooksFactoryRevolving.sol';
import { HooksTemplate } from 'src/IHooksFactory.sol';
import { IHooksFactory } from 'src/IHooksFactory.sol';
import { IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { WildcatBorrowerIdentityRegistry } from 'src/WildcatBorrowerIdentityRegistry.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { CreateProviderInputs } from 'src/access/ProviderStructs.sol';
import { ExistingProviderInputs } from 'src/access/ProviderStructs.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { NullProviderIndex, RoleProvider, encodeRoleProvider } from 'src/types/RoleProvider.sol';
import { BrokenHooksTemplate } from '../mocks/HooksFactoryMocks.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract HooksFactoriesTest is TestKernel {
  enum FactoryKind {
    Standard,
    Revolving
  }

  struct FeeConfig {
    address recipient;
    address asset;
    uint80 amount;
    uint16 protocolFeeBips;
  }

  struct Fixture {
    WildcatArchController archController;
    WildcatBorrowerIdentityRegistry registry;
    IHooksFactory standardFactory;
    IHooksFactory revolvingFactory;
    address standardMarketStorage;
    address revolvingMarketStorage;
    uint256 standardMarketHash;
    uint256 revolvingMarketHash;
    address firstTemplate;
    address secondTemplate;
  }

  address internal constant SanctionsSentinel = address(0x5A);
  address internal constant WrapperFactory = address(0x4626);
  address internal constant FeeRecipient = address(0xFEE);
  address internal constant FeeAsset = address(0xA55E7);
  address internal constant Outsider = address(0xBAD);

  function _storeInitCode(
    string memory artifact
  ) internal returns (address storageContract, uint256 initCodeHash) {
    bytes memory initCode = vm.getCode(artifact);
    storageContract = LibStoredInitCode.deployInitCode(initCode);
    initCodeHash = uint256(keccak256(initCode));
  }

  function _deployFactory(
    Fixture memory fixture,
    bool revolving,
    address marketStorage,
    uint256 marketHash
  ) internal returns (IHooksFactory factory) {
    bytes memory arguments = abi.encode(
      address(fixture.archController),
      SanctionsSentinel,
      WrapperFactory,
      marketStorage,
      marketHash,
      address(fixture.registry)
    );
    factory = IHooksFactory(
      revolving
        ? _deployCode('src/HooksFactoryRevolving.sol:HooksFactoryRevolving', arguments)
        : _deployCode('src/HooksFactory.sol:HooksFactory', arguments)
    );
    fixture.archController.registerControllerFactory(address(factory));
    factory.registerWithArchController();
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
    (fixture.standardMarketStorage, fixture.standardMarketHash) = _storeInitCode(
      'src/market/WildcatMarket.sol:WildcatMarket'
    );
    (fixture.revolvingMarketStorage, fixture.revolvingMarketHash) = _storeInitCode(
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
    );
    fixture.standardFactory = _deployFactory(
      fixture,
      false,
      fixture.standardMarketStorage,
      fixture.standardMarketHash
    );
    fixture.revolvingFactory = _deployFactory(
      fixture,
      true,
      fixture.revolvingMarketStorage,
      fixture.revolvingMarketHash
    );
    fixture.firstTemplate = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/OpenTermHooks.sol:OpenTermHooks')
    );
    fixture.secondTemplate = LibStoredInitCode.deployInitCode(
      vm.getCode('src/access/OpenTermHooks.sol:OpenTermHooks')
    );
  }

  function _factories(
    Fixture memory fixture
  ) internal pure returns (IHooksFactory[2] memory factories) {
    factories[0] = fixture.standardFactory;
    factories[1] = fixture.revolvingFactory;
  }

  function _addTemplate(
    IHooksFactory factory,
    address template,
    string memory name,
    FeeConfig memory fees
  ) internal {
    factory.addHooksTemplate(
      template,
      name,
      fees.recipient,
      fees.asset,
      fees.amount,
      fees.protocolFeeBips
    );
  }

  function _assertTemplate(
    IHooksFactory factory,
    address template,
    string memory name,
    uint24 index,
    bool enabled,
    FeeConfig memory fees
  ) internal view {
    HooksTemplate memory details = factory.getHooksTemplateDetails(template);
    assertTrue(details.exists);
    assertEq(details.enabled, enabled);
    assertEq(uint256(details.index), uint256(index));
    assertEq(details.name, name);
    assertEq(details.feeRecipient, fees.recipient);
    assertEq(details.originationFeeAsset, fees.asset);
    assertEq(uint256(details.originationFeeAmount), uint256(fees.amount));
    assertEq(uint256(details.protocolFeeBips), uint256(fees.protocolFeeBips));
    assertTrue(factory.isHooksTemplate(template));
  }

  function test_constructorAndRegistration_AcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      bool revolving = i == uint256(FactoryKind.Revolving);
      assertEq(factory.name(), revolving ? 'WildcatHooksFactoryRevolving' : 'WildcatHooksFactory');
      assertEq(factory.archController(), address(fixture.archController));
      assertEq(factory.sanctionsSentinel(), SanctionsSentinel);
      assertEq(factory.wrapperFactory(), WrapperFactory);
      assertEq(factory.borrowerIdentityRegistry(), address(fixture.registry));
      assertEq(
        factory.marketInitCodeStorage(),
        revolving ? fixture.revolvingMarketStorage : fixture.standardMarketStorage
      );
      assertEq(
        factory.marketInitCodeHash(),
        revolving ? fixture.revolvingMarketHash : fixture.standardMarketHash
      );
      assertTrue(fixture.archController.isRegisteredControllerFactory(address(factory)));
      assertTrue(fixture.archController.isRegisteredController(address(factory)));
    }
  }

  function test_addTemplate_StoresValidBoundaryConfigurationsAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    FeeConfig memory maximumFees = FeeConfig({
      recipient: FeeRecipient,
      asset: FeeAsset,
      amount: type(uint80).max,
      protocolFeeBips: 1_000
    });
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];

      vm.expectEmit(address(factory));
      emit IHooksFactoryEventsAndErrors.HooksTemplateAdded(
        fixture.firstTemplate,
        address(this),
        'no fees',
        address(0),
        address(0),
        0,
        0
      );
      _addTemplate(factory, fixture.firstTemplate, 'no fees', noFees);
      _assertTemplate(factory, fixture.firstTemplate, 'no fees', 0, true, noFees);

      vm.expectEmit(address(factory));
      emit IHooksFactoryEventsAndErrors.HooksTemplateAdded(
        fixture.secondTemplate,
        address(this),
        'maximum fees',
        maximumFees.recipient,
        maximumFees.asset,
        maximumFees.amount,
        maximumFees.protocolFeeBips
      );
      _addTemplate(factory, fixture.secondTemplate, 'maximum fees', maximumFees);
      _assertTemplate(factory, fixture.secondTemplate, 'maximum fees', 1, true, maximumFees);

      assertEq(factory.getHooksTemplatesCount(), 2);
      address[] memory templates = factory.getHooksTemplates();
      assertEq(templates.length, 2);
      assertEq(templates[0], fixture.firstTemplate);
      assertEq(templates[1], fixture.secondTemplate);
    }
  }

  function test_addTemplate_RejectsUnauthorizedAndDuplicateAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];

      vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
      vm.prank(Outsider);
      _addTemplate(factory, fixture.firstTemplate, 'template', noFees);

      _addTemplate(factory, fixture.firstTemplate, 'template', noFees);
      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateAlreadyExists.selector);
      _addTemplate(factory, fixture.firstTemplate, 'template', noFees);
    }
  }

  function test_addTemplate_RejectsEveryInvalidFeeShapeAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.addHooksTemplate(fixture.firstTemplate, 'template', address(0), address(0), 0, 1);

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.addHooksTemplate(fixture.firstTemplate, 'template', address(0), FeeAsset, 1, 0);

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.addHooksTemplate(fixture.firstTemplate, 'template', FeeRecipient, address(0), 1, 0);

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.addHooksTemplate(fixture.firstTemplate, 'template', FeeRecipient, FeeAsset, 0, 1_001);
    }
  }

  function test_updateTemplateFees_UpdatesAllFieldsAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    FeeConfig memory updatedFees = FeeConfig({
      recipient: FeeRecipient,
      asset: FeeAsset,
      amount: 123,
      protocolFeeBips: 456
    });
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      _addTemplate(factory, fixture.firstTemplate, 'template', noFees);

      vm.expectEmit(address(factory));
      emit IHooksFactoryEventsAndErrors.HooksTemplateFeesUpdated(
        fixture.firstTemplate,
        address(this),
        address(0),
        updatedFees.recipient,
        address(0),
        updatedFees.asset,
        0,
        updatedFees.amount,
        0,
        updatedFees.protocolFeeBips
      );
      factory.updateHooksTemplateFees(
        fixture.firstTemplate,
        updatedFees.recipient,
        updatedFees.asset,
        updatedFees.amount,
        updatedFees.protocolFeeBips
      );
      _assertTemplate(factory, fixture.firstTemplate, 'template', 0, true, updatedFees);
    }
  }

  function test_updateTemplateFees_RejectsInvalidCallsAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];

      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
      factory.updateHooksTemplateFees(fixture.firstTemplate, address(0), address(0), 0, 0);

      _addTemplate(factory, fixture.firstTemplate, 'template', noFees);
      vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
      vm.prank(Outsider);
      factory.updateHooksTemplateFees(fixture.firstTemplate, address(0), address(0), 0, 0);

      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.updateHooksTemplateFees(fixture.firstTemplate, address(0), address(0), 0, 1);
      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.updateHooksTemplateFees(fixture.firstTemplate, address(0), FeeAsset, 1, 0);
      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.updateHooksTemplateFees(fixture.firstTemplate, FeeRecipient, address(0), 1, 0);
      vm.expectRevert(IHooksFactoryEventsAndErrors.InvalidFeeConfiguration.selector);
      factory.updateHooksTemplateFees(fixture.firstTemplate, FeeRecipient, FeeAsset, 0, 1_001);
      _assertTemplate(factory, fixture.firstTemplate, 'template', 0, true, noFees);
    }
  }

  function test_disableTemplate_IsPermanentAndRetainsMetadataAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory fees = FeeConfig({
      recipient: FeeRecipient,
      asset: FeeAsset,
      amount: 123,
      protocolFeeBips: 456
    });
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      _addTemplate(factory, fixture.firstTemplate, 'template', fees);

      vm.expectEmit(address(factory));
      emit IHooksFactoryEventsAndErrors.HooksTemplateDisabled(fixture.firstTemplate, address(this));
      factory.disableHooksTemplate(fixture.firstTemplate);
      _assertTemplate(factory, fixture.firstTemplate, 'template', 0, false, fees);

      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateAlreadyExists.selector);
      _addTemplate(factory, fixture.firstTemplate, 'template', fees);
    }
  }

  function test_disableTemplate_RejectsInvalidCallsAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];

      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
      factory.disableHooksTemplate(fixture.firstTemplate);

      _addTemplate(factory, fixture.firstTemplate, 'template', noFees);
      vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
      vm.prank(Outsider);
      factory.disableHooksTemplate(fixture.firstTemplate);
      _assertTemplate(factory, fixture.firstTemplate, 'template', 0, true, noFees);
    }
  }

  function test_templatePagination_ClampsAndReturnsEmptyRangesAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      _addTemplate(factory, fixture.firstTemplate, 'first', noFees);
      _addTemplate(factory, fixture.secondTemplate, 'second', noFees);

      address[] memory first = factory.getHooksTemplates(0, 1);
      assertEq(first.length, 1);
      assertEq(first[0], fixture.firstTemplate);

      address[] memory second = factory.getHooksTemplates(1, 2);
      assertEq(second.length, 1);
      assertEq(second[0], fixture.secondTemplate);

      address[] memory clamped = factory.getHooksTemplates(0, type(uint256).max);
      assertEq(clamped.length, 2);
      assertEq(clamped[0], fixture.firstTemplate);
      assertEq(clamped[1], fixture.secondTemplate);

      assertEq(factory.getHooksTemplates(2, 2).length, 0);
      assertEq(factory.getHooksTemplates(2, 1).length, 0);
      assertEq(factory.getHooksTemplates(3, type(uint256).max).length, 0);
    }
  }

  function test_deployHooksInstance_RecordsIdentityAndProviderSnapshotAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    fixture.archController.registerBorrower(address(this));

    MockRoleProvider pullProvider = MockRoleProvider(
      _deployCode('test-next/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    MockRoleProvider pushProvider = MockRoleProvider(
      _deployCode('test-next/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    pullProvider.setIsPullProvider(true);

    ExistingProviderInputs[] memory existingProviders = new ExistingProviderInputs[](2);
    existingProviders[0] = ExistingProviderInputs({
      providerAddress: address(pullProvider),
      timeToLive: 1 days
    });
    existingProviders[1] = ExistingProviderInputs({
      providerAddress: address(pushProvider),
      timeToLive: 2 days
    });
    bytes memory constructorArgs = abi.encode(
      NameAndProviderInputs({
        name: 'shared access',
        roleProviderFactory: address(0),
        newProviderInputs: new CreateProviderInputs[](0),
        existingProviders: existingProviders
      })
    );

    RoleProvider[] memory expectedPullProviders = new RoleProvider[](1);
    expectedPullProviders[0] = encodeRoleProvider(
      1 days,
      address(pullProvider),
      0,
      NullProviderIndex
    );
    RoleProvider[] memory expectedPushProviders = new RoleProvider[](1);
    expectedPushProviders[0] = encodeRoleProvider(
      2 days,
      address(pushProvider),
      NullProviderIndex,
      0
    );

    FeeConfig memory noFees;
    IHooksFactory[2] memory factories = _factories(fixture);
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];
      _addTemplate(factory, fixture.firstTemplate, 'Open Term', noFees);

      vm.expectEmit(false, true, true, true, address(factory));
      emit IHooksFactoryEventsAndErrors.HooksInstanceDeployed(
        address(0),
        fixture.firstTemplate,
        address(this),
        address(this),
        'shared access',
        'OpenTermHooks'
      );
      vm.expectEmit(false, true, true, true, address(factory));
      emit IHooksFactoryEventsAndErrors.HooksInstanceRoleProviders(
        address(0),
        true,
        expectedPullProviders,
        expectedPushProviders
      );
      address hooksInstance = factory.deployHooksInstance(fixture.firstTemplate, constructorArgs);

      assertTrue(factory.isHooksInstance(hooksInstance));
      assertEq(factory.getHooksTemplateForInstance(hooksInstance), fixture.firstTemplate);
      assertEq(factory.getHooksAdministrator(hooksInstance), address(this));
      assertEq(factory.getHooksInstanceDeploymentNonce(address(this)), 1);
      assertEq(OpenTermHooks(hooksInstance).administrator(), address(this));
      assertEq(OpenTermHooks(hooksInstance).name(), 'shared access');

      address[] memory administratorInstances = factory.getHooksInstancesForAdministrator(
        address(this)
      );
      assertEq(administratorInstances.length, 1);
      assertEq(administratorInstances[0], hooksInstance);
      assertEq(factory.getHooksInstancesCountForAdministrator(address(this)), 1);
      address[] memory borrowerInstances = factory.getHooksInstancesForBorrower(address(this));
      assertEq(borrowerInstances.length, 1);
      assertEq(borrowerInstances[0], hooksInstance);
      assertEq(factory.getHooksInstancesCountForBorrower(address(this)), 1);

      RoleProvider[] memory pullProviders = OpenTermHooks(hooksInstance).getPullProviders();
      RoleProvider[] memory pushProviders = OpenTermHooks(hooksInstance).getPushProviders();
      assertEq(pullProviders.length, 1);
      assertEq(pushProviders.length, 1);
      assertEq(
        RoleProvider.unwrap(pullProviders[0]),
        RoleProvider.unwrap(expectedPullProviders[0])
      );
      assertEq(
        RoleProvider.unwrap(pushProviders[0]),
        RoleProvider.unwrap(expectedPushProviders[0])
      );
    }
  }

  function test_deployHooksInstance_RejectsInvalidPathsAcrossFactories() external {
    Fixture memory fixture = _newFixture();
    FeeConfig memory noFees;
    IHooksFactory[2] memory factories = _factories(fixture);

    for (uint256 i; i < factories.length; i++) {
      _addTemplate(factories[i], fixture.firstTemplate, 'Open Term', noFees);
      vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedBorrower.selector);
      factories[i].deployHooksInstance(fixture.firstTemplate, '');
    }

    fixture.archController.registerBorrower(address(this));
    address brokenTemplate = LibStoredInitCode.deployInitCode(
      vm.getCode('test-next/mocks/HooksFactoryMocks.sol:BrokenHooksTemplate')
    );
    for (uint256 i; i < factories.length; i++) {
      IHooksFactory factory = factories[i];

      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotFound.selector);
      factory.deployHooksInstance(fixture.secondTemplate, '');

      factory.disableHooksTemplate(fixture.firstTemplate);
      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateNotAvailable.selector);
      factory.deployHooksInstance(fixture.firstTemplate, '');

      _addTemplate(factory, brokenTemplate, 'broken', noFees);
      vm.expectRevert(IHooksFactoryEventsAndErrors.DeploymentFailed.selector);
      factory.deployHooksInstance(brokenTemplate, '');

      assertEq(factory.getHooksInstanceDeploymentNonce(address(this)), 0);
      assertEq(factory.getHooksInstancesCountForAdministrator(address(this)), 0);
    }
  }
}

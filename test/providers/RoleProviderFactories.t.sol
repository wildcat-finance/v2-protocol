// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // RoleProviderFactories.t
//  \ ^ /   Provider deployment matrices, validation, and hook attachment.
//    V
//
//  FIXTURE
//  setUp()
//  _case(...)
//  _factory(...)
//
//  PROVIDER DEPLOYMENT
//  testFuzz_typedAccessListFactoryCreatesExpectedProvider(...)
//  test_genericInterfaceCreatesExpectedProviders()
//  test_deploymentEvents()
//  _createTyped(...)
//  _assertProvider(...)
//  _expectDeploymentEvent(...)
//
//  DETERMINISTIC ADDRESSES
//  test_saltsAreNamespacedByCaller()
//  test_duplicateDeploymentsRevert()
//  _computeProviderAddress(...)
//
//  INPUT VALIDATION
//  test_malformedGenericInputsRevert()
//  test_invalidPrimaryAddressesRevert()
//
//  PROVIDER AUTHORITY AND ATTACHMENT
//  test_hookConstructorsCreateAndAttachProviders()
// ═════

import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { IRoleProviderFactory } from 'src/access/IRoleProviderFactory.sol';
import { CreateProviderInputs, NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { AccessListRoleProvider } from 'src/providers/AccessListRoleProvider.sol';
import { AccessListRoleProviderFactory } from 'src/providers/AccessListRoleProviderFactory.sol';
import {
  AccessListRoleProviderFactoryInputs,
  IAccessListRoleProviderFactory
} from 'src/providers/IAccessListRoleProviderFactory.sol';
import { RoleProvider } from 'src/types/RoleProvider.sol';
import { RoleProviderFactoryCaller } from '../mocks/RoleProviderFactoryMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

enum FactoryKind {
  AccessList
}

struct FactoryCase {
  FactoryKind kind;
  address factory;
  bytes inputs;
}

// ┌─ RoleProviderFactoriesTest ────────────────────────────────────────────────
contract RoleProviderFactoriesTest is TestKernel {
  address internal constant Alice = address(0xA11CE);
  address internal constant Administrator = address(0xAD111);
  uint256 internal constant FactoryCount = 1;

  address[FactoryCount] internal factories;
  RoleProviderFactoryCaller internal alternateCaller;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(1_714_737_030);
    factories[uint256(FactoryKind.AccessList)] =
      _deployCode('src/providers/AccessListRoleProviderFactory.sol:AccessListRoleProviderFactory');
    alternateCaller =
      RoleProviderFactoryCaller(_deployCode('test/mocks/RoleProviderFactoryMocks.sol:RoleProviderFactoryCaller'));
  }

  // ┌─ _case ─────
  function _case(FactoryKind kind, bytes32 salt) internal view returns (FactoryCase memory testCase) {
    testCase.kind = kind;
    testCase.factory = _factory(kind);
    address[] memory initialMembers = new address[](1);
    initialMembers[0] = Alice;
    testCase.inputs = abi.encode(
      AccessListRoleProviderFactoryInputs({ administrator: Administrator, initialMembers: initialMembers, salt: salt })
    );
  }

  // ┌─ _factory ─────
  function _factory(FactoryKind kind) internal view returns (address) {
    return factories[uint256(kind)];
  }

  // ░░▒▒▓▓██ [ PROVIDER DEPLOYMENT ] ──────────────────────────────────────────

  // ┌─ testFuzz_typedAccessListFactoryCreatesExpectedProvider ─────
  function testFuzz_typedAccessListFactoryCreatesExpectedProvider(bytes32 salt) external {
    FactoryCase memory testCase = _case(FactoryKind.AccessList, salt);
    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);

    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  // ┌─ test_genericInterfaceCreatesExpectedProviders ─────
  function test_genericInterfaceCreatesExpectedProviders() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(FactoryKind(rawKind), keccak256(abi.encode('generic', rawKind)));
      address expected = _computeProviderAddress(testCase, address(this));
      address actual = IRoleProviderFactory(testCase.factory).createRoleProvider(testCase.inputs);

      assertEq(actual, expected, 'provider');
      _assertProvider(testCase, actual);
    }
  }

  // ┌─ test_deploymentEvents ─────
  function test_deploymentEvents() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(FactoryKind(rawKind), keccak256(abi.encode('event', rawKind)));
      address expected = _computeProviderAddress(testCase, address(this));
      _expectDeploymentEvent(testCase, expected, address(this));
      _createTyped(testCase);
    }
  }

  // ┌─ _createTyped ─────
  function _createTyped(FactoryCase memory testCase) internal returns (address provider) {
    return AccessListRoleProviderFactory(testCase.factory)
      .createAccessListRoleProvider(abi.decode(testCase.inputs, (AccessListRoleProviderFactoryInputs)));
  }

  // ┌─ _assertProvider ─────
  function _assertProvider(FactoryCase memory testCase, address provider) internal view {
    assertTrue(provider.code.length > 0, 'provider code');
    assertTrue(IRoleProvider(provider).isPullProvider(), 'provider kind');
    AccessListRoleProviderFactoryInputs memory inputs =
      abi.decode(testCase.inputs, (AccessListRoleProviderFactoryInputs));
    assertEq(AccessListRoleProvider(provider).administrator(), inputs.administrator);
    assertTrue(AccessListRoleProvider(provider).isMember(inputs.initialMembers[0]));
  }

  // ┌─ _expectDeploymentEvent ─────
  function _expectDeploymentEvent(FactoryCase memory testCase, address provider, address deployer) internal {
    vm.expectEmit(testCase.factory);
    AccessListRoleProviderFactoryInputs memory inputs =
      abi.decode(testCase.inputs, (AccessListRoleProviderFactoryInputs));
    emit IAccessListRoleProviderFactory.AccessListRoleProviderDeployed(
      provider,
      inputs.administrator,
      deployer,
      inputs.salt,
      inputs.initialMembers
    );
  }

  // ░░▒▒▓▓██ [ DETERMINISTIC ADDRESSES ] ──────────────────────────────────────

  // ┌─ test_saltsAreNamespacedByCaller ─────
  function test_saltsAreNamespacedByCaller() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(FactoryKind(rawKind), keccak256(abi.encode('shared', rawKind)));
      address first = IRoleProviderFactory(testCase.factory).createRoleProvider(testCase.inputs);
      address second = alternateCaller.createRoleProvider(testCase.factory, testCase.inputs);

      assertTrue(first != second, 'provider addresses');
      assertEq(second, _computeProviderAddress(testCase, address(alternateCaller)), 'namespaced address');
    }
  }

  // ┌─ test_duplicateDeploymentsRevert ─────
  function test_duplicateDeploymentsRevert() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(FactoryKind(rawKind), keccak256(abi.encode('duplicate', rawKind)));
      _createTyped(testCase);

      vm.expectRevert(IAccessListRoleProviderFactory.RoleProviderAlreadyExists.selector);
      _createTyped(testCase);
    }
  }

  // ┌─ _computeProviderAddress ─────
  function _computeProviderAddress(
    FactoryCase memory testCase,
    address deployer
  )
    internal
    view
    returns (address provider)
  {
    return AccessListRoleProviderFactory(testCase.factory)
      .computeRoleProviderAddress(deployer, abi.decode(testCase.inputs, (AccessListRoleProviderFactoryInputs)));
  }

  // ░░▒▒▓▓██ [ INPUT VALIDATION ] ─────────────────────────────────────────────

  // ┌─ test_malformedGenericInputsRevert ─────
  function test_malformedGenericInputsRevert() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      vm.expectRevert();
      IRoleProviderFactory(_factory(FactoryKind(rawKind))).createRoleProvider(hex'1234');
    }
  }

  // ┌─ test_invalidPrimaryAddressesRevert ─────
  function test_invalidPrimaryAddressesRevert() external {
    address[] memory noMembers = new address[](0);
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    AccessListRoleProviderFactory(_factory(FactoryKind.AccessList))
      .createAccessListRoleProvider(
        AccessListRoleProviderFactoryInputs({
          administrator: address(0),
          initialMembers: noMembers,
          salt: bytes32('access')
        })
      );
  }

  // ░░▒▒▓▓██ [ PROVIDER AUTHORITY AND ATTACHMENT ] ────────────────────────────

  // ┌─ test_hookConstructorsCreateAndAttachProviders ─────
  function test_hookConstructorsCreateAndAttachProviders() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(FactoryKind(rawKind), keccak256(abi.encode('hook constructor', rawKind)));
      NameAndProviderInputs memory hookInputs;
      hookInputs.name = 'Factory matrix hook';
      hookInputs.roleProviderFactory = testCase.factory;
      hookInputs.newProviderInputs = new CreateProviderInputs[](1);
      hookInputs.newProviderInputs[0] =
        CreateProviderInputs({ timeToLive: 0, providerFactoryCalldata: testCase.inputs });

      OpenTermHooks hooks = OpenTermHooks(
        _deployCode('src/access/OpenTermHooks.sol:OpenTermHooks', abi.encode(address(this), abi.encode(hookInputs)))
      );
      address expected = _computeProviderAddress(testCase, address(hooks));
      RoleProvider[] memory providers = hooks.getPullProviders();

      assertEq(providers.length, 1, 'provider count');
      assertEq(providers[0].providerAddress(), expected, 'provider address');
      _assertProvider(testCase, expected);
    }
  }
}

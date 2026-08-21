// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/IManagedRoleProvider.sol';
import 'src/access/ProviderStructs.sol';
import 'src/providers/IMerkleRoleProviderFactory.sol';
import 'src/providers/MerkleRoleProvider.sol';
import 'src/providers/MerkleRoleProviderFactory.sol';
import 'src/types/RoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';

contract MerkleRoleProviderFactoryCaller {
  function createRoleProvider(
    MerkleRoleProviderFactory factory,
    bytes calldata data
  ) external returns (address) {
    return factory.createRoleProvider(data);
  }
}

contract MerkleRoleProviderFactoryTest is Test {
  address internal constant Administrator = address(0xA11CE);

  MerkleRoleProviderFactory internal factory;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new MerkleRoleProviderFactory();
  }

  function _inputs(
    address administrator,
    bytes32 root,
    bytes32 salt
  ) internal pure returns (MerkleRoleProviderFactoryInputs memory inputs) {
    inputs.administrator = administrator;
    inputs.root = root;
    inputs.salt = salt;
  }

  function testFuzz_createMerkleRoleProvider(
    address administrator,
    bytes32 root,
    bytes32 salt
  ) external {
    if (administrator == address(0)) administrator = Administrator;
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(administrator, root, salt);
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createMerkleRoleProvider(inputs);

    assertEq(actual, expected, 'provider');
    assertGt(actual.code.length, 0, 'provider code');
    assertEq(MerkleRoleProvider(actual).administrator(), administrator, 'administrator');
    assertEq(MerkleRoleProvider(actual).root(), root, 'root');
  }

  function test_createRoleProvider_GenericInterface() external {
    bytes32 root = keccak256('root');
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      Administrator,
      root,
      bytes32('generic')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(abi.encode(inputs));

    assertEq(actual, expected, 'provider');
    assertEq(MerkleRoleProvider(actual).administrator(), Administrator, 'administrator');
    assertEq(MerkleRoleProvider(actual).root(), root, 'root');
  }

  function test_deploymentEvent() external {
    bytes32 root = keccak256('root');
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      Administrator,
      root,
      bytes32('event')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);

    vm.expectEmit(address(factory));
    emit IMerkleRoleProviderFactory.MerkleRoleProviderDeployed(
      expected,
      Administrator,
      address(this),
      inputs.salt,
      root
    );
    factory.createMerkleRoleProvider(inputs);
  }

  function test_saltIsNamespacedByCaller() external {
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      Administrator,
      keccak256('root'),
      bytes32('shared')
    );
    MerkleRoleProviderFactoryCaller caller = new MerkleRoleProviderFactoryCaller();

    address first = factory.createRoleProvider(abi.encode(inputs));
    address second = caller.createRoleProvider(factory, abi.encode(inputs));

    assertNotEq(first, second, 'provider addresses');
    assertEq(
      second,
      factory.computeRoleProviderAddress(address(caller), inputs),
      'namespaced address'
    );
  }

  function test_duplicateDeploymentReverts() external {
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      Administrator,
      keccak256('root'),
      bytes32('duplicate')
    );
    factory.createMerkleRoleProvider(inputs);

    vm.expectRevert(IMerkleRoleProviderFactory.RoleProviderAlreadyExists.selector);
    factory.createMerkleRoleProvider(inputs);
  }

  function test_malformedInitializationReverts() external {
    vm.expectRevert();
    factory.createRoleProvider(hex'1234');

    bytes memory dirtyAddress = abi.encode(
      _inputs(Administrator, keccak256('root'), bytes32('dirty'))
    );
    assembly {
      mstore(add(dirtyAddress, 0x20), or(mload(add(dirtyAddress, 0x20)), shl(160, 1)))
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyAddress);
  }

  function test_invalidAdministratorReverts() external {
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      address(0),
      keccak256('root'),
      bytes32('invalid')
    );
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    factory.createMerkleRoleProvider(inputs);
  }

  function test_zeroRootIsAllowed() external {
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      Administrator,
      bytes32(0),
      bytes32('empty')
    );
    MerkleRoleProvider provider = MerkleRoleProvider(
      factory.createMerkleRoleProvider(inputs)
    );
    bytes32[] memory proof = new bytes32[](0);

    assertEq(provider.root(), bytes32(0), 'root');
    assertFalse(provider.isMember(Administrator, proof), 'member');
  }

  function test_factoryHasNoProviderAuthority() external {
    MerkleRoleProviderFactoryInputs memory inputs = _inputs(
      Administrator,
      keccak256('root'),
      bytes32('authority')
    );
    MerkleRoleProvider provider = MerkleRoleProvider(
      factory.createMerkleRoleProvider(inputs)
    );

    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    vm.prank(address(factory));
    provider.updateRoot(keccak256('next root'));
  }

  function test_hookConstructorCreatesAndAttachesProvider() external {
    bytes32 root = keccak256('root');
    MerkleRoleProviderFactoryInputs memory providerInputs = _inputs(
      Administrator,
      root,
      bytes32('constructor')
    );

    NameAndProviderInputs memory hookInputs;
    hookInputs.name = 'Merkle Hook';
    hookInputs.roleProviderFactory = address(factory);
    hookInputs.newProviderInputs = new CreateProviderInputs[](1);
    hookInputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(providerInputs)
    });

    OpenTermHooks hooks = new OpenTermHooks(address(this), abi.encode(hookInputs));
    address expectedProvider = factory.computeRoleProviderAddress(address(hooks), providerInputs);

    RoleProvider[] memory providers = hooks.getPushProviders();
    assertEq(providers.length, 1, 'provider count');
    assertEq(providers[0].providerAddress(), expectedProvider, 'provider address');
    assertEq(
      MerkleRoleProvider(expectedProvider).administrator(),
      Administrator,
      'provider administrator'
    );
    assertEq(MerkleRoleProvider(expectedProvider).root(), root, 'provider root');
  }
}

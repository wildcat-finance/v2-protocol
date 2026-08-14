// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MockERC4626 } from 'lib/solady/test/utils/mocks/MockERC4626.sol';

import 'src/access/ProviderStructs.sol';
import 'src/providers/ERC4626AssetsRoleProvider.sol';
import 'src/providers/ERC4626AssetsRoleProviderFactory.sol';
import 'src/providers/IERC4626AssetsRoleProvider.sol';
import 'src/providers/IERC4626AssetsRoleProviderFactory.sol';
import 'src/types/RoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';

contract ERC4626AssetsRoleProviderFactoryCaller {
  function createRoleProvider(
    ERC4626AssetsRoleProviderFactory factory,
    bytes calldata data
  ) external returns (address) {
    return factory.createRoleProvider(data);
  }
}

contract ERC4626AssetsRoleProviderFactoryTest is Test {
  ERC4626AssetsRoleProviderFactory internal factory;
  MockERC20 internal underlying;
  MockERC4626 internal vault;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new ERC4626AssetsRoleProviderFactory();
    underlying = new MockERC20('Underlying', 'UND', 18);
    vault = new MockERC4626(address(underlying), 'Vault', 'VLT', false, 0);
  }

  function _inputs(
    address vaultAddress,
    uint256 minAssets,
    bytes32 salt
  ) internal pure returns (ERC4626AssetsRoleProviderFactoryInputs memory inputs) {
    inputs.vault = vaultAddress;
    inputs.minAssets = minAssets;
    inputs.salt = salt;
  }

  function testFuzz_createERC4626AssetsRoleProvider(
    uint128 minAssetsSeed,
    bytes32 salt
  ) external {
    uint256 minAssets = bound(uint256(minAssetsSeed), 1, type(uint128).max);
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(vault),
      minAssets,
      salt
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createERC4626AssetsRoleProvider(inputs);

    assertEq(actual, expected, 'provider');
    assertGt(actual.code.length, 0, 'provider code');
    assertEq(ERC4626AssetsRoleProvider(actual).vault(), address(vault), 'vault');
    assertEq(ERC4626AssetsRoleProvider(actual).minAssets(), minAssets, 'minimum assets');
  }

  function test_createRoleProvider_GenericInterface() external {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(vault),
      100e18,
      bytes32('generic')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(abi.encode(inputs));

    assertEq(actual, expected, 'provider');
    assertEq(ERC4626AssetsRoleProvider(actual).vault(), address(vault), 'vault');
    assertEq(ERC4626AssetsRoleProvider(actual).minAssets(), 100e18, 'minimum assets');
  }

  function test_deploymentEvent() external {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(vault),
      100e18,
      bytes32('event')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);

    vm.expectEmit(address(factory));
    emit IERC4626AssetsRoleProviderFactory.ERC4626AssetsRoleProviderDeployed(
      expected,
      address(vault),
      address(this),
      inputs.salt,
      inputs.minAssets
    );
    factory.createERC4626AssetsRoleProvider(inputs);
  }

  function test_saltIsNamespacedByCaller() external {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(vault),
      100e18,
      bytes32('shared')
    );
    ERC4626AssetsRoleProviderFactoryCaller caller = new ERC4626AssetsRoleProviderFactoryCaller();

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
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(vault),
      100e18,
      bytes32('duplicate')
    );
    factory.createERC4626AssetsRoleProvider(inputs);

    vm.expectRevert(IERC4626AssetsRoleProviderFactory.RoleProviderAlreadyExists.selector);
    factory.createERC4626AssetsRoleProvider(inputs);
  }

  function test_malformedInitializationReverts() external {
    vm.expectRevert();
    factory.createRoleProvider(hex'1234');
  }

  function test_invalidVaultReverts() external {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(0),
      100e18,
      bytes32('invalid')
    );
    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidVaultAddress.selector);
    factory.createERC4626AssetsRoleProvider(inputs);
  }

  function test_zeroMinimumReverts() external {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = _inputs(
      address(vault),
      0,
      bytes32('zero')
    );
    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidMinimumAssets.selector);
    factory.createERC4626AssetsRoleProvider(inputs);
  }

  function test_hookConstructorCreatesAndAttachesProvider() external {
    ERC4626AssetsRoleProviderFactoryInputs memory providerInputs = _inputs(
      address(vault),
      100e18,
      bytes32('constructor')
    );

    NameAndProviderInputs memory hookInputs;
    hookInputs.name = 'ERC4626 Hook';
    hookInputs.roleProviderFactory = address(factory);
    hookInputs.newProviderInputs = new CreateProviderInputs[](1);
    hookInputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(providerInputs)
    });

    OpenTermHooks hooks = new OpenTermHooks(address(this), abi.encode(hookInputs));
    address expectedProvider = factory.computeRoleProviderAddress(address(hooks), providerInputs);

    RoleProvider[] memory providers = hooks.getPullProviders();
    assertEq(providers.length, 1, 'provider count');
    assertEq(providers[0].providerAddress(), expectedProvider, 'provider address');
    assertEq(ERC4626AssetsRoleProvider(expectedProvider).vault(), address(vault), 'vault');
    assertEq(
      ERC4626AssetsRoleProvider(expectedProvider).minAssets(),
      providerInputs.minAssets,
      'minimum assets'
    );
  }
}

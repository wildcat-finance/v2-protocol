// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

import 'src/access/ProviderStructs.sol';
import 'src/providers/ERC20RoleProvider.sol';
import 'src/providers/ERC20RoleProviderFactory.sol';
import 'src/providers/IERC20RoleProvider.sol';
import 'src/providers/IERC20RoleProviderFactory.sol';
import 'src/types/RoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';

contract ERC20RoleProviderFactoryCaller {
  function createRoleProvider(
    ERC20RoleProviderFactory factory,
    bytes calldata data
  ) external returns (address) {
    return factory.createRoleProvider(data);
  }
}

contract ERC20RoleProviderFactoryTest is Test {
  ERC20RoleProviderFactory internal factory;
  MockERC20 internal token;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new ERC20RoleProviderFactory();
    token = new MockERC20('Gate', 'GATE', 18);
  }

  function _inputs(
    address tokenAddress,
    uint256 minBalance,
    bytes32 salt
  ) internal pure returns (ERC20RoleProviderFactoryInputs memory inputs) {
    inputs.token = tokenAddress;
    inputs.minBalance = minBalance;
    inputs.salt = salt;
  }

  function testFuzz_createERC20RoleProvider(
    uint128 minBalanceSeed,
    bytes32 salt
  ) external {
    uint256 minBalance = bound(uint256(minBalanceSeed), 1, type(uint128).max);
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      minBalance,
      salt
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createERC20RoleProvider(inputs);

    assertEq(actual, expected, 'provider');
    assertGt(actual.code.length, 0, 'provider code');
    assertEq(ERC20RoleProvider(actual).token(), address(token), 'token');
    assertEq(ERC20RoleProvider(actual).minBalance(), minBalance, 'minimum balance');
  }

  function test_createRoleProvider_GenericInterface() external {
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      100e18,
      bytes32('generic')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(bytes.concat(abi.encode(inputs), hex'deadbeef'));

    assertEq(actual, expected, 'provider');
    assertEq(ERC20RoleProvider(actual).token(), address(token), 'token');
    assertEq(ERC20RoleProvider(actual).minBalance(), 100e18, 'minimum balance');
  }

  function test_deploymentEvent() external {
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      100e18,
      bytes32('event')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);

    vm.expectEmit(address(factory));
    emit IERC20RoleProviderFactory.ERC20RoleProviderDeployed(
      expected,
      address(token),
      address(this),
      inputs.salt,
      inputs.minBalance
    );
    factory.createERC20RoleProvider(inputs);
  }

  function test_saltIsNamespacedByCaller() external {
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      100e18,
      bytes32('shared')
    );
    ERC20RoleProviderFactoryCaller caller = new ERC20RoleProviderFactoryCaller();

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
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      100e18,
      bytes32('duplicate')
    );
    factory.createERC20RoleProvider(inputs);

    vm.expectRevert(IERC20RoleProviderFactory.RoleProviderAlreadyExists.selector);
    factory.createERC20RoleProvider(inputs);
  }

  function test_malformedInitializationReverts() external {
    vm.expectRevert();
    factory.createRoleProvider(hex'1234');

    bytes memory dirtyAddress = abi.encode(
      _inputs(address(token), 100e18, bytes32('dirty'))
    );
    assembly {
      mstore(add(dirtyAddress, 0x20), or(mload(add(dirtyAddress, 0x20)), shl(160, 1)))
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyAddress);
  }

  function test_invalidTokenReverts() external {
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(0),
      100e18,
      bytes32('invalid')
    );
    vm.expectRevert(IERC20RoleProvider.InvalidTokenAddress.selector);
    factory.createERC20RoleProvider(inputs);
  }

  function test_zeroMinimumReverts() external {
    ERC20RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      0,
      bytes32('zero')
    );
    vm.expectRevert(IERC20RoleProvider.InvalidMinimumBalance.selector);
    factory.createERC20RoleProvider(inputs);
  }

  function test_hookConstructorCreatesAndAttachesProvider() external {
    ERC20RoleProviderFactoryInputs memory providerInputs = _inputs(
      address(token),
      100e18,
      bytes32('constructor')
    );

    NameAndProviderInputs memory hookInputs;
    hookInputs.name = 'ERC20 Hook';
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
    assertEq(ERC20RoleProvider(expectedProvider).token(), address(token), 'token');
    assertEq(
      ERC20RoleProvider(expectedProvider).minBalance(),
      providerInputs.minBalance,
      'minimum balance'
    );
  }
}

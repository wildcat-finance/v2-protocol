// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import { MockERC721 } from 'solmate/test/utils/mocks/MockERC721.sol';

import 'src/access/ProviderStructs.sol';
import 'src/providers/ERC721RoleProvider.sol';
import 'src/providers/ERC721RoleProviderFactory.sol';
import 'src/providers/IERC721RoleProvider.sol';
import 'src/providers/IERC721RoleProviderFactory.sol';
import 'src/types/RoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';

contract ERC721RoleProviderFactoryCaller {
  function createRoleProvider(
    ERC721RoleProviderFactory factory,
    bytes calldata data
  ) external returns (address) {
    return factory.createRoleProvider(data);
  }
}

contract ERC721FactoryNonERC165BalanceToken {
  mapping(address account => uint256 balance) public balanceOf;

  function mint(address account) external {
    balanceOf[account] += 1;
  }
}

contract ERC721RoleProviderFactoryTest is Test {
  ERC721RoleProviderFactory internal factory;
  MockERC721 internal token;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new ERC721RoleProviderFactory();
    token = new MockERC721('Access', 'ACCESS');
  }

  function _inputs(
    address tokenAddress,
    bool skipInterfaceCheck,
    bytes32 salt
  ) internal pure returns (ERC721RoleProviderFactoryInputs memory inputs) {
    inputs.token = tokenAddress;
    inputs.skipInterfaceCheck = skipInterfaceCheck;
    inputs.salt = salt;
  }

  function testFuzz_createERC721RoleProvider(
    bool skipInterfaceCheck,
    bytes32 salt
  ) external {
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      skipInterfaceCheck,
      salt
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createERC721RoleProvider(inputs);

    assertEq(actual, expected, 'provider');
    assertGt(actual.code.length, 0, 'provider code');
    assertEq(ERC721RoleProvider(actual).token(), address(token), 'token');
    assertTrue(ERC721RoleProvider(actual).isPullProvider(), 'pull provider');
  }

  function test_createRoleProvider_GenericInterface() external {
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      false,
      bytes32('generic')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(abi.encode(inputs));

    assertEq(actual, expected, 'provider');
    assertEq(ERC721RoleProvider(actual).token(), address(token), 'token');
  }

  function test_deploymentEvent() external {
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      false,
      bytes32('event')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);

    vm.expectEmit(address(factory));
    emit IERC721RoleProviderFactory.ERC721RoleProviderDeployed(
      expected,
      address(token),
      address(this),
      inputs.salt,
      inputs.skipInterfaceCheck
    );
    factory.createERC721RoleProvider(inputs);
  }

  function test_saltIsNamespacedByCaller() external {
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      false,
      bytes32('shared')
    );
    ERC721RoleProviderFactoryCaller caller = new ERC721RoleProviderFactoryCaller();

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
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      false,
      bytes32('duplicate')
    );
    factory.createERC721RoleProvider(inputs);

    vm.expectRevert(IERC721RoleProviderFactory.RoleProviderAlreadyExists.selector);
    factory.createERC721RoleProvider(inputs);
  }

  function test_malformedInitializationReverts() external {
    vm.expectRevert();
    factory.createRoleProvider(hex'1234');

    bytes memory dirtyAddress = abi.encode(
      _inputs(address(token), false, bytes32('dirty-address'))
    );
    assembly {
      mstore(add(dirtyAddress, 0x20), or(mload(add(dirtyAddress, 0x20)), shl(160, 1)))
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyAddress);

    bytes memory dirtyBoolean = abi.encode(
      _inputs(address(token), false, bytes32('dirty-bool'))
    );
    assembly {
      mstore(add(dirtyBoolean, 0x40), 2)
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyBoolean);
  }

  function test_invalidTokenReverts() external {
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(0),
      false,
      bytes32('invalid')
    );
    vm.expectRevert(IERC721RoleProvider.InvalidTokenAddress.selector);
    factory.createERC721RoleProvider(inputs);
  }

  function test_invalidInterfaceReverts() external {
    ERC721FactoryNonERC165BalanceToken nonErc165 = new ERC721FactoryNonERC165BalanceToken();
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(nonErc165),
      false,
      bytes32('interface')
    );
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    factory.createERC721RoleProvider(inputs);
  }

  function test_skipInterfaceCheckCreatesUsableProvider() external {
    ERC721FactoryNonERC165BalanceToken nonErc165 = new ERC721FactoryNonERC165BalanceToken();
    nonErc165.mint(address(this));
    ERC721RoleProviderFactoryInputs memory inputs = _inputs(
      address(nonErc165),
      true,
      bytes32('skip')
    );

    address provider = factory.createERC721RoleProvider(inputs);
    assertEq(
      ERC721RoleProvider(provider).getCredential(address(this)),
      uint32(block.timestamp),
      'credential'
    );
  }

  function test_hookConstructorCreatesAndAttachesProvider() external {
    ERC721RoleProviderFactoryInputs memory providerInputs = _inputs(
      address(token),
      false,
      bytes32('constructor')
    );

    NameAndProviderInputs memory hookInputs;
    hookInputs.name = 'ERC721 Hook';
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
    assertEq(ERC721RoleProvider(expectedProvider).token(), address(token), 'token');
  }
}

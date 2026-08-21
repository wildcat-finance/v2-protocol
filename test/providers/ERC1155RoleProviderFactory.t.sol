// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import { MockERC1155 } from 'solmate/test/utils/mocks/MockERC1155.sol';

import 'src/access/ProviderStructs.sol';
import 'src/providers/ERC1155RoleProvider.sol';
import 'src/providers/ERC1155RoleProviderFactory.sol';
import 'src/providers/IERC1155RoleProvider.sol';
import 'src/providers/IERC1155RoleProviderFactory.sol';
import 'src/types/RoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';

contract ERC1155RoleProviderFactoryCaller {
  function createRoleProvider(
    ERC1155RoleProviderFactory factory,
    bytes calldata data
  ) external returns (address) {
    return factory.createRoleProvider(data);
  }
}

contract ERC1155FactoryNonERC165BalanceToken {
  mapping(address account => mapping(uint256 tokenId => uint256 balance)) public balanceOf;

  function mint(address account, uint256 tokenId, uint256 amount) external {
    balanceOf[account][tokenId] += amount;
  }
}

contract ERC1155RoleProviderFactoryTest is Test {
  ERC1155RoleProviderFactory internal factory;
  MockERC1155 internal token;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new ERC1155RoleProviderFactory();
    token = new MockERC1155();
  }

  function _inputs(
    address tokenAddress,
    uint256 tokenId,
    bool skipInterfaceCheck,
    bytes32 salt
  ) internal pure returns (ERC1155RoleProviderFactoryInputs memory inputs) {
    inputs.token = tokenAddress;
    inputs.tokenId = tokenId;
    inputs.skipInterfaceCheck = skipInterfaceCheck;
    inputs.salt = salt;
  }

  function testFuzz_createERC1155RoleProvider(
    uint256 tokenId,
    bool skipInterfaceCheck,
    bytes32 salt
  ) external {
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      tokenId,
      skipInterfaceCheck,
      salt
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createERC1155RoleProvider(inputs);

    assertEq(actual, expected, 'provider');
    assertGt(actual.code.length, 0, 'provider code');
    assertEq(ERC1155RoleProvider(actual).token(), address(token), 'token');
    assertEq(ERC1155RoleProvider(actual).tokenId(), tokenId, 'token ID');
    assertTrue(ERC1155RoleProvider(actual).isPullProvider(), 'pull provider');
  }

  function test_createRoleProvider_GenericInterface() external {
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      42,
      false,
      bytes32('generic')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(abi.encode(inputs));

    assertEq(actual, expected, 'provider');
    assertEq(ERC1155RoleProvider(actual).token(), address(token), 'token');
    assertEq(ERC1155RoleProvider(actual).tokenId(), inputs.tokenId, 'token ID');
  }

  function test_deploymentEvent() external {
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      42,
      false,
      bytes32('event')
    );
    address expected = factory.computeRoleProviderAddress(address(this), inputs);

    vm.expectEmit(address(factory));
    emit IERC1155RoleProviderFactory.ERC1155RoleProviderDeployed(
      expected,
      address(token),
      address(this),
      inputs.salt,
      inputs.tokenId,
      inputs.skipInterfaceCheck
    );
    factory.createERC1155RoleProvider(inputs);
  }

  function test_saltIsNamespacedByCaller() external {
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      42,
      false,
      bytes32('shared')
    );
    ERC1155RoleProviderFactoryCaller caller = new ERC1155RoleProviderFactoryCaller();

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
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(token),
      42,
      false,
      bytes32('duplicate')
    );
    factory.createERC1155RoleProvider(inputs);

    vm.expectRevert(IERC1155RoleProviderFactory.RoleProviderAlreadyExists.selector);
    factory.createERC1155RoleProvider(inputs);
  }

  function test_malformedInitializationReverts() external {
    vm.expectRevert();
    factory.createRoleProvider(hex'1234');

    bytes memory dirtyAddress = abi.encode(
      _inputs(address(token), 42, false, bytes32('dirty-address'))
    );
    assembly {
      mstore(add(dirtyAddress, 0x20), or(mload(add(dirtyAddress, 0x20)), shl(160, 1)))
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyAddress);

    bytes memory dirtyBoolean = abi.encode(
      _inputs(address(token), 42, false, bytes32('dirty-bool'))
    );
    assembly {
      mstore(add(dirtyBoolean, 0x60), 2)
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyBoolean);
  }

  function test_invalidTokenReverts() external {
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(0),
      42,
      false,
      bytes32('invalid')
    );
    vm.expectRevert(IERC1155RoleProvider.InvalidTokenAddress.selector);
    factory.createERC1155RoleProvider(inputs);
  }

  function test_invalidInterfaceReverts() external {
    ERC1155FactoryNonERC165BalanceToken nonErc165 = new ERC1155FactoryNonERC165BalanceToken();
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(nonErc165),
      42,
      false,
      bytes32('interface')
    );
    vm.expectRevert(IERC1155RoleProvider.InvalidERC1155.selector);
    factory.createERC1155RoleProvider(inputs);
  }

  function test_skipInterfaceCheckCreatesUsableProvider() external {
    uint256 tokenId = 42;
    ERC1155FactoryNonERC165BalanceToken nonErc165 = new ERC1155FactoryNonERC165BalanceToken();
    nonErc165.mint(address(this), tokenId, 1);
    ERC1155RoleProviderFactoryInputs memory inputs = _inputs(
      address(nonErc165),
      tokenId,
      true,
      bytes32('skip')
    );

    address provider = factory.createERC1155RoleProvider(inputs);
    assertEq(
      ERC1155RoleProvider(provider).getCredential(address(this)),
      uint32(block.timestamp),
      'credential'
    );
  }

  function test_hookConstructorCreatesAndAttachesProvider() external {
    ERC1155RoleProviderFactoryInputs memory providerInputs = _inputs(
      address(token),
      42,
      false,
      bytes32('constructor')
    );

    NameAndProviderInputs memory hookInputs;
    hookInputs.name = 'ERC1155 Hook';
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
    assertEq(ERC1155RoleProvider(expectedProvider).token(), address(token), 'token');
    assertEq(
      ERC1155RoleProvider(expectedProvider).tokenId(),
      providerInputs.tokenId,
      'token ID'
    );
  }
}

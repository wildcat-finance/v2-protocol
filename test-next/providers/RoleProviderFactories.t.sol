// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { IRoleProviderFactory } from 'src/access/IRoleProviderFactory.sol';
import { CreateProviderInputs, NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { AccessListRoleProvider } from 'src/providers/AccessListRoleProvider.sol';
import { AccessListRoleProviderFactory } from 'src/providers/AccessListRoleProviderFactory.sol';
import { AccessListRoleProviderFactoryInputs, IAccessListRoleProviderFactory } from 'src/providers/IAccessListRoleProviderFactory.sol';
import { ERC20RoleProvider } from 'src/providers/ERC20RoleProvider.sol';
import { ERC20RoleProviderFactory } from 'src/providers/ERC20RoleProviderFactory.sol';
import { ERC20RoleProviderFactoryInputs, IERC20RoleProviderFactory } from 'src/providers/IERC20RoleProviderFactory.sol';
import { IERC20RoleProvider } from 'src/providers/IERC20RoleProvider.sol';
import { ERC721RoleProvider } from 'src/providers/ERC721RoleProvider.sol';
import { ERC721RoleProviderFactory } from 'src/providers/ERC721RoleProviderFactory.sol';
import { IERC721RoleProvider } from 'src/providers/IERC721RoleProvider.sol';
import { ERC721RoleProviderFactoryInputs, IERC721RoleProviderFactory } from 'src/providers/IERC721RoleProviderFactory.sol';
import { ERC1155RoleProvider } from 'src/providers/ERC1155RoleProvider.sol';
import { ERC1155RoleProviderFactory } from 'src/providers/ERC1155RoleProviderFactory.sol';
import { IERC1155RoleProvider } from 'src/providers/IERC1155RoleProvider.sol';
import { ERC1155RoleProviderFactoryInputs, IERC1155RoleProviderFactory } from 'src/providers/IERC1155RoleProviderFactory.sol';
import { ERC4626AssetsRoleProvider } from 'src/providers/ERC4626AssetsRoleProvider.sol';
import { ERC4626AssetsRoleProviderFactory } from 'src/providers/ERC4626AssetsRoleProviderFactory.sol';
import { IERC4626AssetsRoleProvider } from 'src/providers/IERC4626AssetsRoleProvider.sol';
import { ERC4626AssetsRoleProviderFactoryInputs, IERC4626AssetsRoleProviderFactory } from 'src/providers/IERC4626AssetsRoleProviderFactory.sol';
import { MerkleRoleProvider } from 'src/providers/MerkleRoleProvider.sol';
import { MerkleRoleProviderFactory } from 'src/providers/MerkleRoleProviderFactory.sol';
import { IMerkleRoleProviderFactory, MerkleRoleProviderFactoryInputs } from 'src/providers/IMerkleRoleProviderFactory.sol';
import { RoleProvider } from 'src/types/RoleProvider.sol';
import { FactoryBalanceTokenMock, FactoryERC165TokenMock, RoleProviderFactoryCaller } from '../mocks/RoleProviderFactoryMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

enum FactoryKind {
  AccessList,
  ERC20,
  ERC721,
  ERC1155,
  ERC4626,
  Merkle
}

struct FactoryCase {
  FactoryKind kind;
  address factory;
  bytes inputs;
}

contract RoleProviderFactoriesTest is TestKernel {
  address internal constant Alice = address(0xA11CE);
  address internal constant Administrator = address(0xAD111);
  uint256 internal constant FactoryCount = 6;
  uint256 internal constant DefaultMinimum = 100e18;
  uint256 internal constant DefaultTokenId = 42;

  address[FactoryCount] internal factories;
  FactoryBalanceTokenMock internal balanceToken;
  FactoryBalanceTokenMock internal nonERC165Token;
  FactoryERC165TokenMock internal erc721Token;
  FactoryERC165TokenMock internal erc1155Token;
  RoleProviderFactoryCaller internal alternateCaller;

  function setUp() external {
    vm.warp(1_714_737_030);
    factories[uint256(FactoryKind.AccessList)] = _deployCode(
      'src/providers/AccessListRoleProviderFactory.sol:AccessListRoleProviderFactory'
    );
    factories[uint256(FactoryKind.ERC20)] = _deployCode(
      'src/providers/ERC20RoleProviderFactory.sol:ERC20RoleProviderFactory'
    );
    factories[uint256(FactoryKind.ERC721)] = _deployCode(
      'src/providers/ERC721RoleProviderFactory.sol:ERC721RoleProviderFactory'
    );
    factories[uint256(FactoryKind.ERC1155)] = _deployCode(
      'src/providers/ERC1155RoleProviderFactory.sol:ERC1155RoleProviderFactory'
    );
    factories[uint256(FactoryKind.ERC4626)] = _deployCode(
      'src/providers/ERC4626AssetsRoleProviderFactory.sol:ERC4626AssetsRoleProviderFactory'
    );
    factories[uint256(FactoryKind.Merkle)] = _deployCode(
      'src/providers/MerkleRoleProviderFactory.sol:MerkleRoleProviderFactory'
    );

    balanceToken = FactoryBalanceTokenMock(
      _deployCode('test-next/mocks/RoleProviderFactoryMocks.sol:FactoryBalanceTokenMock')
    );
    nonERC165Token = FactoryBalanceTokenMock(
      _deployCode('test-next/mocks/RoleProviderFactoryMocks.sol:FactoryBalanceTokenMock')
    );
    erc721Token = FactoryERC165TokenMock(
      _deployCode(
        'test-next/mocks/RoleProviderFactoryMocks.sol:FactoryERC165TokenMock',
        abi.encode(bytes4(0x80ac58cd))
      )
    );
    erc1155Token = FactoryERC165TokenMock(
      _deployCode(
        'test-next/mocks/RoleProviderFactoryMocks.sol:FactoryERC165TokenMock',
        abi.encode(bytes4(0xd9b67a26))
      )
    );
    alternateCaller = RoleProviderFactoryCaller(
      _deployCode('test-next/mocks/RoleProviderFactoryMocks.sol:RoleProviderFactoryCaller')
    );
  }

  // ========================================================================== //
  //                                Case matrix                                 //
  // ========================================================================== //

  function _factory(FactoryKind kind) internal view returns (address) {
    return factories[uint256(kind)];
  }

  function _case(
    FactoryKind kind,
    bytes32 salt
  ) internal view returns (FactoryCase memory testCase) {
    testCase.kind = kind;
    testCase.factory = _factory(kind);

    if (kind == FactoryKind.AccessList) {
      address[] memory initialMembers = new address[](1);
      initialMembers[0] = Alice;
      testCase.inputs = abi.encode(
        AccessListRoleProviderFactoryInputs({
          administrator: Administrator,
          initialMembers: initialMembers,
          salt: salt
        })
      );
    } else if (kind == FactoryKind.ERC20) {
      testCase.inputs = abi.encode(
        ERC20RoleProviderFactoryInputs({
          token: address(balanceToken),
          minBalance: DefaultMinimum,
          salt: salt
        })
      );
    } else if (kind == FactoryKind.ERC721) {
      testCase.inputs = abi.encode(
        ERC721RoleProviderFactoryInputs({
          token: address(erc721Token),
          skipInterfaceCheck: false,
          salt: salt
        })
      );
    } else if (kind == FactoryKind.ERC1155) {
      testCase.inputs = abi.encode(
        ERC1155RoleProviderFactoryInputs({
          token: address(erc1155Token),
          tokenId: DefaultTokenId,
          skipInterfaceCheck: false,
          salt: salt
        })
      );
    } else if (kind == FactoryKind.ERC4626) {
      testCase.inputs = abi.encode(
        ERC4626AssetsRoleProviderFactoryInputs({
          vault: address(balanceToken),
          minAssets: DefaultMinimum,
          salt: salt
        })
      );
    } else {
      testCase.inputs = abi.encode(
        MerkleRoleProviderFactoryInputs({
          administrator: Administrator,
          root: keccak256('root'),
          salt: salt
        })
      );
    }
  }

  function _computeProviderAddress(
    FactoryCase memory testCase,
    address deployer
  ) internal view returns (address provider) {
    if (testCase.kind == FactoryKind.AccessList) {
      return
        AccessListRoleProviderFactory(testCase.factory).computeRoleProviderAddress(
          deployer,
          abi.decode(testCase.inputs, (AccessListRoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC20) {
      return
        ERC20RoleProviderFactory(testCase.factory).computeRoleProviderAddress(
          deployer,
          abi.decode(testCase.inputs, (ERC20RoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC721) {
      return
        ERC721RoleProviderFactory(testCase.factory).computeRoleProviderAddress(
          deployer,
          abi.decode(testCase.inputs, (ERC721RoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC1155) {
      return
        ERC1155RoleProviderFactory(testCase.factory).computeRoleProviderAddress(
          deployer,
          abi.decode(testCase.inputs, (ERC1155RoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC4626) {
      return
        ERC4626AssetsRoleProviderFactory(testCase.factory).computeRoleProviderAddress(
          deployer,
          abi.decode(testCase.inputs, (ERC4626AssetsRoleProviderFactoryInputs))
        );
    }
    return
      MerkleRoleProviderFactory(testCase.factory).computeRoleProviderAddress(
        deployer,
        abi.decode(testCase.inputs, (MerkleRoleProviderFactoryInputs))
      );
  }

  function _createTyped(FactoryCase memory testCase) internal returns (address provider) {
    if (testCase.kind == FactoryKind.AccessList) {
      return
        AccessListRoleProviderFactory(testCase.factory).createAccessListRoleProvider(
          abi.decode(testCase.inputs, (AccessListRoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC20) {
      return
        ERC20RoleProviderFactory(testCase.factory).createERC20RoleProvider(
          abi.decode(testCase.inputs, (ERC20RoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC721) {
      return
        ERC721RoleProviderFactory(testCase.factory).createERC721RoleProvider(
          abi.decode(testCase.inputs, (ERC721RoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC1155) {
      return
        ERC1155RoleProviderFactory(testCase.factory).createERC1155RoleProvider(
          abi.decode(testCase.inputs, (ERC1155RoleProviderFactoryInputs))
        );
    }
    if (testCase.kind == FactoryKind.ERC4626) {
      return
        ERC4626AssetsRoleProviderFactory(testCase.factory).createERC4626AssetsRoleProvider(
          abi.decode(testCase.inputs, (ERC4626AssetsRoleProviderFactoryInputs))
        );
    }
    return
      MerkleRoleProviderFactory(testCase.factory).createMerkleRoleProvider(
        abi.decode(testCase.inputs, (MerkleRoleProviderFactoryInputs))
      );
  }

  function _assertProvider(FactoryCase memory testCase, address provider) internal view {
    assertTrue(provider.code.length > 0, 'provider code');
    assertEq(
      IRoleProvider(provider).isPullProvider(),
      testCase.kind != FactoryKind.Merkle,
      'provider kind'
    );

    if (testCase.kind == FactoryKind.AccessList) {
      AccessListRoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (AccessListRoleProviderFactoryInputs)
      );
      assertEq(AccessListRoleProvider(provider).administrator(), inputs.administrator);
      assertTrue(AccessListRoleProvider(provider).isMember(inputs.initialMembers[0]));
    } else if (testCase.kind == FactoryKind.ERC20) {
      ERC20RoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC20RoleProviderFactoryInputs)
      );
      assertEq(ERC20RoleProvider(provider).token(), inputs.token);
      assertEq(ERC20RoleProvider(provider).minBalance(), inputs.minBalance);
    } else if (testCase.kind == FactoryKind.ERC721) {
      ERC721RoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC721RoleProviderFactoryInputs)
      );
      assertEq(ERC721RoleProvider(provider).token(), inputs.token);
    } else if (testCase.kind == FactoryKind.ERC1155) {
      ERC1155RoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC1155RoleProviderFactoryInputs)
      );
      assertEq(ERC1155RoleProvider(provider).token(), inputs.token);
      assertEq(ERC1155RoleProvider(provider).tokenId(), inputs.tokenId);
    } else if (testCase.kind == FactoryKind.ERC4626) {
      ERC4626AssetsRoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC4626AssetsRoleProviderFactoryInputs)
      );
      assertEq(ERC4626AssetsRoleProvider(provider).vault(), inputs.vault);
      assertEq(ERC4626AssetsRoleProvider(provider).minAssets(), inputs.minAssets);
    } else {
      MerkleRoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (MerkleRoleProviderFactoryInputs)
      );
      assertEq(MerkleRoleProvider(provider).administrator(), inputs.administrator);
      assertEq(MerkleRoleProvider(provider).root(), inputs.root);
    }
  }

  function _expectDeploymentEvent(
    FactoryCase memory testCase,
    address provider,
    address deployer
  ) internal {
    vm.expectEmit(testCase.factory);
    if (testCase.kind == FactoryKind.AccessList) {
      AccessListRoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (AccessListRoleProviderFactoryInputs)
      );
      emit IAccessListRoleProviderFactory.AccessListRoleProviderDeployed(
        provider,
        inputs.administrator,
        deployer,
        inputs.salt,
        inputs.initialMembers
      );
    } else if (testCase.kind == FactoryKind.ERC20) {
      ERC20RoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC20RoleProviderFactoryInputs)
      );
      emit IERC20RoleProviderFactory.ERC20RoleProviderDeployed(
        provider,
        inputs.token,
        deployer,
        inputs.salt,
        inputs.minBalance
      );
    } else if (testCase.kind == FactoryKind.ERC721) {
      ERC721RoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC721RoleProviderFactoryInputs)
      );
      emit IERC721RoleProviderFactory.ERC721RoleProviderDeployed(
        provider,
        inputs.token,
        deployer,
        inputs.salt,
        inputs.skipInterfaceCheck
      );
    } else if (testCase.kind == FactoryKind.ERC1155) {
      ERC1155RoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC1155RoleProviderFactoryInputs)
      );
      emit IERC1155RoleProviderFactory.ERC1155RoleProviderDeployed(
        provider,
        inputs.token,
        deployer,
        inputs.salt,
        inputs.tokenId,
        inputs.skipInterfaceCheck
      );
    } else if (testCase.kind == FactoryKind.ERC4626) {
      ERC4626AssetsRoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (ERC4626AssetsRoleProviderFactoryInputs)
      );
      emit IERC4626AssetsRoleProviderFactory.ERC4626AssetsRoleProviderDeployed(
        provider,
        inputs.vault,
        deployer,
        inputs.salt,
        inputs.minAssets
      );
    } else {
      MerkleRoleProviderFactoryInputs memory inputs = abi.decode(
        testCase.inputs,
        (MerkleRoleProviderFactoryInputs)
      );
      emit IMerkleRoleProviderFactory.MerkleRoleProviderDeployed(
        provider,
        inputs.administrator,
        deployer,
        inputs.salt,
        inputs.root
      );
    }
  }

  // ========================================================================== //
  //                             Typed entry points                             //
  // ========================================================================== //

  function testFuzz_typedAccessListFactoryCreatesExpectedProvider(bytes32 salt) external {
    FactoryCase memory testCase = _case(FactoryKind.AccessList, salt);
    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);

    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  function testFuzz_typedERC20FactoryCreatesExpectedProvider(
    uint128 minimumSeed,
    bytes32 salt
  ) external {
    FactoryCase memory testCase = _case(FactoryKind.ERC20, salt);
    ERC20RoleProviderFactoryInputs memory inputs = abi.decode(
      testCase.inputs,
      (ERC20RoleProviderFactoryInputs)
    );
    inputs.minBalance = bound(uint256(minimumSeed), 1, type(uint128).max);
    testCase.inputs = abi.encode(inputs);

    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);
    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  function testFuzz_typedERC721FactoryCreatesExpectedProvider(
    bool skipInterfaceCheck,
    bytes32 salt
  ) external {
    FactoryCase memory testCase = _case(FactoryKind.ERC721, salt);
    ERC721RoleProviderFactoryInputs memory inputs = abi.decode(
      testCase.inputs,
      (ERC721RoleProviderFactoryInputs)
    );
    inputs.skipInterfaceCheck = skipInterfaceCheck;
    testCase.inputs = abi.encode(inputs);

    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);
    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  function testFuzz_typedERC1155FactoryCreatesExpectedProvider(
    uint256 tokenId,
    bool skipInterfaceCheck,
    bytes32 salt
  ) external {
    FactoryCase memory testCase = _case(FactoryKind.ERC1155, salt);
    ERC1155RoleProviderFactoryInputs memory inputs = abi.decode(
      testCase.inputs,
      (ERC1155RoleProviderFactoryInputs)
    );
    inputs.tokenId = tokenId;
    inputs.skipInterfaceCheck = skipInterfaceCheck;
    testCase.inputs = abi.encode(inputs);

    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);
    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  function testFuzz_typedERC4626FactoryCreatesExpectedProvider(
    uint128 minimumSeed,
    bytes32 salt
  ) external {
    FactoryCase memory testCase = _case(FactoryKind.ERC4626, salt);
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = abi.decode(
      testCase.inputs,
      (ERC4626AssetsRoleProviderFactoryInputs)
    );
    inputs.minAssets = bound(uint256(minimumSeed), 1, type(uint128).max);
    testCase.inputs = abi.encode(inputs);

    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);
    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  function testFuzz_typedMerkleFactoryCreatesExpectedProvider(
    address administrator,
    bytes32 root,
    bytes32 salt
  ) external {
    if (administrator == address(0)) administrator = Administrator;
    FactoryCase memory testCase = _case(FactoryKind.Merkle, salt);
    MerkleRoleProviderFactoryInputs memory inputs = abi.decode(
      testCase.inputs,
      (MerkleRoleProviderFactoryInputs)
    );
    inputs.administrator = administrator;
    inputs.root = root;
    testCase.inputs = abi.encode(inputs);

    address expected = _computeProviderAddress(testCase, address(this));
    address actual = _createTyped(testCase);
    assertEq(actual, expected, 'provider');
    _assertProvider(testCase, actual);
  }

  // ========================================================================== //
  //                         Shared factory behavior                            //
  // ========================================================================== //

  function test_genericInterfaceCreatesExpectedProviders() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(
        FactoryKind(rawKind),
        keccak256(abi.encode('generic', rawKind))
      );
      address expected = _computeProviderAddress(testCase, address(this));
      address actual = IRoleProviderFactory(testCase.factory).createRoleProvider(testCase.inputs);

      assertEq(actual, expected, 'provider');
      _assertProvider(testCase, actual);
    }
  }

  function test_deploymentEvents() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(
        FactoryKind(rawKind),
        keccak256(abi.encode('event', rawKind))
      );
      address expected = _computeProviderAddress(testCase, address(this));
      _expectDeploymentEvent(testCase, expected, address(this));
      _createTyped(testCase);
    }
  }

  function test_saltsAreNamespacedByCaller() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(
        FactoryKind(rawKind),
        keccak256(abi.encode('shared', rawKind))
      );
      address first = IRoleProviderFactory(testCase.factory).createRoleProvider(testCase.inputs);
      address second = alternateCaller.createRoleProvider(testCase.factory, testCase.inputs);

      assertTrue(first != second, 'provider addresses');
      assertEq(
        second,
        _computeProviderAddress(testCase, address(alternateCaller)),
        'namespaced address'
      );
    }
  }

  function test_duplicateDeploymentsRevert() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(
        FactoryKind(rawKind),
        keccak256(abi.encode('duplicate', rawKind))
      );
      _createTyped(testCase);

      vm.expectRevert(IAccessListRoleProviderFactory.RoleProviderAlreadyExists.selector);
      _createTyped(testCase);
    }
  }

  function test_malformedGenericInputsRevert() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      vm.expectRevert();
      IRoleProviderFactory(_factory(FactoryKind(rawKind))).createRoleProvider(hex'1234');
    }
  }

  function test_invalidPrimaryAddressesRevert() external {
    address[] memory noMembers = new address[](0);

    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    AccessListRoleProviderFactory(_factory(FactoryKind.AccessList)).createAccessListRoleProvider(
      AccessListRoleProviderFactoryInputs({
        administrator: address(0),
        initialMembers: noMembers,
        salt: bytes32('access')
      })
    );

    vm.expectRevert(IERC20RoleProvider.InvalidTokenAddress.selector);
    ERC20RoleProviderFactory(_factory(FactoryKind.ERC20)).createERC20RoleProvider(
      ERC20RoleProviderFactoryInputs({
        token: address(0),
        minBalance: DefaultMinimum,
        salt: bytes32('erc20')
      })
    );

    vm.expectRevert(IERC721RoleProvider.InvalidTokenAddress.selector);
    ERC721RoleProviderFactory(_factory(FactoryKind.ERC721)).createERC721RoleProvider(
      ERC721RoleProviderFactoryInputs({
        token: address(0),
        skipInterfaceCheck: false,
        salt: bytes32('erc721')
      })
    );

    vm.expectRevert(IERC1155RoleProvider.InvalidTokenAddress.selector);
    ERC1155RoleProviderFactory(_factory(FactoryKind.ERC1155)).createERC1155RoleProvider(
      ERC1155RoleProviderFactoryInputs({
        token: address(0),
        tokenId: DefaultTokenId,
        skipInterfaceCheck: false,
        salt: bytes32('erc1155')
      })
    );

    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidVaultAddress.selector);
    ERC4626AssetsRoleProviderFactory(_factory(FactoryKind.ERC4626)).createERC4626AssetsRoleProvider(
      ERC4626AssetsRoleProviderFactoryInputs({
        vault: address(0),
        minAssets: DefaultMinimum,
        salt: bytes32('erc4626')
      })
    );

    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    MerkleRoleProviderFactory(_factory(FactoryKind.Merkle)).createMerkleRoleProvider(
      MerkleRoleProviderFactoryInputs({
        administrator: address(0),
        root: keccak256('root'),
        salt: bytes32('merkle')
      })
    );
  }

  // ========================================================================== //
  //                        Variant-specific behavior                           //
  // ========================================================================== //

  function test_zeroMinimumsRevert() external {
    vm.expectRevert(IERC20RoleProvider.InvalidMinimumBalance.selector);
    ERC20RoleProviderFactory(_factory(FactoryKind.ERC20)).createERC20RoleProvider(
      ERC20RoleProviderFactoryInputs({
        token: address(balanceToken),
        minBalance: 0,
        salt: bytes32('erc20 zero')
      })
    );

    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidMinimumAssets.selector);
    ERC4626AssetsRoleProviderFactory(_factory(FactoryKind.ERC4626)).createERC4626AssetsRoleProvider(
      ERC4626AssetsRoleProviderFactoryInputs({
        vault: address(balanceToken),
        minAssets: 0,
        salt: bytes32('erc4626 zero')
      })
    );
  }

  function test_invalidTokenInterfacesRevert() external {
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    ERC721RoleProviderFactory(_factory(FactoryKind.ERC721)).createERC721RoleProvider(
      ERC721RoleProviderFactoryInputs({
        token: address(nonERC165Token),
        skipInterfaceCheck: false,
        salt: bytes32('erc721 interface')
      })
    );

    vm.expectRevert(IERC1155RoleProvider.InvalidERC1155.selector);
    ERC1155RoleProviderFactory(_factory(FactoryKind.ERC1155)).createERC1155RoleProvider(
      ERC1155RoleProviderFactoryInputs({
        token: address(nonERC165Token),
        tokenId: DefaultTokenId,
        skipInterfaceCheck: false,
        salt: bytes32('erc1155 interface')
      })
    );
  }

  function test_skippingTokenInterfaceChecksCreatesUsableProviders() external {
    nonERC165Token.setBalance(address(this), 1);
    nonERC165Token.setBalance(address(this), DefaultTokenId, 1);

    address erc721Provider = ERC721RoleProviderFactory(_factory(FactoryKind.ERC721))
      .createERC721RoleProvider(
        ERC721RoleProviderFactoryInputs({
          token: address(nonERC165Token),
          skipInterfaceCheck: true,
          salt: bytes32('erc721 skip')
        })
      );
    assertEq(
      ERC721RoleProvider(erc721Provider).getCredential(address(this)),
      uint32(block.timestamp),
      'ERC721 credential'
    );

    address erc1155Provider = ERC1155RoleProviderFactory(_factory(FactoryKind.ERC1155))
      .createERC1155RoleProvider(
        ERC1155RoleProviderFactoryInputs({
          token: address(nonERC165Token),
          tokenId: DefaultTokenId,
          skipInterfaceCheck: true,
          salt: bytes32('erc1155 skip')
        })
      );
    assertEq(
      ERC1155RoleProvider(erc1155Provider).getCredential(address(this)),
      uint32(block.timestamp),
      'ERC1155 credential'
    );
  }

  function test_merkleZeroRootIsAllowed() external {
    FactoryCase memory testCase = _case(FactoryKind.Merkle, bytes32('empty'));
    MerkleRoleProviderFactoryInputs memory inputs = abi.decode(
      testCase.inputs,
      (MerkleRoleProviderFactoryInputs)
    );
    inputs.root = bytes32(0);
    testCase.inputs = abi.encode(inputs);

    MerkleRoleProvider provider = MerkleRoleProvider(_createTyped(testCase));
    bytes32[] memory proof = new bytes32[](0);
    assertEq(provider.root(), bytes32(0), 'root');
    assertFalse(provider.isMember(Administrator, proof), 'member');
  }

  function test_merkleFactoryHasNoProviderAuthority() external {
    FactoryCase memory testCase = _case(FactoryKind.Merkle, bytes32('authority'));
    MerkleRoleProvider provider = MerkleRoleProvider(_createTyped(testCase));

    vm.prank(testCase.factory);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.updateRoot(keccak256('next root'));
  }

  function test_hookConstructorsCreateAndAttachProviders() external {
    for (uint256 rawKind; rawKind < FactoryCount; rawKind++) {
      FactoryCase memory testCase = _case(
        FactoryKind(rawKind),
        keccak256(abi.encode('hook constructor', rawKind))
      );
      NameAndProviderInputs memory hookInputs;
      hookInputs.name = 'Factory matrix hook';
      hookInputs.roleProviderFactory = testCase.factory;
      hookInputs.newProviderInputs = new CreateProviderInputs[](1);
      hookInputs.newProviderInputs[0] = CreateProviderInputs({
        timeToLive: 0,
        providerFactoryCalldata: testCase.inputs
      });

      OpenTermHooks hooks = OpenTermHooks(
        _deployCode(
          'src/access/OpenTermHooks.sol:OpenTermHooks',
          abi.encode(address(this), abi.encode(hookInputs))
        )
      );
      address expected = _computeProviderAddress(testCase, address(hooks));
      RoleProvider[] memory providers = testCase.kind == FactoryKind.Merkle
        ? hooks.getPushProviders()
        : hooks.getPullProviders();

      assertEq(providers.length, 1, 'provider count');
      assertEq(providers[0].providerAddress(), expected, 'provider address');
      _assertProvider(testCase, expected);
    }
  }
}

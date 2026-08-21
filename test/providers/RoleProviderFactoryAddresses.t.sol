// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.25;

import 'forge-std/Test.sol';

import 'src/providers/AccessListRoleProvider.sol';
import 'src/providers/AccessListRoleProviderFactory.sol';
import 'src/providers/ERC1155RoleProvider.sol';
import 'src/providers/ERC1155RoleProviderFactory.sol';
import 'src/providers/ERC20RoleProvider.sol';
import 'src/providers/ERC20RoleProviderFactory.sol';
import 'src/providers/ERC4626AssetsRoleProvider.sol';
import 'src/providers/ERC4626AssetsRoleProviderFactory.sol';
import 'src/providers/ERC721RoleProvider.sol';
import 'src/providers/ERC721RoleProviderFactory.sol';
import 'src/providers/MerkleRoleProvider.sol';
import 'src/providers/MerkleRoleProviderFactory.sol';

contract RoleProviderFactoryAddressesTest is Test {
  AccessListRoleProviderFactory internal accessListFactory;
  ERC20RoleProviderFactory internal erc20Factory;
  ERC721RoleProviderFactory internal erc721Factory;
  ERC1155RoleProviderFactory internal erc1155Factory;
  ERC4626AssetsRoleProviderFactory internal erc4626Factory;
  MerkleRoleProviderFactory internal merkleFactory;

  address internal constant Deployer = address(0x1234);
  address internal constant Target = address(0x5678);
  bytes32 internal constant Salt = bytes32('salt');

  function setUp() external {
    accessListFactory = new AccessListRoleProviderFactory();
    erc20Factory = new ERC20RoleProviderFactory();
    erc721Factory = new ERC721RoleProviderFactory();
    erc1155Factory = new ERC1155RoleProviderFactory();
    erc4626Factory = new ERC4626AssetsRoleProviderFactory();
    merkleFactory = new MerkleRoleProviderFactory();
  }

  function _computeAddress(address factory, bytes memory initCode) internal pure returns (address) {
    bytes32 derivedSalt = keccak256(abi.encode(Deployer, Salt));
    return
      address(
        uint160(
          uint256(
            keccak256(abi.encodePacked(bytes1(0xff), factory, derivedSalt, keccak256(initCode)))
          )
        )
      );
  }

  function test_accessListAddressMatchesCanonicalCreate2Formula() external view {
    address[] memory initialMembers = new address[](2);
    initialMembers[0] = address(0x1111);
    initialMembers[1] = address(0x2222);
    AccessListRoleProviderFactoryInputs memory inputs = AccessListRoleProviderFactoryInputs({
      administrator: Target,
      initialMembers: initialMembers,
      salt: Salt
    });
    bytes memory initCode = abi.encodePacked(
      type(AccessListRoleProvider).creationCode,
      abi.encode(inputs.administrator, inputs.initialMembers)
    );
    assertEq(
      accessListFactory.computeRoleProviderAddress(Deployer, inputs),
      _computeAddress(address(accessListFactory), initCode)
    );
  }

  function test_erc20AddressMatchesCanonicalCreate2Formula() external view {
    ERC20RoleProviderFactoryInputs memory inputs = ERC20RoleProviderFactoryInputs({
      token: Target,
      minBalance: 123,
      salt: Salt
    });
    bytes memory initCode = abi.encodePacked(
      type(ERC20RoleProvider).creationCode,
      abi.encode(inputs.token, inputs.minBalance)
    );
    assertEq(
      erc20Factory.computeRoleProviderAddress(Deployer, inputs),
      _computeAddress(address(erc20Factory), initCode)
    );
  }

  function test_erc721AddressMatchesCanonicalCreate2Formula() external view {
    ERC721RoleProviderFactoryInputs memory inputs = ERC721RoleProviderFactoryInputs({
      token: Target,
      skipInterfaceCheck: true,
      salt: Salt
    });
    bytes memory initCode = abi.encodePacked(
      type(ERC721RoleProvider).creationCode,
      abi.encode(inputs.token, inputs.skipInterfaceCheck)
    );
    assertEq(
      erc721Factory.computeRoleProviderAddress(Deployer, inputs),
      _computeAddress(address(erc721Factory), initCode)
    );
  }

  function test_erc1155AddressMatchesCanonicalCreate2Formula() external view {
    ERC1155RoleProviderFactoryInputs memory inputs = ERC1155RoleProviderFactoryInputs({
      token: Target,
      tokenId: 123,
      skipInterfaceCheck: true,
      salt: Salt
    });
    bytes memory initCode = abi.encodePacked(
      type(ERC1155RoleProvider).creationCode,
      abi.encode(inputs.token, inputs.tokenId, inputs.skipInterfaceCheck)
    );
    assertEq(
      erc1155Factory.computeRoleProviderAddress(Deployer, inputs),
      _computeAddress(address(erc1155Factory), initCode)
    );
  }

  function test_erc4626AddressMatchesCanonicalCreate2Formula() external view {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = ERC4626AssetsRoleProviderFactoryInputs({
      vault: Target,
      minAssets: 123,
      salt: Salt
    });
    bytes memory initCode = abi.encodePacked(
      type(ERC4626AssetsRoleProvider).creationCode,
      abi.encode(inputs.vault, inputs.minAssets)
    );
    assertEq(
      erc4626Factory.computeRoleProviderAddress(Deployer, inputs),
      _computeAddress(address(erc4626Factory), initCode)
    );
  }

  function test_merkleAddressMatchesCanonicalCreate2Formula() external view {
    MerkleRoleProviderFactoryInputs memory inputs = MerkleRoleProviderFactoryInputs({
      administrator: Target,
      root: bytes32(uint256(123)),
      salt: Salt
    });
    bytes memory initCode = abi.encodePacked(
      type(MerkleRoleProvider).creationCode,
      abi.encode(inputs.administrator, inputs.root)
    );
    assertEq(
      merkleFactory.computeRoleProviderAddress(Deployer, inputs),
      _computeAddress(address(merkleFactory), initCode)
    );
  }
}

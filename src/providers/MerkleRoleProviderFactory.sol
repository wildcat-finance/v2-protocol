// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './MerkleRoleProvider.sol';
import './IMerkleRoleProviderFactory.sol';

/**
 * @dev Deploys Merkle providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract MerkleRoleProviderFactory is IMerkleRoleProviderFactory {
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    address administrator;
    bytes32 root;
    bytes32 salt;
    assembly {
      if lt(data.length, 0x60) {
        revert(0, 0)
      }
      administrator := calldataload(data.offset)
      if shr(160, administrator) {
        revert(0, 0)
      }
      root := calldataload(add(data.offset, 0x20))
      salt := calldataload(add(data.offset, 0x40))
    }
    provider = _createRoleProvider(msg.sender, administrator, root, salt);
  }

  function createMerkleRoleProvider(
    MerkleRoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs.administrator, inputs.root, inputs.salt);
  }

  function _createRoleProvider(
    address deployer,
    address administrator,
    bytes32 root,
    bytes32 userSalt
  ) internal returns (address provider) {
    bytes32 salt = _deriveSalt(deployer, userSalt);
    bytes memory initCode = _getRoleProviderInitCode(administrator, root);
    address expectedProvider = _computeCreate2Address(salt, keccak256(initCode));
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    assembly ('memory-safe') {
      provider := create2(0, add(initCode, 0x20), mload(initCode), salt)
    }
    if (provider == address(0)) {
      assembly ('memory-safe') {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
    emit MerkleRoleProviderDeployed(provider, administrator, deployer, userSalt, root);
  }

  function computeRoleProviderAddress(
    address deployer,
    MerkleRoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    bytes32 initCodeHash = keccak256(_getRoleProviderInitCode(inputs.administrator, inputs.root));
    provider = _computeCreate2Address(_deriveSalt(deployer, inputs.salt), initCodeHash);
  }

  function _getRoleProviderInitCode(
    address administrator,
    bytes32 root
  ) internal pure returns (bytes memory initCode) {
    initCode = abi.encodePacked(
      type(MerkleRoleProvider).creationCode,
      abi.encode(administrator, root)
    );
  }

  function _computeCreate2Address(
    bytes32 salt,
    bytes32 initCodeHash
  ) internal view returns (address provider) {
    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(0x00, or(address(), 0xff0000000000000000000000000000000000000000))
      mstore(0x20, salt)
      mstore(0x40, initCodeHash)
      provider := and(keccak256(0x0b, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
      mstore(0x40, freeMemoryPointer)
    }
  }

  function _deriveSalt(address deployer, bytes32 salt) internal pure returns (bytes32) {
    assembly ('memory-safe') {
      mstore(0x00, deployer)
      mstore(0x20, salt)
      salt := keccak256(0x00, 0x40)
    }
    return salt;
  }
}

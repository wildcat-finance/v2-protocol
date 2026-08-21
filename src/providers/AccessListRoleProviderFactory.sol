// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './AccessListRoleProvider.sol';
import './IAccessListRoleProviderFactory.sol';

/**
 * @dev Deploys access-list providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract AccessListRoleProviderFactory is IAccessListRoleProviderFactory {
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    address administrator;
    bytes32 userSalt;
    address[] calldata initialMembers;
    assembly {
      if lt(data.length, 0xa0) {
        revert(0, 0)
      }
      if iszero(eq(calldataload(data.offset), 0x20)) {
        revert(0, 0)
      }
      administrator := calldataload(add(data.offset, 0x20))
      if shr(160, administrator) {
        revert(0, 0)
      }
      if iszero(eq(calldataload(add(data.offset, 0x40)), 0x60)) {
        revert(0, 0)
      }
      userSalt := calldataload(add(data.offset, 0x60))
      let membersLength := calldataload(add(data.offset, 0x80))
      if gt(membersLength, div(sub(data.length, 0xa0), 0x20)) {
        revert(0, 0)
      }
      initialMembers.offset := add(data.offset, 0xa0)
      initialMembers.length := membersLength
      let membersEnd := add(initialMembers.offset, shl(5, membersLength))
      for { let memberPointer := initialMembers.offset } lt(memberPointer, membersEnd) {
        memberPointer := add(memberPointer, 0x20)
      } {
        if shr(160, calldataload(memberPointer)) {
          revert(0, 0)
        }
      }
    }
    provider = _createRoleProvider(msg.sender, administrator, initialMembers, userSalt);
  }

  function createAccessListRoleProvider(
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(
      msg.sender,
      inputs.administrator,
      inputs.initialMembers,
      inputs.salt
    );
  }

  function _createRoleProvider(
    address deployer,
    address administrator,
    address[] calldata initialMembers,
    bytes32 userSalt
  ) internal returns (address provider) {
    bytes32 salt = _deriveSalt(deployer, userSalt);
    bytes memory initCode = _getRoleProviderInitCode(administrator, initialMembers);
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
    emit AccessListRoleProviderDeployed(
      provider,
      administrator,
      deployer,
      userSalt,
      initialMembers
    );
  }

  function computeRoleProviderAddress(
    address deployer,
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    bytes32 initCodeHash = keccak256(
      _getRoleProviderInitCode(inputs.administrator, inputs.initialMembers)
    );
    provider = _computeCreate2Address(_deriveSalt(deployer, inputs.salt), initCodeHash);
  }

  function _getRoleProviderInitCode(
    address administrator,
    address[] calldata initialMembers
  ) internal pure returns (bytes memory initCode) {
    initCode = abi.encodePacked(
      type(AccessListRoleProvider).creationCode,
      abi.encode(administrator, initialMembers)
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

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './ERC4626AssetsRoleProvider.sol';
import './IERC4626AssetsRoleProviderFactory.sol';

/**
 * @dev Deploys ERC4626 assets providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract ERC4626AssetsRoleProviderFactory is IERC4626AssetsRoleProviderFactory {
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (ERC4626AssetsRoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs.vault, inputs.minAssets, inputs.salt);
  }

  function createERC4626AssetsRoleProvider(
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs.vault, inputs.minAssets, inputs.salt);
  }

  function _createRoleProvider(
    address deployer,
    address vault,
    uint256 minAssets,
    bytes32 userSalt
  ) internal returns (address provider) {
    bytes32 salt = _deriveSalt(deployer, userSalt);
    bytes memory initCode = _getRoleProviderInitCode(vault, minAssets);
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
    emit ERC4626AssetsRoleProviderDeployed(provider, vault, deployer, userSalt, minAssets);
  }

  function computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    bytes32 initCodeHash = keccak256(_getRoleProviderInitCode(inputs.vault, inputs.minAssets));
    provider = _computeCreate2Address(_deriveSalt(deployer, inputs.salt), initCodeHash);
  }

  function _getRoleProviderInitCode(
    address vault,
    uint256 minAssets
  ) internal pure returns (bytes memory initCode) {
    initCode = abi.encodePacked(
      type(ERC4626AssetsRoleProvider).creationCode,
      abi.encode(vault, minAssets)
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

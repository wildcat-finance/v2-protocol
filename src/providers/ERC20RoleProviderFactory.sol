// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './ERC20RoleProvider.sol';
import './IERC20RoleProviderFactory.sol';

/**
 * @dev Deploys ERC20 providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract ERC20RoleProviderFactory is IERC20RoleProviderFactory {
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    address token;
    uint256 minBalance;
    bytes32 salt;
    assembly {
      if lt(data.length, 0x60) {
        revert(0, 0)
      }
      token := calldataload(data.offset)
      if shr(160, token) {
        revert(0, 0)
      }
      minBalance := calldataload(add(data.offset, 0x20))
      salt := calldataload(add(data.offset, 0x40))
    }
    provider = _createRoleProvider(msg.sender, token, minBalance, salt);
  }

  function createERC20RoleProvider(
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs.token, inputs.minBalance, inputs.salt);
  }

  function _createRoleProvider(
    address deployer,
    address token,
    uint256 minBalance,
    bytes32 userSalt
  ) internal returns (address provider) {
    bytes32 salt = _deriveSalt(deployer, userSalt);
    bytes memory initCode = _getRoleProviderInitCode(token, minBalance);
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
    emit ERC20RoleProviderDeployed(provider, token, deployer, userSalt, minBalance);
  }

  function computeRoleProviderAddress(
    address deployer,
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    bytes32 initCodeHash = keccak256(_getRoleProviderInitCode(inputs.token, inputs.minBalance));
    provider = _computeCreate2Address(_deriveSalt(deployer, inputs.salt), initCodeHash);
  }

  function _getRoleProviderInitCode(
    address token,
    uint256 minBalance
  ) internal pure returns (bytes memory initCode) {
    initCode = abi.encodePacked(
      type(ERC20RoleProvider).creationCode,
      abi.encode(token, minBalance)
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

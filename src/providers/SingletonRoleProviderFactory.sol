// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './ISingletonRoleProviderFactory.sol';
import './SingletonRoleProvider.sol';

/// @notice CREATE2 factory for immutable singleton role providers.
/// @dev Salts are namespaced by the caller, so one caller cannot consume another's address.
contract SingletonRoleProviderFactory is ISingletonRoleProviderFactory {
  function createRoleProvider(
    bytes calldata data
  ) external override returns (address provider) {
    SingletonRoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (SingletonRoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function createSingletonRoleProvider(
    SingletonRoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function computeRoleProviderAddress(
    address deployer,
    SingletonRoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  function _createRoleProvider(
    address deployer,
    SingletonRoleProviderFactoryInputs memory inputs
  ) internal returns (address provider) {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    provider = address(new SingletonRoleProvider{ salt: _deriveSalt(deployer, inputs.salt) }(inputs.lender));
    emit SingletonRoleProviderDeployed(provider, inputs.lender, deployer, inputs.salt);
  }

  function _computeRoleProviderAddress(
    address deployer,
    SingletonRoleProviderFactoryInputs memory inputs
  ) internal view returns (address provider) {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(type(SingletonRoleProvider).creationCode, abi.encode(inputs.lender))
    );
    provider = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              bytes1(0xff),
              address(this),
              _deriveSalt(deployer, inputs.salt),
              initCodeHash
            )
          )
        )
      )
    );
  }

  function _deriveSalt(address deployer, bytes32 salt) internal pure returns (bytes32) {
    return keccak256(abi.encode(deployer, salt));
  }
}

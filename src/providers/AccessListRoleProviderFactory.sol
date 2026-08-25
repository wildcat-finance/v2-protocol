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
  function createRoleProvider(
    bytes calldata data
  ) external override returns (address provider) {
    AccessListRoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (AccessListRoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function createAccessListRoleProvider(
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function _createRoleProvider(
    address deployer,
    AccessListRoleProviderFactoryInputs memory inputs
  ) internal returns (address provider) {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(
      new AccessListRoleProvider{ salt: salt }(inputs.administrator, inputs.initialMembers)
    );
    emit AccessListRoleProviderDeployed(
      provider,
      inputs.administrator,
      deployer,
      inputs.salt,
      inputs.initialMembers
    );
  }

  function computeRoleProviderAddress(
    address deployer,
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  function _computeRoleProviderAddress(
    address deployer,
    AccessListRoleProviderFactoryInputs memory inputs
  ) internal view returns (address provider) {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(
        type(AccessListRoleProvider).creationCode,
        abi.encode(inputs.administrator, inputs.initialMembers)
      )
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

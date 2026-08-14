// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './ERC1155RoleProvider.sol';
import './IERC1155RoleProviderFactory.sol';

/**
 * @dev Deploys ERC1155 providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract ERC1155RoleProviderFactory is IERC1155RoleProviderFactory {
  function createRoleProvider(
    bytes calldata data
  ) external override returns (address provider) {
    ERC1155RoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (ERC1155RoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function createERC1155RoleProvider(
    ERC1155RoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function _createRoleProvider(
    address deployer,
    ERC1155RoleProviderFactoryInputs memory inputs
  ) internal returns (address provider) {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(
      new ERC1155RoleProvider{ salt: salt }(
        inputs.token,
        inputs.tokenId,
        inputs.skipInterfaceCheck
      )
    );
    emit ERC1155RoleProviderDeployed(
      provider,
      inputs.token,
      deployer,
      inputs.salt,
      inputs.tokenId,
      inputs.skipInterfaceCheck
    );
  }

  function computeRoleProviderAddress(
    address deployer,
    ERC1155RoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  function _computeRoleProviderAddress(
    address deployer,
    ERC1155RoleProviderFactoryInputs memory inputs
  ) internal view returns (address provider) {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(
        type(ERC1155RoleProvider).creationCode,
        abi.encode(inputs.token, inputs.tokenId, inputs.skipInterfaceCheck)
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

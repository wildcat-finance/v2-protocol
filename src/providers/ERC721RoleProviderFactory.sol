// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './ERC721RoleProvider.sol';
import './IERC721RoleProviderFactory.sol';

/**
 * @dev Deploys ERC721 providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract ERC721RoleProviderFactory is IERC721RoleProviderFactory {
  function createRoleProvider(
    bytes calldata data
  ) external override returns (address provider) {
    ERC721RoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (ERC721RoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function createERC721RoleProvider(
    ERC721RoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function _createRoleProvider(
    address deployer,
    ERC721RoleProviderFactoryInputs memory inputs
  ) internal returns (address provider) {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(
      new ERC721RoleProvider{ salt: salt }(inputs.token, inputs.skipInterfaceCheck)
    );
    emit ERC721RoleProviderDeployed(
      provider,
      inputs.token,
      deployer,
      inputs.salt,
      inputs.skipInterfaceCheck
    );
  }

  function computeRoleProviderAddress(
    address deployer,
    ERC721RoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  function _computeRoleProviderAddress(
    address deployer,
    ERC721RoleProviderFactoryInputs memory inputs
  ) internal view returns (address provider) {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(
        type(ERC721RoleProvider).creationCode,
        abi.encode(inputs.token, inputs.skipInterfaceCheck)
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

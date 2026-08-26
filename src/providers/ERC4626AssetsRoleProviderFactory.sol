// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './ERC4626AssetsRoleProvider.sol';
import './IERC4626AssetsRoleProviderFactory.sol';

/**
 * @dev Deploys ERC4626 assets providers without retaining any authority over them.
 *      Salts are namespaced by the caller so another caller cannot consume a
 *      deployment address first.
 */
contract ERC4626AssetsRoleProviderFactory is IERC4626AssetsRoleProviderFactory {
  function createRoleProvider(
    bytes calldata data
  ) external override returns (address provider) {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (ERC4626AssetsRoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function createERC4626AssetsRoleProvider(
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function _createRoleProvider(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs memory inputs
  ) internal returns (address provider) {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(
      new ERC4626AssetsRoleProvider{ salt: salt }(inputs.vault, inputs.minAssets)
    );
    emit ERC4626AssetsRoleProviderDeployed(
      provider,
      inputs.vault,
      deployer,
      inputs.salt,
      inputs.minAssets
    );
  }

  function computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  function _computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs memory inputs
  ) internal view returns (address provider) {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(
        type(ERC4626AssetsRoleProvider).creationCode,
        abi.encode(inputs.vault, inputs.minAssets)
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

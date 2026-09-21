// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './ERC20RoleProvider.sol';
import './IERC20RoleProviderFactory.sol';

/// @notice deterministic deployer for immutable ERC20 balance providers.
/// @dev the user salt is namespaced by `msg.sender`, so another caller can't consume the predicted
///      address first. the provider has no administrator and this factory retains no authority.
contract ERC20RoleProviderFactory is IERC20RoleProviderFactory {
  /// @notice decodes `ERC20RoleProviderFactoryInputs` and deploys for `msg.sender`.
  /// @dev when a hooks instance calls this entrypoint, that instance is the CREATE2 namespace.
  function createRoleProvider(
    bytes calldata data
  ) external override returns (address provider) {
    ERC20RoleProviderFactoryInputs memory inputs = abi.decode(
      data,
      (ERC20RoleProviderFactoryInputs)
    );
    provider = _createRoleProvider(msg.sender, inputs);
  }

  /// @notice deploys an ERC20 provider in `msg.sender`'s CREATE2 namespace.
  function createERC20RoleProvider(
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external override returns (address provider) {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  function _createRoleProvider(
    address deployer,
    ERC20RoleProviderFactoryInputs memory inputs
  ) internal returns (address provider) {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(new ERC20RoleProvider{ salt: salt }(inputs.token, inputs.minBalance));
    emit ERC20RoleProviderDeployed(
      provider,
      inputs.token,
      deployer,
      inputs.salt,
      inputs.minBalance
    );
  }

  /// @notice predicts the provider for the exact deployer, constructor inputs, and user salt.
  function computeRoleProviderAddress(
    address deployer,
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external view override returns (address provider) {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  function _computeRoleProviderAddress(
    address deployer,
    ERC20RoleProviderFactoryInputs memory inputs
  ) internal view returns (address provider) {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(
        type(ERC20RoleProvider).creationCode,
        abi.encode(inputs.token, inputs.minBalance)
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

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // ERC4626AssetsRoleProviderFactory
// ║  ██▀▀     ▀▀██   Deterministic ERC4626Assets provider deployment and address prediction.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DEPLOYMENT
// ║  createRoleProvider(...)
// ║  createERC4626AssetsRoleProvider(...)
// ║  _createRoleProvider(...)
// ║
// ║  ADDRESS PREDICTION
// ║  computeRoleProviderAddress(...)
// ║  _computeRoleProviderAddress(...)
// ║  _deriveSalt(...)
// ╚═════

import './ERC4626AssetsRoleProvider.sol';
import './IERC4626AssetsRoleProviderFactory.sol';

// ┌─ ERC4626AssetsRoleProviderFactory ─────────────────────────────────────────
/// @notice deterministic deployer for immutable ERC4626 asset-value providers.
///
/// @dev the user salt is namespaced by `msg.sender`, so another caller can't consume the predicted
///      address first. the provider has no administrator and this factory retains no authority.
contract ERC4626AssetsRoleProviderFactory is IERC4626AssetsRoleProviderFactory {
  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  /// @notice decode `ERC4626AssetsRoleProviderFactoryInputs` and deploy for `msg.sender`.
  ///
  /// @dev when a hooks instance calls this entrypoint, that instance is the CREATE2 namespace.
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    ERC4626AssetsRoleProviderFactoryInputs memory inputs = abi.decode(data, (ERC4626AssetsRoleProviderFactoryInputs));
    provider = _createRoleProvider(msg.sender, inputs);
  }

  // ┌─ createERC4626AssetsRoleProvider ─────
  /// @notice deploy an ERC4626 provider in `msg.sender`'s CREATE2 namespace.
  function createERC4626AssetsRoleProvider(ERC4626AssetsRoleProviderFactoryInputs calldata inputs)
    external
    override
    returns (address provider)
  {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  // ┌─ _createRoleProvider ─────
  function _createRoleProvider(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs memory inputs
  )
    internal
    returns (address provider)
  {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(new ERC4626AssetsRoleProvider{ salt: salt }(inputs.vault, inputs.minAssets));
    emit ERC4626AssetsRoleProviderDeployed(provider, inputs.vault, deployer, inputs.salt, inputs.minAssets);
  }

  // ░░▒▒▓▓██ [ ADDRESS PREDICTION ] ───────────────────────────────────────────

  // ┌─ computeRoleProviderAddress ─────
  /// @notice predict the provider for the exact deployer, constructor inputs, and user salt.
  function computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  )
    external
    view
    override
    returns (address provider)
  {
    provider = _computeRoleProviderAddress(deployer, inputs);
  }

  // ┌─ _computeRoleProviderAddress ─────
  function _computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs memory inputs
  )
    internal
    view
    returns (address provider)
  {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(type(ERC4626AssetsRoleProvider).creationCode, abi.encode(inputs.vault, inputs.minAssets))
    );
    provider = address(
      uint160(
        uint256(
          keccak256(abi.encodePacked(bytes1(0xff), address(this), _deriveSalt(deployer, inputs.salt), initCodeHash))
        )
      )
    );
  }

  // ┌─ _deriveSalt ─────
  function _deriveSalt(address deployer, bytes32 salt) internal pure returns (bytes32) {
    return keccak256(abi.encode(deployer, salt));
  }
}

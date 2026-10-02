// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MerkleRoleProviderFactory
// ║  ██▀▀     ▀▀██   Deterministic Merkle provider deployment and address prediction.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DEPLOYMENT
// ║  createRoleProvider(...)
// ║  createMerkleRoleProvider(...)
// ║  _createRoleProvider(...)
// ║
// ║  ADDRESS PREDICTION
// ║  computeRoleProviderAddress(...)
// ║  _computeRoleProviderAddress(...)
// ║  _deriveSalt(...)
// ╚═════

import './MerkleRoleProvider.sol';
import './IMerkleRoleProviderFactory.sol';

// ┌─ MerkleRoleProviderFactory ────────────────────────────────────────────────
/// @notice deterministic deployer for mutable-root Merkle providers.
///
/// @dev the user salt is namespaced by `msg.sender`, so another caller can't consume the predicted
///      address first. the provider's configured administrator owns it; this factory retains
///      nothing.
contract MerkleRoleProviderFactory is IMerkleRoleProviderFactory {
  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  /// @notice decode `MerkleRoleProviderFactoryInputs` and deploy for `msg.sender`.
  ///
  /// @dev when a hooks instance calls this entrypoint, that instance is the CREATE2 namespace.
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    MerkleRoleProviderFactoryInputs memory inputs = abi.decode(data, (MerkleRoleProviderFactoryInputs));
    provider = _createRoleProvider(msg.sender, inputs);
  }

  // ┌─ createMerkleRoleProvider ─────
  /// @notice deploy a Merkle provider in `msg.sender`'s CREATE2 namespace.
  function createMerkleRoleProvider(MerkleRoleProviderFactoryInputs calldata inputs)
    external
    override
    returns (address provider)
  {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  // ┌─ _createRoleProvider ─────
  function _createRoleProvider(
    address deployer,
    MerkleRoleProviderFactoryInputs memory inputs
  )
    internal
    returns (address provider)
  {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(new MerkleRoleProvider{ salt: salt }(inputs.administrator, inputs.root));
    emit MerkleRoleProviderDeployed(provider, inputs.administrator, deployer, inputs.salt, inputs.root);
  }

  // ░░▒▒▓▓██ [ ADDRESS PREDICTION ] ───────────────────────────────────────────

  // ┌─ computeRoleProviderAddress ─────
  /// @notice predict the provider for the exact deployer, constructor inputs, and user salt.
  function computeRoleProviderAddress(
    address deployer,
    MerkleRoleProviderFactoryInputs calldata inputs
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
    MerkleRoleProviderFactoryInputs memory inputs
  )
    internal
    view
    returns (address provider)
  {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(type(MerkleRoleProvider).creationCode, abi.encode(inputs.administrator, inputs.root))
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

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // AccessListRoleProviderFactory
//  \ ^ /   Deterministic AccessList provider deployment and address prediction.
//    V
//
//  DEPLOYMENT
//  createRoleProvider(...)
//  createAccessListRoleProvider(...)
//  _createRoleProvider(...)
//
//  ADDRESS PREDICTION
//  computeRoleProviderAddress(...)
//  _computeRoleProviderAddress(...)
//  _deriveSalt(...)
// ═════

import './AccessListRoleProvider.sol';
import './IAccessListRoleProviderFactory.sol';

// ┌─ AccessListRoleProviderFactory ────────────────────────────────────────────
/// @notice deterministic deployer for reusable access-list providers.
///
/// @dev the user salt is namespaced by `msg.sender`, so another caller can't consume the predicted
///      address first. the provider's configured administrator owns it; this factory retains
///      nothing.
contract AccessListRoleProviderFactory is IAccessListRoleProviderFactory {
  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  /// @notice decode `AccessListRoleProviderFactoryInputs` and deploy for `msg.sender`.
  ///
  /// @dev when a hooks instance calls this entrypoint, that instance is the CREATE2 namespace.
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    AccessListRoleProviderFactoryInputs memory inputs = abi.decode(data, (AccessListRoleProviderFactoryInputs));
    provider = _createRoleProvider(msg.sender, inputs);
  }

  // ┌─ createAccessListRoleProvider ─────
  /// @notice deploy an access-list provider in `msg.sender`'s CREATE2 namespace.
  function createAccessListRoleProvider(AccessListRoleProviderFactoryInputs calldata inputs)
    external
    override
    returns (address provider)
  {
    provider = _createRoleProvider(msg.sender, inputs);
  }

  // ┌─ _createRoleProvider ─────
  function _createRoleProvider(
    address deployer,
    AccessListRoleProviderFactoryInputs memory inputs
  )
    internal
    returns (address provider)
  {
    address expectedProvider = _computeRoleProviderAddress(deployer, inputs);
    if (expectedProvider.code.length != 0) revert RoleProviderAlreadyExists();
    bytes32 salt = _deriveSalt(deployer, inputs.salt);
    provider = address(new AccessListRoleProvider{ salt: salt }(inputs.administrator, inputs.initialMembers));
    emit AccessListRoleProviderDeployed(provider, inputs.administrator, deployer, inputs.salt, inputs.initialMembers);
  }

  // ░░▒▒▓▓██ [ ADDRESS PREDICTION ] ───────────────────────────────────────────

  // ┌─ computeRoleProviderAddress ─────
  /// @notice predict the provider for the exact deployer, constructor inputs, and user salt.
  function computeRoleProviderAddress(
    address deployer,
    AccessListRoleProviderFactoryInputs calldata inputs
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
    AccessListRoleProviderFactoryInputs memory inputs
  )
    internal
    view
    returns (address provider)
  {
    bytes32 initCodeHash = keccak256(
      abi.encodePacked(
        type(AccessListRoleProvider).creationCode, abi.encode(inputs.administrator, inputs.initialMembers)
      )
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

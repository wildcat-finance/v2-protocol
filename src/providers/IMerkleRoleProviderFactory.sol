// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

/// @notice constructor and CREATE2 inputs for a Merkle provider.
/// @param administrator initial authority over the root and provider administration.
/// @param root initial sorted-pair Merkle root.
/// @param salt caller-scoped salt used by the factory.
struct MerkleRoleProviderFactoryInputs {
  address administrator;
  bytes32 root;
  bytes32 salt;
}

/// @notice deterministic factory for mutable-root Merkle providers.
/// @dev salts are namespaced by the factory caller. the factory retains no authority over the
///      provider after deployment.
interface IMerkleRoleProviderFactory is IRoleProviderFactory {
  /// @dev a provider already has code at the derived CREATE2 address.
  error RoleProviderAlreadyExists();

  /// @notice emitted when the factory deploys a Merkle membership provider.
  event MerkleRoleProviderDeployed(
    address indexed provider,
    address indexed administrator,
    address indexed deployer,
    bytes32 salt,
    bytes32 root
  );

  /// @notice deploys a provider for `msg.sender`.
  function createMerkleRoleProvider(
    MerkleRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  /// @notice predicts the address for the exact `deployer`, inputs, and this factory.
  /// @dev pass the address that will actually call the create function as `deployer`.
  function computeRoleProviderAddress(
    address deployer,
    MerkleRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

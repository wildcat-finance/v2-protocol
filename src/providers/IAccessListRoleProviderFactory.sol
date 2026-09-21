// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

/// @notice constructor and CREATE2 inputs for an access-list provider.
/// @param administrator initial authority over membership and provider administration.
/// @param initialMembers initial nonzero members; duplicates revert deployment.
/// @param salt caller-scoped salt used by the factory.
struct AccessListRoleProviderFactoryInputs {
  address administrator;
  address[] initialMembers;
  bytes32 salt;
}

/// @notice deterministic factory for reusable access-list providers.
/// @dev salts are namespaced by the factory caller. the factory retains no authority over the
///      provider after deployment.
interface IAccessListRoleProviderFactory is IRoleProviderFactory {
  /// @dev a provider already has code at the derived CREATE2 address.
  error RoleProviderAlreadyExists();

  /// @notice emitted when the factory deploys an access-list provider.
  event AccessListRoleProviderDeployed(
    address indexed provider,
    address indexed administrator,
    address indexed deployer,
    bytes32 salt,
    address[] initialMembers
  );

  /// @notice deploys a provider for `msg.sender` with the supplied initial authority and members.
  function createAccessListRoleProvider(
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  /// @notice predicts the address for the exact `deployer`, inputs, and this factory.
  /// @dev pass the address that will actually call the create function as `deployer`.
  function computeRoleProviderAddress(
    address deployer,
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

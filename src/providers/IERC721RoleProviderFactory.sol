// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

/// @notice constructor and CREATE2 inputs for an ERC721 balance provider.
/// @param token collection queried for balances.
/// @param skipInterfaceCheck skips ERC165 and ERC721 checks, not later `balanceOf` failures.
/// @param salt caller-scoped salt used by the factory.
struct ERC721RoleProviderFactoryInputs {
  address token;
  bool skipInterfaceCheck;
  bytes32 salt;
}

/// @notice deterministic factory for immutable ERC721 balance providers.
/// @dev salts are namespaced by the factory caller. the factory retains no authority over the
///      provider after deployment.
interface IERC721RoleProviderFactory is IRoleProviderFactory {
  /// @dev a provider already has code at the derived CREATE2 address.
  error RoleProviderAlreadyExists();

  /// @notice emitted when the factory deploys an ERC721 balance provider.
  event ERC721RoleProviderDeployed(
    address indexed provider,
    address indexed token,
    address indexed deployer,
    bytes32 salt,
    bool skipInterfaceCheck
  );

  /// @notice deploys a provider for `msg.sender`.
  function createERC721RoleProvider(
    ERC721RoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  /// @notice predicts the address for the exact `deployer`, inputs, and this factory.
  /// @dev pass the address that will actually call the create function as `deployer`.
  function computeRoleProviderAddress(
    address deployer,
    ERC721RoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

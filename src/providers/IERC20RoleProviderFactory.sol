// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

/// @notice constructor and CREATE2 inputs for an ERC20 balance provider.
/// @param token contract queried for balances.
/// @param minBalance nonzero threshold in token base units.
/// @param salt caller-scoped salt used by the factory.
struct ERC20RoleProviderFactoryInputs {
  address token;
  uint256 minBalance;
  bytes32 salt;
}

/// @notice deterministic factory for immutable ERC20 balance providers.
/// @dev salts are namespaced by the factory caller. the factory retains no authority over the
///      provider after deployment.
interface IERC20RoleProviderFactory is IRoleProviderFactory {
  /// @dev a provider already has code at the derived CREATE2 address.
  error RoleProviderAlreadyExists();

  /// @notice emitted when the factory deploys an ERC20 balance provider.
  event ERC20RoleProviderDeployed(
    address indexed provider,
    address indexed token,
    address indexed deployer,
    bytes32 salt,
    uint256 minBalance
  );

  /// @notice deploys a provider for `msg.sender`.
  function createERC20RoleProvider(
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  /// @notice predicts the address for the exact `deployer`, inputs, and this factory.
  /// @dev pass the address that will actually call the create function as `deployer`.
  function computeRoleProviderAddress(
    address deployer,
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

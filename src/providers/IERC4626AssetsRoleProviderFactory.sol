// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

/// @notice constructor and CREATE2 inputs for an ERC4626 asset-value provider.
/// @param vault contract queried for share balances and asset conversion.
/// @param minAssets nonzero threshold in underlying-asset base units.
/// @param salt caller-scoped salt used by the factory.
struct ERC4626AssetsRoleProviderFactoryInputs {
  address vault;
  uint256 minAssets;
  bytes32 salt;
}

/// @notice deterministic factory for immutable ERC4626 asset-value providers.
/// @dev salts are namespaced by the factory caller. the factory retains no authority over the
///      provider after deployment.
interface IERC4626AssetsRoleProviderFactory is IRoleProviderFactory {
  /// @dev a provider already has code at the derived CREATE2 address.
  error RoleProviderAlreadyExists();

  /// @notice emitted when the factory deploys an ERC4626 asset-value provider.
  event ERC4626AssetsRoleProviderDeployed(
    address indexed provider,
    address indexed vault,
    address indexed deployer,
    bytes32 salt,
    uint256 minAssets
  );

  /// @notice deploys a provider for `msg.sender`.
  function createERC4626AssetsRoleProvider(
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  /// @notice predicts the address for the exact `deployer`, inputs, and this factory.
  /// @dev pass the address that will actually call the create function as `deployer`.
  function computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice common deployment entrypoint used when a hooks instance creates and attaches a provider.
interface IRoleProviderFactory {
  /// @param data provider-specific constructor and deployment inputs.
  /// @return address of the deployed role provider.
  function createRoleProvider(bytes calldata data) external returns (address);
}

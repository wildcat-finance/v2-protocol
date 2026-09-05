// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice configuration for creating and attaching a provider during hooks deployment.
/// @param timeToLive seconds added to this provider's credential timestamp to determine expiry.
/// @param providerFactoryCalldata provider-specific input passed to `createRoleProvider`.
struct CreateProviderInputs {
  uint32 timeToLive;
  bytes providerFactoryCalldata;
}

/// @notice configuration for attaching an existing provider during hooks deployment.
/// @param providerAddress provider trusted by the new hooks instance.
/// @param timeToLive seconds added to its credential timestamps to determine expiry on this hook.
struct ExistingProviderInputs {
  address providerAddress;
  uint32 timeToLive;
}

/// @notice shared constructor configuration for built-in access-control hooks.
/// @param name display name stored on the hooks instance.
/// @param roleProviderFactory factory used for every entry in `newProviderInputs`.
/// @param newProviderInputs providers to create and attach.
/// @param existingProviders providers to attach without deploying them.
/// @dev `roleProviderFactory` may be zero only when `newProviderInputs` is empty.
struct NameAndProviderInputs {
  string name;
  address roleProviderFactory;
  CreateProviderInputs[] newProviderInputs;
  ExistingProviderInputs[] existingProviders;
}

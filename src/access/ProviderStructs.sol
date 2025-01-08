// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ========================================================================== //
//        Common structs for AccessControlHooks and FixedTermLoanHooks        //
// ========================================================================== //

/**
 * @dev Input parameters to create a new role provider with a call to a provider factory.
 * @param timeToLive Time to live for the new provider.
 * @param providerFactoryCalldata Calldata to be passed to the provider factory.
 */
struct CreateProviderInputs {
  uint32 timeToLive;
  bytes providerFactoryCalldata;
}

/**
 * @dev Input parameters to add a role provider that has already been deployed.
 * @param providerAddress Address of the role provider.
 * @param timeToLive Time to live for the provider.
 */
struct ExistingProviderInputs {
  address providerAddress;
  uint32 timeToLive;
}

/**
 * @dev Constructor parameters for new access control or fixed term hooks instance.
 * @param name Name of the hooks instance.
 * @param roleProviderFactory Address of the role provider factory.
 * @param newProviderInputs Inputs for creating new role providers.
 * @param existingProviders Inputs for adding existing role providers.
 */
struct NameAndProviderInputs {
  string name;
  address roleProviderFactory;
  CreateProviderInputs[] newProviderInputs;
  ExistingProviderInputs[] existingProviders;
}

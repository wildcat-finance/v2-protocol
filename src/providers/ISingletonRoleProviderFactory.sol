// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../access/IRoleProviderFactory.sol';

struct SingletonRoleProviderFactoryInputs {
  address lender;
  bytes32 salt;
}

interface ISingletonRoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event SingletonRoleProviderDeployed(
    address indexed provider,
    address indexed lender,
    address indexed deployer,
    bytes32 salt
  );

  function createSingletonRoleProvider(
    SingletonRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    SingletonRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

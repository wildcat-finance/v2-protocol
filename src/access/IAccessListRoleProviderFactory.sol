// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './IRoleProviderFactory.sol';

struct AccessListRoleProviderFactoryInputs {
  address administrator;
  address[] initialMembers;
  bytes32 salt;
}

interface IAccessListRoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event AccessListRoleProviderDeployed(
    address indexed provider,
    address indexed administrator,
    address indexed deployer,
    bytes32 salt,
    address[] initialMembers
  );

  function createAccessListRoleProvider(
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    AccessListRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

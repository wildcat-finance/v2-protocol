// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

struct MerkleRoleProviderFactoryInputs {
  address administrator;
  bytes32 root;
  bytes32 salt;
}

interface IMerkleRoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event MerkleRoleProviderDeployed(
    address indexed provider,
    address indexed administrator,
    address indexed deployer,
    bytes32 salt,
    bytes32 root
  );

  function createMerkleRoleProvider(
    MerkleRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    MerkleRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

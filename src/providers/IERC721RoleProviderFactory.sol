// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

struct ERC721RoleProviderFactoryInputs {
  address token;
  bool skipInterfaceCheck;
  bytes32 salt;
}

interface IERC721RoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event ERC721RoleProviderDeployed(
    address indexed provider,
    address indexed token,
    address indexed deployer,
    bytes32 salt,
    bool skipInterfaceCheck
  );

  function createERC721RoleProvider(
    ERC721RoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    ERC721RoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

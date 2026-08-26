// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

struct ERC20RoleProviderFactoryInputs {
  address token;
  uint256 minBalance;
  bytes32 salt;
}

interface IERC20RoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event ERC20RoleProviderDeployed(
    address indexed provider,
    address indexed token,
    address indexed deployer,
    bytes32 salt,
    uint256 minBalance
  );

  function createERC20RoleProvider(
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    ERC20RoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

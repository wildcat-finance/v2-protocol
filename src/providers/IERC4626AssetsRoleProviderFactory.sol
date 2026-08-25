// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../access/IRoleProviderFactory.sol';

struct ERC4626AssetsRoleProviderFactoryInputs {
  address vault;
  uint256 minAssets;
  bytes32 salt;
}

interface IERC4626AssetsRoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event ERC4626AssetsRoleProviderDeployed(
    address indexed provider,
    address indexed vault,
    address indexed deployer,
    bytes32 salt,
    uint256 minAssets
  );

  function createERC4626AssetsRoleProvider(
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    ERC4626AssetsRoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

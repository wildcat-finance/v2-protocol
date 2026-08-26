// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProviderFactory.sol';

struct ERC1155RoleProviderFactoryInputs {
  address token;
  uint256 tokenId;
  bool skipInterfaceCheck;
  bytes32 salt;
}

interface IERC1155RoleProviderFactory is IRoleProviderFactory {
  error RoleProviderAlreadyExists();

  event ERC1155RoleProviderDeployed(
    address indexed provider,
    address indexed token,
    address indexed deployer,
    bytes32 salt,
    uint256 tokenId,
    bool skipInterfaceCheck
  );

  function createERC1155RoleProvider(
    ERC1155RoleProviderFactoryInputs calldata inputs
  ) external returns (address provider);

  function computeRoleProviderAddress(
    address deployer,
    ERC1155RoleProviderFactoryInputs calldata inputs
  ) external view returns (address provider);
}

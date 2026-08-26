// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IRoleProviderFactory {
  function createRoleProvider(bytes calldata data) external returns (address);
}

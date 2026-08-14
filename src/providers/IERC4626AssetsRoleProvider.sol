// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../access/IRoleProvider.sol';

interface IERC4626AssetsRoleProvider is IRoleProvider {
  error InvalidVaultAddress();
  error InvalidMinimumAssets();

  function vault() external view returns (address);

  function minAssets() external view returns (uint256);
}

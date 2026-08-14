// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../access/IRoleProvider.sol';

interface IERC20RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidMinimumBalance();

  function token() external view returns (address);

  function minBalance() external view returns (uint256);
}

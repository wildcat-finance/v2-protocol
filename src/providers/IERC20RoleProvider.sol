// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';

/// @notice pull provider that accepts accounts holding a minimum ERC20 balance.
interface IERC20RoleProvider is IRoleProvider {
  /// @dev the token address has no code.
  error InvalidTokenAddress();
  /// @dev the qualifying token balance is zero.
  error InvalidMinimumBalance();

  /// @notice token contract queried for balances.
  function token() external view returns (address);

  /// @notice qualifying balance in token base units.
  function minBalance() external view returns (uint256);
}

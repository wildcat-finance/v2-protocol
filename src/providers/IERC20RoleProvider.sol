// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IERC20RoleProvider
//  \ ^ /   Immutable ERC20 credential-provider configuration.
//    V
//
//  CONFIGURATION
//  token()
//  minBalance()
// ═════

import '../access/IRoleProvider.sol';

// ┌─ IERC20RoleProvider ───────────────────────────────────────────────────────
/// @notice pull provider that accepts accounts holding a minimum ERC20 balance.
interface IERC20RoleProvider is IRoleProvider {
  /// @dev the token address has no code.
  error InvalidTokenAddress();

  /// @dev the qualifying token balance is zero.
  error InvalidMinimumBalance();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ token ─────
  /// @notice token contract queried for balances.
  function token() external view returns (address);

  // ┌─ minBalance ─────
  /// @notice qualifying balance in token base units.
  function minBalance() external view returns (uint256);
}

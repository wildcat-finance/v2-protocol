// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IERC721RoleProvider
// ║  ██▀▀     ▀▀██   Immutable ERC721 credential-provider configuration.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CONFIGURATION
// ║  token()
// ╚═════

import '../access/IRoleProvider.sol';

// ┌─ IERC721RoleProvider ──────────────────────────────────────────────────────
/// @notice pull provider that accepts accounts holding any token from an ERC721 collection.
interface IERC721RoleProvider is IRoleProvider {
  /// @dev the token address has no code.
  error InvalidTokenAddress();

  /// @dev the token failed the deployment-time ERC165 or ERC721 checks.
  error InvalidERC721();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ token ─────
  /// @notice collection queried for balances.
  function token() external view returns (address);
}

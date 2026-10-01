// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IERC1155RoleProvider
// ║  ██▀▀     ▀▀██   Immutable ERC1155 credential-provider configuration.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CONFIGURATION
// ║  token()
// ║  tokenId()
// ╚═════

import '../access/IRoleProvider.sol';

// ┌─ IERC1155RoleProvider ─────────────────────────────────────────────────────
/// @notice pull provider that accepts holders of one ERC1155 collection and token ID.
interface IERC1155RoleProvider is IRoleProvider {
  /// @dev the token address has no code.
  error InvalidTokenAddress();

  /// @dev the token failed the deployment-time ERC165 or ERC1155 checks.
  error InvalidERC1155();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ token ─────
  /// @notice collection queried for balances.
  function token() external view returns (address);

  // ┌─ tokenId ─────
  /// @notice only token ID whose balance qualifies.
  function tokenId() external view returns (uint256);
}

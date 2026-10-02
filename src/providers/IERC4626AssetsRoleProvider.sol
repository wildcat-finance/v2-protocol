// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IERC4626AssetsRoleProvider
//  \ ^ /   Immutable ERC4626Assets credential-provider configuration.
//    V
//
//  CONFIGURATION
//  vault()
//  minAssets()
// ═════

import '../access/IRoleProvider.sol';

// ┌─ IERC4626AssetsRoleProvider ───────────────────────────────────────────────
/// @notice pull provider that accepts accounts whose ERC4626 shares represent enough assets.
interface IERC4626AssetsRoleProvider is IRoleProvider {
  /// @dev the vault address has no code.
  error InvalidVaultAddress();

  /// @dev the qualifying underlying-asset value is zero.
  error InvalidMinimumAssets();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ vault ─────
  /// @notice vault queried for share balances and asset conversion.
  function vault() external view returns (address);

  // ┌─ minAssets ─────
  /// @notice qualifying value in underlying-asset base units.
  function minAssets() external view returns (uint256);
}

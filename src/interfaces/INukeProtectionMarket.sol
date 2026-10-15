// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // INukeProtectionMarket
//  \ ^ /   Market-local protection registration and lifetime queries.
//    V
//
//  OPERATIONS
//  factory()
//  isNukeProtected(...)
//  registerNukeProtectedAccount(...)
// ═════

// ┌─ INukeProtectionMarket ────────────────────────────────────────────────────
/// @notice market-local protection for approved integration contracts.
interface INukeProtectionMarket {
  // ┌─ factory ─────
  function factory() external view returns (address);

  // ┌─ isNukeProtected ─────
  function isNukeProtected(address account) external view returns (bool);

  // ┌─ registerNukeProtectedAccount ─────
  /// @notice permanently protect an account at any point in the market's lifetime.
  /// @dev only the market's immutable factory may call this.
  function registerNukeProtectedAccount(address account) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // INukeProtectionMarket
//  \ ^ /   Market-local protection registration and lifetime queries.
//    V
//
//  AUTHORITY
//  factory()
//
//  NUKE PROTECTION
//  isNukeProtected(...)
//  registerNukeProtectedAccount(...)
// ═════

// ┌─ INukeProtectionMarket ────────────────────────────────────────────────────
/// @notice market-local protection for approved integration contracts.
interface INukeProtectionMarket {
  // ░░▒▒▓▓██ [ AUTHORITY ] ────────────────────────────────────────────────────

  // ┌─ factory ─────
  /// @notice return the immutable factory allowed to register protected accounts.
  function factory() external view returns (address);

  // ░░▒▒▓▓██ [ NUKE PROTECTION ] ──────────────────────────────────────────────

  // ┌─ isNukeProtected ─────
  /// @notice return whether `account` is permanently exempt from lender sanctions checks and nuking.
  function isNukeProtected(address account) external view returns (bool);

  // ┌─ registerNukeProtectedAccount ─────
  /// @notice permanently protect an account at any point in the market's lifetime.
  ///
  /// @dev only the market's immutable factory may call this.
  function registerNukeProtectedAccount(address account) external;
}

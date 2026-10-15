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
//  nukeProtectionSealed()
//  registerNukeProtectedAccount(...)
// ═════

// ┌─ INukeProtectionMarket ────────────────────────────────────────────────────
/// @notice market-local protection for approved integration contracts.
interface INukeProtectionMarket {
  // ┌─ factory ─────
  function factory() external view returns (address);

  // ┌─ isNukeProtected ─────
  function isNukeProtected(address account) external view returns (bool);

  // ┌─ nukeProtectionSealed ─────
  function nukeProtectionSealed() external view returns (bool);

  // ┌─ registerNukeProtectedAccount ─────
  /// @notice permanently protect an account before the first successful deposit.
  /// @dev only the market's immutable factory may call this.
  function registerNukeProtectedAccount(address account) external;
}

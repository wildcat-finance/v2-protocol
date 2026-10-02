// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IHooksAdministrator
// ║  ██▀▀     ▀▀██   Hooks authority transfers and factory index synchronization.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ADMINISTRATOR TRANSFER
// ║  requestAdministratorTransfer(...)
// ║  acceptAdministratorTransfer()
// ║  cancelAdministratorTransfer()
// ║
// ║  AUTHORITY QUERIES
// ║  administrator()
// ║  pendingAdministrator()
// ║
// ║  FACTORY CALLBACK
// ║  onHooksAdministratorTransferred(...)
// ║  archController()
// ╚═════

// ┌─ IHooksAdministrator ──────────────────────────────────────────────────────
/// @notice two-step authority transfer used by administered hooks instances.
///
/// @dev a pending administrator has no authority until it accepts. built-in hooks also require
///      the target to be a registered borrower when the transfer is requested and accepted.
interface IHooksAdministrator {
  // ░░▒▒▓▓██ [ ADMINISTRATOR TRANSFER ] ───────────────────────────────────────

  // ┌─ requestAdministratorTransfer ─────
  /// @notice start or replace a pending transfer.
  function requestAdministratorTransfer(address newAdministrator) external;

  // ┌─ acceptAdministratorTransfer ─────
  /// @notice complete the transfer when called by the pending administrator.
  function acceptAdministratorTransfer() external;

  // ┌─ cancelAdministratorTransfer ─────
  /// @notice clear the pending transfer without changing the administrator.
  function cancelAdministratorTransfer() external;

  // ░░▒▒▓▓██ [ AUTHORITY QUERIES ] ────────────────────────────────────────────

  // ┌─ administrator ─────
  /// @notice current authority over this hooks instance.
  function administrator() external view returns (address);

  // ┌─ pendingAdministrator ─────
  /// @notice address allowed to accept the pending transfer, or zero when none is pending.
  function pendingAdministrator() external view returns (address);
}

// ┌─ IHooksFactoryAdministratorCallback ───────────────────────────────────────
/// @notice callback used to keep a factory's administrator index in sync with its hooks instance.
interface IHooksFactoryAdministratorCallback {
  // ░░▒▒▓▓██ [ FACTORY CALLBACK ] ─────────────────────────────────────────────

  // ┌─ onHooksAdministratorTransferred ─────
  /// @dev the factory must authenticate `msg.sender` as the hooks instance being reindexed.
  function onHooksAdministratorTransferred(address previousAdministrator, address newAdministrator) external;

  // ┌─ archController ─────
  /// @notice ArchController used to validate hooks administrators.
  function archController() external view returns (address);
}

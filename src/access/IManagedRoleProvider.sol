// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IManagedRoleProvider
// ║  ██▀▀     ▀▀██   Optional two-step administration for mutable role providers.
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
// ╚═════

// ┌─ IManagedRoleProvider ─────────────────────────────────────────────────────
/// @notice optional two-step administration for providers with mutable configuration.
///
/// @dev provider administration is independent of hooks administration and ArchController
///      registration. role providers are not required to implement this interface.
interface IManagedRoleProvider {
  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when the administrator starts or replaces a two-step transfer.
  event AdministratorTransferRequested(
    address indexed administrator,
    address indexed previousPendingAdministrator,
    address indexed pendingAdministrator
  );

  /// @notice emitted when the administrator cancels a pending transfer.
  event AdministratorTransferCancelled(address indexed administrator, address indexed cancelledPendingAdministrator);

  /// @notice emitted when the pending administrator accepts authority.
  event AdministratorTransferred(address indexed previousAdministrator, address indexed newAdministrator);

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev the caller is not the current provider administrator.
  error CallerNotAdministrator();

  /// @dev the proposed administrator is zero or unchanged.
  error InvalidAdministratorTransferTarget();

  /// @dev no provider-administrator transfer is pending.
  error NoPendingAdministratorTransfer();

  /// @dev the caller is not the pending provider administrator.
  error NotPendingAdministrator();

  // ░░▒▒▓▓██ [ ADMINISTRATOR TRANSFER ] ───────────────────────────────────────

  // ┌─ requestAdministratorTransfer ─────
  /// @notice starts or replaces a pending transfer.
  function requestAdministratorTransfer(address newAdministrator) external;

  // ┌─ acceptAdministratorTransfer ─────
  /// @notice completes the transfer when called by the pending administrator.
  function acceptAdministratorTransfer() external;

  // ┌─ cancelAdministratorTransfer ─────
  /// @notice clears the pending transfer without changing the administrator.
  function cancelAdministratorTransfer() external;

  // ░░▒▒▓▓██ [ AUTHORITY QUERIES ] ────────────────────────────────────────────

  // ┌─ administrator ─────
  /// @notice current authority over this provider's mutable configuration.
  function administrator() external view returns (address);

  // ┌─ pendingAdministrator ─────
  /// @notice address allowed to accept the pending transfer, or zero when none is pending.
  function pendingAdministrator() external view returns (address);
}

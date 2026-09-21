// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice optional two-step administration for providers with mutable configuration.
/// @dev provider administration is independent of hooks administration and ArchController
///      registration. role providers are not required to implement this interface.
interface IManagedRoleProvider {
  /// @notice emitted when the administrator starts or replaces a two-step transfer.
  event AdministratorTransferRequested(
    address indexed administrator,
    address indexed previousPendingAdministrator,
    address indexed pendingAdministrator
  );
  /// @notice emitted when the administrator cancels a pending transfer.
  event AdministratorTransferCancelled(
    address indexed administrator,
    address indexed cancelledPendingAdministrator
  );
  /// @notice emitted when the pending administrator accepts authority.
  event AdministratorTransferred(
    address indexed previousAdministrator,
    address indexed newAdministrator
  );

  /// @dev the caller is not the current provider administrator.
  error CallerNotAdministrator();
  /// @dev the proposed administrator is zero or unchanged.
  error InvalidAdministratorTransferTarget();
  /// @dev no provider-administrator transfer is pending.
  error NoPendingAdministratorTransfer();
  /// @dev the caller is not the pending provider administrator.
  error NotPendingAdministrator();

  /// @notice current authority over this provider's mutable configuration.
  function administrator() external view returns (address);

  /// @notice address allowed to accept the pending transfer, or zero when none is pending.
  function pendingAdministrator() external view returns (address);

  /// @notice starts or replaces a pending transfer.
  function requestAdministratorTransfer(address newAdministrator) external;

  /// @notice clears the pending transfer without changing the administrator.
  function cancelAdministratorTransfer() external;

  /// @notice completes the transfer when called by the pending administrator.
  function acceptAdministratorTransfer() external;
}

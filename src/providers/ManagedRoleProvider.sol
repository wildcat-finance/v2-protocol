// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../access/IManagedRoleProvider.sol';

/// @notice shared two-step authority transfer for providers with mutable configuration.
/// @dev provider authority is independent of hooks authority. targets need no ArchController
///      registration, and attaching this provider to a hook gives that hook no authority here.
abstract contract ManagedRoleProvider is IManagedRoleProvider {
  address public override administrator;
  address public override pendingAdministrator;

  modifier onlyAdministrator() {
    if (msg.sender != administrator) revert CallerNotAdministrator();
    _;
  }

  /// @param administrator_ initial nonzero provider administrator.
  constructor(address administrator_) {
    if (administrator_ == address(0)) revert InvalidAdministratorTransferTarget();
    administrator = administrator_;
  }

  /// @notice starts or replaces a pending provider-administrator transfer.
  /// @dev the target must be nonzero and different from the current administrator. pending status
  ///      grants no authority.
  function requestAdministratorTransfer(
    address newAdministrator
  ) external override onlyAdministrator {
    if (newAdministrator == address(0) || newAdministrator == administrator) {
      revert InvalidAdministratorTransferTarget();
    }
    address previousPendingAdministrator = pendingAdministrator;
    pendingAdministrator = newAdministrator;
    emit AdministratorTransferRequested(
      msg.sender,
      previousPendingAdministrator,
      newAdministrator
    );
  }

  /// @notice cancels the pending transfer without changing provider authority.
  function cancelAdministratorTransfer() external override onlyAdministrator {
    address cancelledPendingAdministrator = pendingAdministrator;
    if (cancelledPendingAdministrator == address(0)) {
      revert NoPendingAdministratorTransfer();
    }
    pendingAdministrator = address(0);
    emit AdministratorTransferCancelled(msg.sender, cancelledPendingAdministrator);
  }

  /// @notice completes the transfer when called by the pending administrator.
  /// @dev configuration, hook attachments, and provider address are unchanged.
  function acceptAdministratorTransfer() external override {
    address newAdministrator = pendingAdministrator;
    if (msg.sender != newAdministrator) revert NotPendingAdministrator();

    address previousAdministrator = administrator;
    pendingAdministrator = address(0);
    administrator = newAdministrator;
    emit AdministratorTransferred(previousAdministrator, newAdministrator);
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../access/IManagedRoleProvider.sol';

/**
 * @dev Shared two-step administration for providers with mutable configuration.
 *      Hooks do not assume that a provider implements this interface.
 */
abstract contract ManagedRoleProvider is IManagedRoleProvider {
  address public override administrator;
  address public override pendingAdministrator;

  modifier onlyAdministrator() {
    if (msg.sender != administrator) revert CallerNotAdministrator();
    _;
  }

  constructor(address administrator_) {
    if (administrator_ == address(0)) revert InvalidAdministratorTransferTarget();
    administrator = administrator_;
  }

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

  function cancelAdministratorTransfer() external override onlyAdministrator {
    address cancelledPendingAdministrator = pendingAdministrator;
    if (cancelledPendingAdministrator == address(0)) {
      revert NoPendingAdministratorTransfer();
    }
    pendingAdministrator = address(0);
    emit AdministratorTransferCancelled(msg.sender, cancelledPendingAdministrator);
  }

  function acceptAdministratorTransfer() external override {
    address newAdministrator = pendingAdministrator;
    if (msg.sender != newAdministrator) revert NotPendingAdministrator();

    address previousAdministrator = administrator;
    pendingAdministrator = address(0);
    administrator = newAdministrator;
    emit AdministratorTransferred(previousAdministrator, newAdministrator);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @dev Optional administration interface for role providers whose authority can move.
 *      Role providers are not required to implement this interface.
 */
interface IManagedRoleProvider {
  event AdministratorTransferRequested(
    address indexed administrator,
    address indexed previousPendingAdministrator,
    address indexed pendingAdministrator
  );
  event AdministratorTransferCancelled(
    address indexed administrator,
    address indexed cancelledPendingAdministrator
  );
  event AdministratorTransferred(
    address indexed previousAdministrator,
    address indexed newAdministrator
  );

  error CallerNotAdministrator();
  error InvalidAdministratorTransferTarget();
  error NoPendingAdministratorTransfer();
  error NotPendingAdministrator();

  function administrator() external view returns (address);

  function pendingAdministrator() external view returns (address);

  function requestAdministratorTransfer(address newAdministrator) external;

  function cancelAdministratorTransfer() external;

  function acceptAdministratorTransfer() external;
}

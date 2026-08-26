// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IHooksAdministrator {
  function administrator() external view returns (address);

  function pendingAdministrator() external view returns (address);

  function requestAdministratorTransfer(address newAdministrator) external;

  function cancelAdministratorTransfer() external;

  function acceptAdministratorTransfer() external;
}

interface IHooksFactoryAdministratorCallback {
  function archController() external view returns (address);

  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice two-step authority transfer used by administered hooks instances.
/// @dev a pending administrator has no authority until it accepts. built-in hooks also require
///      the target to be a registered borrower when the transfer is requested and accepted.
interface IHooksAdministrator {
  /// @notice current authority over this hooks instance.
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

/// @notice callback used to keep a factory's administrator index in sync with its hooks instance.
interface IHooksFactoryAdministratorCallback {
  /// @notice ArchController used to validate hooks administrators.
  function archController() external view returns (address);

  /// @dev the factory must authenticate `msg.sender` as the hooks instance being reindexed.
  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external;
}

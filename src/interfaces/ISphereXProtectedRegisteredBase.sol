// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice management surface shared by contracts whose SphereX operator is the ArchController.
interface ISphereXProtectedRegisteredBase {
  /// @dev the caller is not the immutable ArchController operator.
  error SphereXOperatorRequired();

  /// @notice emitted when the registered contract records its ArchController operator.
  event ChangedSpherexOperator(address oldSphereXAdmin, address newSphereXAdmin);

  /// @notice emitted when the active SphereX engine changes.
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);

  /// @notice returns the immutable ArchController operator.
  function sphereXOperator() external view returns (address);

  /// @notice returns the active engine, or zero when protection is disabled.
  function sphereXEngine() external view returns (address);

  /// @notice replaces the engine used by this registered contract.
  /// @dev only the ArchController can call this; it validates the engine before forwarding here.
  function changeSphereXEngine(address newSphereXEngine) external;
}

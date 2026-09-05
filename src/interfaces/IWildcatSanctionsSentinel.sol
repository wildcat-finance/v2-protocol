// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Wildcat sanctions sentinel
/// @notice wraps the external sanctions list with borrower-scoped overrides and deterministic
///         escrows.
/// @dev dependency failures are not treated as an unflagged account; they bubble to the caller.
interface IWildcatSanctionsSentinel {
  event NewSanctionsEscrow(
    address indexed borrower,
    address indexed account,
    address indexed asset
  );

  event SanctionOverride(address indexed borrower, address indexed account);

  event SanctionOverrideRemoved(address indexed borrower, address indexed account);

  struct TmpEscrowParams {
    address borrower;
    address account;
    address asset;
  }

  /// @notice initcode hash used to derive escrow addresses.
  function WildcatSanctionsEscrowInitcodeHash() external pure returns (bytes32);

  /// @notice immutable external sanctions-list contract.
  function chainalysisSanctionsList() external view returns (address);

  /// @notice immutable ArchController associated with this sentinel.
  function archController() external view returns (address);

  /// @notice constructor parameters exposed only while an escrow is being deployed.
  /// @dev returns nonzero placeholders outside a sentinel-managed deployment.
  function tmpEscrowParams()
    external
    view
    returns (address borrower, address account, address asset);

  /// @notice returns the raw sanctions-list result for `account`.
  function isFlaggedByChainalysis(address account) external view returns (bool);

  /// @notice returns whether `account` is flagged and has no override from `borrower`.
  function isSanctioned(address borrower, address account) external view returns (bool);

  /// @notice returns whether `borrower` has overridden `account`'s flagged status.
  function sanctionOverrides(address borrower, address account) external view returns (bool);

  /// @notice lets the caller allow a flagged account in its own borrower namespace.
  function overrideSanction(address account) external;

  /// @notice removes the caller's override for `account`.
  function removeSanctionOverride(address account) external;

  /// @notice returns the CREATE2 escrow address for `(borrower, account, asset)`.
  function getEscrowAddress(
    address borrower,
    address account,
    address asset
  ) external view returns (address escrowContract);

  /// @notice deploys the escrow for `(borrower, account, asset)`, or returns the existing one.
  /// @dev the new escrow is automatically exempted in `borrower`'s namespace so it can receive
  ///      quarantined assets. callers do not need permission.
  function createEscrow(
    address borrower,
    address account,
    address asset
  ) external returns (address escrowContract);
}

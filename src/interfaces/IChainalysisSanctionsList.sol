// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice minimal interface for the external Chainalysis sanctions oracle.
interface IChainalysisSanctionsList {
  /// @notice returns the oracle's raw sanction status for `addr`.
  function isSanctioned(address addr) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice deterministic escrow for one borrower namespace, sanctioned account, and asset.
/// @dev anyone may release the escrow once the sentinel says the account is no longer sanctioned
///      in the namespace captured at deployment.
interface IWildcatSanctionsEscrow {
  event EscrowReleased(address indexed account, address indexed asset, uint256 amount);

  error CanNotReleaseEscrow();

  /// @notice sentinel that deployed and controls this escrow's release condition.
  function sentinel() external view returns (address);

  /// @notice borrower namespace used for sanctions checks.
  function borrower() external view returns (address);

  /// @notice account that receives the asset when the escrow is released.
  function account() external view returns (address);

  /// @notice current balance of the escrowed asset.
  function balance() external view returns (uint256);

  /// @notice whether the sentinel currently permits release to `account`.
  function canReleaseEscrow() external view returns (bool);

  /// @notice returns the escrowed token and its current balance.
  function escrowedAsset() external view returns (address token, uint256 amount);

  /// @notice sends the complete escrowed balance to `account`.
  function releaseEscrow() external;
}

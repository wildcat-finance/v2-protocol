// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IWildcatSanctionsEscrow
// ║  ██▀▀     ▀▀██   Conditional release of borrower-scoped sanctioned assets.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CONFIGURATION
// ║  sentinel()
// ║  borrower()
// ║  account()
// ║
// ║  ESCROW RELEASE
// ║  releaseEscrow()
// ║  canReleaseEscrow()
// ║
// ║  ASSET QUERIES
// ║  escrowedAsset()
// ║  balance()
// ╚═════

// ┌─ IWildcatSanctionsEscrow ──────────────────────────────────────────────────
/// @notice deterministic escrow for one borrower namespace, sanctioned account, and asset.
///
/// @dev anyone may release the escrow once the sentinel says the account is no longer sanctioned
///      in the namespace captured at deployment.
interface IWildcatSanctionsEscrow {
  event EscrowReleased(address indexed account, address indexed asset, uint256 amount);

  error CanNotReleaseEscrow();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ sentinel ─────
  /// @notice sentinel that deployed and controls this escrow's release condition.
  function sentinel() external view returns (address);

  // ┌─ borrower ─────
  /// @notice borrower namespace used for sanctions checks.
  function borrower() external view returns (address);

  // ┌─ account ─────
  /// @notice account that receives the asset when the escrow is released.
  function account() external view returns (address);

  // ░░▒▒▓▓██ [ ESCROW RELEASE ] ───────────────────────────────────────────────

  // ┌─ releaseEscrow ─────
  /// @notice sends the complete escrowed balance to `account`.
  function releaseEscrow() external;

  // ┌─ canReleaseEscrow ─────
  /// @notice whether the sentinel currently permits release to `account`.
  function canReleaseEscrow() external view returns (bool);

  // ░░▒▒▓▓██ [ ASSET QUERIES ] ────────────────────────────────────────────────

  // ┌─ escrowedAsset ─────
  /// @notice returns the escrowed token and its current balance.
  function escrowedAsset() external view returns (address token, uint256 amount);

  // ┌─ balance ─────
  /// @notice current balance of the escrowed asset.
  function balance() external view returns (uint256);
}

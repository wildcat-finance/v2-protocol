// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // IChainalysisSanctionsList
// ║  ██▀▀     ▀▀██   External sanctions-oracle query surface.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SANCTION STATUS
// ║  isSanctioned(...)
// ╚═════

// ┌─ IChainalysisSanctionsList ────────────────────────────────────────────────
/// @notice minimal interface for the external Chainalysis sanctions oracle.
interface IChainalysisSanctionsList {
  // ░░▒▒▓▓██ [ SANCTION STATUS ] ──────────────────────────────────────────────

  // ┌─ isSanctioned ─────
  /// @notice return the oracle's raw sanction status for `addr`.
  function isSanctioned(address addr) external view returns (bool);
}

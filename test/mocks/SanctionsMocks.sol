// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // SanctionsMocks
// ║  ██▀▀     ▀▀██   Mutable sanctions status for protocol tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SANCTIONS STATUS
// ║  sanction(...)
// ║  unsanction(...)
// ╚═════

// ┌─ SanctionsListMock ────────────────────────────────────────────────────────
contract SanctionsListMock {
  mapping(address account => bool sanctioned) public isSanctioned;

  // ░░▒▒▓▓██ [ SANCTIONS STATUS ] ─────────────────────────────────────────────

  // ┌─ sanction ─────
  function sanction(address account) external {
    isSanctioned[account] = true;
  }

  // ┌─ unsanction ─────
  function unsanction(address account) external {
    isSanctioned[account] = false;
  }
}

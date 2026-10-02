// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // HooksFactoryMocks
// ║  ██▀▀     ▀▀██   Reverting hook-template construction for factory tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  FAILED CONSTRUCTION
// ║  constructor()
// ╚═════

// ┌─ BrokenHooksTemplate ──────────────────────────────────────────────────────
contract BrokenHooksTemplate {
  // ░░▒▒▓▓██ [ FAILED CONSTRUCTION ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() {
    assembly {
      revert(0, 0)
    }
  }
}

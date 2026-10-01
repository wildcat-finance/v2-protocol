// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // UniversalProvider
// ║  ██▀▀     ▀▀██   Development credentials available to every account.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CREDENTIALS
// ║  getCredential(...)
// ║  validateCredential(...)
// ╚═════

import 'src/access/IRoleProvider.sol';

// ┌─ UniversalProvider ────────────────────────────────────────────────────────
contract UniversalProvider is IRoleProvider {
  bool public constant override isPullProvider = true;

  // ░░▒▒▓▓██ [ CREDENTIALS ] ──────────────────────────────────────────────────

  // ┌─ getCredential ─────
  function getCredential(address) external view returns (uint32 timestamp) {
    return uint32(block.timestamp);
  }

  // ┌─ validateCredential ─────
  function validateCredential(address, bytes calldata) external view override returns (uint32 timestamp) {
    return uint32(block.timestamp);
  }
}

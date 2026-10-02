// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // BorrowerIdentityMocks
// ║  ██▀▀     ▀▀██   Borrower account and registry-registration test doubles.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ACCOUNT REGISTRATION
// ║  constructor(...)
// ║  registerAccount(...)
// ╚═════

import { IBorrowerIdentityRegistry } from 'src/interfaces/IBorrowerIdentityRegistry.sol';

// ┌─ BorrowerIdentityAccountMock ──────────────────────────────────────────────
contract BorrowerIdentityAccountMock { }

// ┌─ BorrowerIdentityAccountFactoryMock ───────────────────────────────────────
contract BorrowerIdentityAccountFactoryMock {
  IBorrowerIdentityRegistry public immutable registry;

  // ░░▒▒▓▓██ [ ACCOUNT REGISTRATION ] ─────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  // ┌─ registerAccount ─────
  function registerAccount(address account, address principal) external {
    registry.registerBorrowerAccount(account, principal);
  }
}

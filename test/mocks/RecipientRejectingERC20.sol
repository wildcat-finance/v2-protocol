// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // RecipientRejectingERC20
// ║  ██▀▀     ▀▀██   ERC-20 transfer rejection and false-return test behavior.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  TOKEN SETUP
// ║  constructor()
// ║  rejectRecipient(...)
// ║
// ║  TOKEN TRANSFERS
// ║  transfer(...)
// ║  transferFrom(...)
// ╚═════

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

// ┌─ RecipientRejectingERC20 ──────────────────────────────────────────────────
contract RecipientRejectingERC20 is MockERC20 {
  error RecipientRejected();

  address public rejectedRecipient;
  bool public returnsFalse;

  // ░░▒▒▓▓██ [ TOKEN SETUP ] ──────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() MockERC20('Token', 'TKN', 18) { }

  // ┌─ rejectRecipient ─────
  function rejectRecipient(address recipient, bool returnFalse) external {
    rejectedRecipient = recipient;
    returnsFalse = returnFalse;
  }

  // ░░▒▒▓▓██ [ TOKEN TRANSFERS ] ──────────────────────────────────────────────

  // ┌─ transfer ─────
  function transfer(address to, uint256 amount) public override returns (bool) {
    if (to == rejectedRecipient) {
      if (returnsFalse) return false;
      revert RecipientRejected();
    }
    return super.transfer(to, amount);
  }

  // ┌─ transferFrom ─────
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    if (to == rejectedRecipient) {
      if (returnsFalse) return false;
      revert RecipientRejected();
    }
    return super.transferFrom(from, to, amount);
  }
}

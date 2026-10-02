// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MockERC20
//  \ ^ /   Development token with an unrestricted faucet.
//    V
//
//  SETUP
//  constructor(...)
//
//  FAUCET
//  faucet()
// ═════

import { MockERC20 as SolmateMockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

// ┌─ MockERC20 ────────────────────────────────────────────────────────────────
contract MockERC20 is SolmateMockERC20 {
  bool public constant isMock = true;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(string memory _name, string memory _symbol) SolmateMockERC20(_name, _symbol, 18) { }

  // ░░▒▒▓▓██ [ FAUCET ] ───────────────────────────────────────────────────────

  // ┌─ faucet ─────
  function faucet() external {
    mint(msg.sender, 100e18);
  }
}

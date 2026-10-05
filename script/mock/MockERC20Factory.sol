// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MockERC20Factory
//  \ ^ /   Deploy and seed development ERC-20 tokens.
//    V
//
//  TOKEN DEPLOYMENT
//  deploy(...)
// ═════

import './MockERC20.sol';

// ┌─ MockERC20Factory ─────────────────────────────────────────────────────────
contract MockERC20Factory {
  event NewTokenDeployed(address indexed token, string name, string symbol, uint8 decimals);

  // ░░▒▒▓▓██ [ TOKEN DEPLOYMENT ] ─────────────────────────────────────────────

  // ┌─ deploy ─────
  function deploy(string memory name, string memory symbol) external returns (address) {
    MockERC20 token = new MockERC20(name, symbol);
    token.mint(msg.sender, 100e18);
    emit NewTokenDeployed(address(token), name, symbol, 18);
    return address(token);
  }
}

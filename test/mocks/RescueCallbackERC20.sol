// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // RescueCallbackERC20
//  \ ^ /   Token-transfer callbacks for market recovery guard tests.
//    V
//
//  CALLBACK INTERFACE
//  onTokenTransfer()
//
//  TOKEN SETUP
//  constructor()
//  setCallback(...)
//
//  TOKEN TRANSFERS
//  transfer(...)
// ═════

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

// ┌─ IRescueTokenCallback ─────────────────────────────────────────────────────
interface IRescueTokenCallback {
  // ┌─ onTokenTransfer ─────
  function onTokenTransfer() external;
}

// ┌─ RescueCallbackERC20 ─────────────────────────────────────────────────────
contract RescueCallbackERC20 is MockERC20 {
  IRescueTokenCallback public callback;

  // ░░▒▒▓▓██ [ TOKEN SETUP ] ──────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() MockERC20('Callback Token', 'CBT', 18) { }

  // ┌─ setCallback ─────
  function setCallback(address target) external {
    callback = IRescueTokenCallback(target);
  }

  // ░░▒▒▓▓██ [ TOKEN TRANSFERS ] ──────────────────────────────────────────────

  // ┌─ transfer ─────
  function transfer(address to, uint256 amount) public override returns (bool) {
    bool success = super.transfer(to, amount);
    if (address(callback) != address(0)) callback.onTokenTransfer();
    return success;
  }
}

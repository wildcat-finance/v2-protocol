// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // HooksConfigCaller
// ║  ██▀▀     ▀▀██   ABI entry points for exact hook-calldata dispatch tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DISPATCH SETUP
// ║  setState(...)
// ║  setConfig(...)
// ║
// ║  LENDER OPERATIONS
// ║  deposit(...)
// ║  transfer(...)
// ║  queueWithdrawal(...)
// ║  executeWithdrawal(...)
// ║
// ║  BORROWER OPERATIONS
// ║  borrow(...)
// ║  repay(...)
// ║  closeMarket()
// ║
// ║  MARKET CONFIGURATION
// ║  setMaxTotalSupply(...)
// ║  setAnnualInterestAndReserveRatioBips(...)
// ║  setProtocolFeeBips(...)
// ║  nukeFromOrbit(...)
// ╚═════

import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';

// ┌─ HooksConfigCaller ────────────────────────────────────────────────────────
/// @dev call LibHooksConfig through ordinary ABI entrypoints. tests append bytes after the
///      arguments to match the market's raw extraData suffix.
contract HooksConfigCaller {
  HooksConfig internal hooks;
  MarketState internal state;

  // ░░▒▒▓▓██ [ DISPATCH SETUP ] ───────────────────────────────────────────────

  // ┌─ setState ─────
  function setState(MarketState calldata newState) external {
    state = newState;
  }

  // ┌─ setConfig ─────
  function setConfig(HooksConfig newHooks) external {
    hooks = newHooks;
  }

  // ░░▒▒▓▓██ [ LENDER OPERATIONS ] ────────────────────────────────────────────

  // ┌─ deposit ─────
  function deposit(uint256 scaledAmount) external {
    hooks.onDeposit(msg.sender, scaledAmount, state);
  }

  // ┌─ transfer ─────
  function transfer(address to, uint256 scaledAmount) external {
    hooks.onTransfer(msg.sender, to, scaledAmount, state, 0x44);
  }

  // ┌─ queueWithdrawal ─────
  function queueWithdrawal(uint32 expiry, uint256 scaledAmount) external {
    hooks.onQueueWithdrawal(msg.sender, expiry, scaledAmount, state, 0x44);
  }

  // ┌─ executeWithdrawal ─────
  function executeWithdrawal(address lender, uint32 expiry, uint128 normalizedAmountWithdrawn) external {
    hooks.onExecuteWithdrawal(lender, expiry, normalizedAmountWithdrawn, state, 0x64);
  }

  // ░░▒▒▓▓██ [ BORROWER OPERATIONS ] ──────────────────────────────────────────

  // ┌─ borrow ─────
  function borrow(uint256 normalizedAmount) external {
    hooks.onBorrow(normalizedAmount, state);
  }

  // ┌─ repay ─────
  function repay(uint256 normalizedAmount) external {
    hooks.onRepay(normalizedAmount, state, 0x24);
  }

  // ┌─ closeMarket ─────
  function closeMarket() external {
    hooks.onCloseMarket(state);
  }

  // ░░▒▒▓▓██ [ MARKET CONFIGURATION ] ─────────────────────────────────────────

  // ┌─ setMaxTotalSupply ─────
  function setMaxTotalSupply(uint256 maxTotalSupply) external {
    hooks.onSetMaxTotalSupply(maxTotalSupply, state);
  }

  // ┌─ setAnnualInterestAndReserveRatioBips ─────
  function setAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  )
    external
    returns (uint16, uint16)
  {
    return hooks.onSetAnnualInterestAndReserveRatioBips(annualInterestBips, reserveRatioBips, state);
  }

  // ┌─ setProtocolFeeBips ─────
  function setProtocolFeeBips(uint16 protocolFeeBips) external {
    hooks.onSetProtocolFeeBips(protocolFeeBips, state);
  }

  // ┌─ nukeFromOrbit ─────
  function nukeFromOrbit(address lender) external {
    hooks.onNukeFromOrbit(lender, state);
  }
}

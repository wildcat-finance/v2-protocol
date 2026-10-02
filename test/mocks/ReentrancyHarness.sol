// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ReentrancyHarness
//  \ ^ /   Stateful and view reentrancy guard test entry points.
//    V
//
//  STATEFUL CALLS
//  increment()
//  callIncrement()
//  reenterStateful()
//
//  VIEW CALLS
//  readIndex()
//  callRead()
//  reenterView()
// ═════

import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';

// ┌─ ReentrancyHarness ────────────────────────────────────────────────────────
contract ReentrancyHarness is ReentrancyGuard {
  uint256 public index;

  // ░░▒▒▓▓██ [ STATEFUL CALLS ] ───────────────────────────────────────────────

  // ┌─ increment ─────
  function increment() external nonReentrant returns (uint256 previous) {
    previous = index++;
  }

  // ┌─ callIncrement ─────
  function callIncrement() external returns (uint256) {
    return this.increment();
  }

  // ┌─ reenterStateful ─────
  function reenterStateful() external nonReentrant returns (uint256) {
    return this.increment();
  }

  // ░░▒▒▓▓██ [ VIEW CALLS ] ───────────────────────────────────────────────────

  // ┌─ readIndex ─────
  function readIndex() external view nonReentrantView returns (uint256) {
    return index;
  }

  // ┌─ callRead ─────
  function callRead() external view returns (uint256) {
    return this.readIndex();
  }

  // ┌─ reenterView ─────
  function reenterView() external nonReentrant returns (uint256) {
    return this.readIndex();
  }
}

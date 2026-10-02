// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // FIFOQueueLibExternal
// ║  ██▀▀     ▀▀██   External adapters for queue updates and queries.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  QUEUE UPDATES
// ║  $push(...)
// ║  $shift(...)
// ║  $shiftN(...)
// ║
// ║  QUEUE QUERIES
// ║  $empty(...)
// ║  $length(...)
// ║  $first(...)
// ║  $at(...)
// ║  $values(...)
// ║  $word(...)
// ╚═════

import 'src/libraries/FIFOQueue.sol';

// ┌─ FIFOQueueLibExternal ─────────────────────────────────────────────────────
library FIFOQueueLibExternal {
  error FIFOQueueOutOfBounds();

  // ░░▒▒▓▓██ [ QUEUE UPDATES ] ────────────────────────────────────────────────

  // ┌─ $push ─────
  function $push(FIFOQueue storage self, uint32 value) external {
    FIFOQueueLib.push(self, value);
  }

  // ┌─ $shift ─────
  function $shift(FIFOQueue storage self) external {
    FIFOQueueLib.shift(self);
  }

  // ┌─ $shiftN ─────
  function $shiftN(FIFOQueue storage self, uint128 n) external {
    FIFOQueueLib.shiftN(self, n);
  }

  // ░░▒▒▓▓██ [ QUEUE QUERIES ] ────────────────────────────────────────────────

  // ┌─ $empty ─────
  function $empty(FIFOQueue storage arr) external view returns (bool) {
    return FIFOQueueLib.empty(arr);
  }

  // ┌─ $length ─────
  function $length(FIFOQueue storage self) external view returns (uint256) {
    return FIFOQueueLib.length(self);
  }

  // ┌─ $first ─────
  function $first(FIFOQueue storage self) external view returns (uint32) {
    return FIFOQueueLib.first(self);
  }

  // ┌─ $at ─────
  function $at(FIFOQueue storage self, uint256 index) external view returns (uint32) {
    return FIFOQueueLib.at(self, index);
  }

  // ┌─ $values ─────
  function $values(FIFOQueue storage self) external view returns (uint32[] memory) {
    return FIFOQueueLib.values(self);
  }

  // ┌─ $word ─────
  function $word(FIFOQueue storage self, uint256 index) external view returns (uint256) {
    return self.data[index];
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // BoolUtils
//  \ ^ /   Bitwise operations on canonical boolean values.
//    V
//
//  BOOLEAN OPERATIONS
//  and(...)
//  or(...)
//  xor(...)
// ═════

// ┌─ BoolUtils ────────────────────────────────────────────────────────────────
library BoolUtils {
  // ░░▒▒▓▓██ [ BOOLEAN OPERATIONS ] ───────────────────────────────────────────

  // ┌─ and ─────
  function and(bool a, bool b) internal pure returns (bool c) {
    assembly {
      c := and(a, b)
    }
  }

  // ┌─ or ─────
  function or(bool a, bool b) internal pure returns (bool c) {
    assembly {
      c := or(a, b)
    }
  }

  // ┌─ xor ─────
  function xor(bool a, bool b) internal pure returns (bool c) {
    assembly {
      c := xor(a, b)
    }
  }
}

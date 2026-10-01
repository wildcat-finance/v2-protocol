// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // BoolUtils.t
// ║  ██▀▀     ▀▀██   Boolean operation equivalence tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  BOOLEAN OPERATIONS
// ║  test_and(...)
// ║  test_or(...)
// ║  test_xor(...)
// ╚═════

import { BoolUtils } from 'src/libraries/BoolUtils.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ BoolUtilsTest ────────────────────────────────────────────────────────────
contract BoolUtilsTest is TestKernel {
  // ░░▒▒▓▓██ [ BOOLEAN OPERATIONS ] ───────────────────────────────────────────

  // ┌─ test_and ─────
  function test_and(bool a, bool b) external pure {
    assertEq(BoolUtils.and(a, b), a && b);
  }

  // ┌─ test_or ─────
  function test_or(bool a, bool b) external pure {
    assertEq(BoolUtils.or(a, b), a || b);
  }

  // ┌─ test_xor ─────
  function test_xor(bool a, bool b) external pure {
    assertEq(BoolUtils.xor(a, b), a != b);
  }
}

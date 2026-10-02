// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MathUtils.t
// ║  ██▀▀     ▀▀██   Bounds, fixed-point arithmetic, and interest calculation tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  BOUNDS AND SELECTION
// ║  test_max(...)
// ║  test_satSub(...)
// ║  test_satAdd(...)
// ║  test_satAdd_OverflowReturnsMaximum()
// ║
// ║  MULTIPLY AND DIVIDE
// ║  test_mulDiv(...)
// ║  test_mulDivUp(...)
// ║
// ║  BASIS POINTS
// ║  test_bipMul()
// ║  test_bipMul(...)
// ║  test_bipDiv(...)
// ║  test_bipToRay()
// ║  test_bipToRay(...)
// ║
// ║  RAY ARITHMETIC
// ║  test_rayMul()
// ║  test_rayMul(...)
// ║  test_rayDiv()
// ║  test_rayDiv_RevertsOnZeroDenominator()
// ║  test_rayDiv_RevertsOnOverflow()
// ║
// ║  INTEREST
// ║  test_calculateLinearInterestFromBips(...)
// ║  test_calculateLinearInterestFromBips()
// ╚═════

import './wrappers/MathUtilsExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// coverage workaround for MathUtils: the external wrapper uses library-qualified calls
// (XLib.x(value)), so the mapper sees the library identifier instead of value.x().
// ┌─ MathUtilsExternalTest ────────────────────────────────────────────────────
contract MathUtilsExternalTest is TestKernel {
  bytes4 constant TestPanicErrorSelector = 0x4e487b71;
  uint256 constant TestPanicArithmetic = 0x11;
  bytes internal ArithmeticError = abi.encodePacked(TestPanicErrorSelector, TestPanicArithmetic);

  // ░░▒▒▓▓██ [ BOUNDS AND SELECTION ] ─────────────────────────────────────────

  // ┌─ test_max ─────
  function test_max(uint256 a, uint256 b) external pure {
    assertEq(MathUtilsExternal.max(a, b), a > b ? a : b);
  }

  // ┌─ test_satSub ─────
  function test_satSub(uint256 a, uint256 b) external pure {
    if (b > a) {
      assertEq(MathUtilsExternal.satSub(a, b), 0);
    } else {
      assertEq(MathUtilsExternal.satSub(a, b), a - b);
    }
  }

  // ┌─ test_satAdd ─────
  function test_satAdd(uint256 a, uint256 b, uint256 maxValue) external pure {
    uint256 expected;
    if (a >= maxValue || b >= maxValue - a) {
      expected = maxValue;
    } else {
      expected = a + b;
    }
    assertEq(MathUtilsExternal.satAdd(a, b, maxValue), expected);
  }

  // ┌─ test_satAdd_OverflowReturnsMaximum ─────
  function test_satAdd_OverflowReturnsMaximum() external pure {
    assertEq(MathUtilsExternal.satAdd(type(uint256).max, 1, type(uint256).max), type(uint256).max);
  }

  // ░░▒▒▓▓██ [ MULTIPLY AND DIVIDE ] ──────────────────────────────────────────

  // ┌─ test_mulDiv ─────
  function test_mulDiv(uint256 a, uint256 b, uint256 c) external {
    if (c == 0 || (b != 0 && a > (type(uint256).max / b))) {
      vm.expectRevert(MathUtilsExternal.MulDivFailed.selector);
      MathUtilsExternal.mulDiv(a, b, c);
    } else {
      assertEq(MathUtilsExternal.mulDiv(a, b, c), (a * b) / c);
    }
  }

  // ┌─ test_mulDivUp ─────
  function test_mulDivUp(uint256 a, uint256 b, uint256 c) external {
    if (c != 0 && (b == 0 || a <= type(uint256).max / b)) {
      uint256 result = a == 0 || b == 0 ? 0 : (a * b - 1) / c + 1;
      assertEq(MathUtilsExternal.mulDivUp(a, b, c), result);
    } else {
      vm.expectRevert(MathUtilsExternal.MulDivFailed.selector);
      MathUtilsExternal.mulDivUp(a, b, c);
    }
  }

  // ░░▒▒▓▓██ [ BASIS POINTS ] ─────────────────────────────────────────────────

  // ┌─ test_bipMul ─────
  function test_bipMul() external pure {
    assertEq(MathUtilsExternal.bipMul(BIP, BIP), BIP);
    assertEq(MathUtilsExternal.bipMul(100, 1999), 20);
  }

  // ┌─ test_bipMul ─────
  function test_bipMul(uint a, uint b) external {
    if (b == 0 || a <= (type(uint256).max - HALF_BIP) / b) {
      assertEq(MathUtilsExternal.bipMul(a, b), ((a * b) + HALF_BIP) / BIP);
    } else {
      vm.expectRevert(ArithmeticError);
      MathUtilsExternal.bipMul(a, b);
    }
  }

  // ┌─ test_bipDiv ─────
  function test_bipDiv(uint256 a, uint256 b) external {
    if (b > 0 && a <= (type(uint256).max - (b / 2)) / BIP) {
      assertEq(MathUtilsExternal.bipDiv(a, b), ((a * BIP) + (b / 2)) / b);
    } else {
      vm.expectRevert(ArithmeticError);
      MathUtilsExternal.bipDiv(a, b);
    }
  }

  // ┌─ test_bipToRay ─────
  function test_bipToRay() external {
    assertEq(MathUtilsExternal.bipToRay(BIP), RAY);
    vm.expectRevert(ArithmeticError);
    MathUtilsExternal.bipToRay((type(uint256).max / BIP_RAY_RATIO) + 1);
  }

  // ┌─ test_bipToRay ─────
  function test_bipToRay(uint256 a) external {
    unchecked {
      uint256 b;
      if ((b = a * BIP_RAY_RATIO) / BIP_RAY_RATIO == a) {
        assertEq(MathUtilsExternal.bipToRay(a), b);
      } else {
        vm.expectRevert(ArithmeticError);
        MathUtilsExternal.bipToRay(a);
      }
    }
  }

  // ░░▒▒▓▓██ [ RAY ARITHMETIC ] ───────────────────────────────────────────────

  // ┌─ test_rayMul ─────
  function test_rayMul() external pure {
    assertEq(MathUtilsExternal.rayMul(RAY, RAY), RAY);
    assertEq(MathUtilsExternal.rayMul(100, 1.99e26), 20);
  }

  // ┌─ test_rayMul ─────
  function test_rayMul(uint a, uint b) external {
    if (b == 0 || a <= (type(uint256).max - HALF_RAY) / b) {
      assertEq(MathUtilsExternal.rayMul(a, b), ((a * b) + HALF_RAY) / RAY);
    } else {
      vm.expectRevert(ArithmeticError);
      MathUtilsExternal.rayMul(a, b);
    }
  }

  // ┌─ test_rayDiv ─────
  function test_rayDiv() external pure {
    assertEq(MathUtilsExternal.rayDiv(RAY, RAY), RAY);
    assertEq(MathUtilsExternal.rayDiv(1, 2), 5e26);
  }

  // ┌─ test_rayDiv_RevertsOnZeroDenominator ─────
  function test_rayDiv_RevertsOnZeroDenominator() external {
    vm.expectRevert(ArithmeticError);
    MathUtilsExternal.rayDiv(1, 0);
  }

  // ┌─ test_rayDiv_RevertsOnOverflow ─────
  function test_rayDiv_RevertsOnOverflow() external {
    uint256 overflowingNumerator = (type(uint256).max / RAY) + 1;

    vm.expectRevert(ArithmeticError);
    MathUtilsExternal.rayDiv(overflowingNumerator, 1);
  }

  // ░░▒▒▓▓██ [ INTEREST ] ─────────────────────────────────────────────────────

  // ┌─ test_calculateLinearInterestFromBips ─────
  function test_calculateLinearInterestFromBips(uint256 bips, uint256 delta) external pure {
    bips = bound(bips, 0, 10000);
    delta = bound(delta, 0, type(uint32).max);
    uint256 interest = delta == 0 ? 0 : (MathUtilsExternal.bipToRay(bips) * delta) / SECONDS_IN_365_DAYS;
    assertEq(MathUtilsExternal.calculateLinearInterestFromBips(bips, delta), interest);
  }

  // ┌─ test_calculateLinearInterestFromBips ─────
  function test_calculateLinearInterestFromBips() external pure {
    assertEq(MathUtilsExternal.calculateLinearInterestFromBips(1000, 365 days), 1e26);
  }
}

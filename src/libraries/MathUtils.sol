// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MathUtils
//  \ ^ /   Bounded arithmetic, fixed-point scaling, and linear interest.
//    V
//
//  BOUNDS AND SELECTION
//  min(...)
//  max(...)
//  ternary(...)
//  satSub(...)
//  satAdd(...)
//
//  MULTIPLY AND DIVIDE
//  mulDiv(...)
//  mulDivUp(...)
//
//  BASIS POINTS
//  bipMul(...)
//  bipDiv(...)
//  bipToRay(...)
//
//  RAY ARITHMETIC
//  rayMul(...)
//  rayDiv(...)
//
//  INTEREST
//  calculateLinearInterestFromBips(...)
// ═════

import './Errors.sol';

uint256 constant BIP = 1e4;
uint256 constant HALF_BIP = 0.5e4;

uint256 constant RAY = 1e27;
uint256 constant HALF_RAY = 0.5e27;

uint256 constant BIP_RAY_RATIO = 1e23;

uint256 constant SECONDS_IN_365_DAYS = 365 days;

// ┌─ MathUtils ────────────────────────────────────────────────────────────────
library MathUtils {
  /// @dev multiply-divide failed: the product overflowed or the divisor was zero.
  error MulDivFailed();

  using MathUtils for uint256;

  // ░░▒▒▓▓██ [ BOUNDS AND SELECTION ] ─────────────────────────────────────────

  // ┌─ min ─────
  /// @dev return the smaller of `a` and `b`.
  function min(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = ternary(a < b, a, b);
  }

  // ┌─ max ─────
  /// @dev return the larger of `a` and `b`.
  function max(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = ternary(a < b, b, a);
  }

  // ┌─ ternary ─────
  /// @dev select `condition ? valueIfTrue : valueIfFalse`.
  function ternary(bool condition, uint256 valueIfTrue, uint256 valueIfFalse) internal pure returns (uint256 c) {
    assembly ('memory-safe') {
      c := add(valueIfFalse, mul(condition, sub(valueIfTrue, valueIfFalse)))
    }
  }

  // ┌─ satSub ─────
  /// @dev subtract `b` from `a`, saturating at zero.
  function satSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
    assembly ('memory-safe') {
      // (a > b) * (a - b)
      // if a-b underflows, the product is zero.
      c := mul(gt(a, b), sub(a, b))
    }
  }

  // ┌─ satAdd ─────
  /// @dev cap `a + b` at `maxValue`, including when the sum overflows uint256.
  function satAdd(uint256 a, uint256 b, uint256 maxValue) internal pure returns (uint256 c) {
    unchecked {
      c = a + b;
      return ternary(c < a || c >= maxValue, maxValue, c);
    }
  }

  // ░░▒▒▓▓██ [ MULTIPLY AND DIVIDE ] ──────────────────────────────────────────

  // ┌─ mulDiv ─────
  /// @dev return `floor(x * y / d)`.
  ///      revert if `x * y` overflows or `d` is zero.
  ///
  /// @custom:author solady/src/utils/FixedPointMathLib.sol
  function mulDiv(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
    assembly ('memory-safe') {
      // equivalent to require(d != 0 && (y == 0 || x <= type(uint256).max / y))
      if iszero(mul(d, iszero(mul(y, gt(x, div(not(0), y)))))) {
        // MulDivFailed()
        mstore(0x00, 0xad251c27)
        revert(0x1c, 0x04)
      }
      z := div(mul(x, y), d)
    }
  }

  // ┌─ mulDivUp ─────
  /// @dev return `ceil(x * y / d)`.
  ///      revert if `x * y` overflows or `d` is zero.
  ///
  /// @custom:author solady/src/utils/FixedPointMathLib.sol
  function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
    assembly ('memory-safe') {
      // equivalent to require(d != 0 && (y == 0 || x <= type(uint256).max / y))
      if iszero(mul(d, iszero(mul(y, gt(x, div(not(0), y)))))) {
        // MulDivFailed()
        mstore(0x00, 0xad251c27)
        revert(0x1c, 0x04)
      }
      z := add(iszero(iszero(mod(mul(x, y), d))), div(mul(x, y), d))
    }
  }

  // ░░▒▒▓▓██ [ BASIS POINTS ] ─────────────────────────────────────────────────

  // ┌─ bipMul ─────
  /// @dev multiply two bip values, rounding half-up.
  ///      see https://twitter.com/transmissions11/status/1451131036377571328
  function bipMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    assembly ('memory-safe') {
      // equivalent to `require(b == 0 || a <= (type(uint256).max - HALF_BIP) / b)`
      if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_BIP), b))))) {
        // Panic(uint256)
        mstore(0, Panic_ErrorSelector)
        // arithmetic overflow: Panic(0x11).
        mstore(Panic_ErrorCodePointer, Panic_Arithmetic)
        // revert(abi.encodeWithSignature("Panic(uint256)", 0x11))
        revert(Error_SelectorPointer, Panic_ErrorLength)
      }

      c := div(add(mul(a, b), HALF_BIP), BIP)
    }
  }

  // ┌─ bipDiv ─────
  /// @dev divide two bip values, rounding half-up.
  ///      see https://twitter.com/transmissions11/status/1451131036377571328
  function bipDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
    assembly ('memory-safe') {
      // equivalent to `require(b != 0 && a <= (type(uint256).max - b/2) / BIP)`
      if or(iszero(b), gt(a, div(sub(not(0), div(b, 2)), BIP))) {
        mstore(0, Panic_ErrorSelector)
        mstore(Panic_ErrorCodePointer, Panic_Arithmetic)
        revert(Error_SelectorPointer, Panic_ErrorLength)
      }

      c := div(add(mul(a, BIP), div(b, 2)), b)
    }
  }

  // ┌─ bipToRay ─────
  /// @dev convert bip to ray.
  function bipToRay(uint256 a) internal pure returns (uint256 b) {
    // to avoid overflow, b/BIP_RAY_RATIO == a
    assembly ('memory-safe') {
      b := mul(a, BIP_RAY_RATIO)
      // equivalent to `require((b = a * BIP_RAY_RATIO) / BIP_RAY_RATIO == a )
      if iszero(eq(div(b, BIP_RAY_RATIO), a)) {
        mstore(0, Panic_ErrorSelector)
        mstore(Panic_ErrorCodePointer, Panic_Arithmetic)
        revert(Error_SelectorPointer, Panic_ErrorLength)
      }
    }
  }

  // ░░▒▒▓▓██ [ RAY ARITHMETIC ] ───────────────────────────────────────────────

  // ┌─ rayMul ─────
  /// @dev multiply two ray values, rounding half-up.
  ///      see https://twitter.com/transmissions11/status/1451131036377571328
  function rayMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    assembly ('memory-safe') {
      // equivalent to `require(b == 0 || a <= (type(uint256).max - HALF_RAY) / b)`
      if iszero(or(iszero(b), iszero(gt(a, div(sub(not(0), HALF_RAY), b))))) {
        mstore(0, Panic_ErrorSelector)
        mstore(Panic_ErrorCodePointer, Panic_Arithmetic)
        revert(Error_SelectorPointer, Panic_ErrorLength)
      }

      c := div(add(mul(a, b), HALF_RAY), RAY)
    }
  }

  // ┌─ rayDiv ─────
  /// @dev divide two ray values, rounding half-up.
  ///      see https://twitter.com/transmissions11/status/1451131036377571328
  function rayDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
    assembly ('memory-safe') {
      // equivalent to `require(b != 0 && a <= (type(uint256).max - halfB) / RAY)`
      if or(iszero(b), gt(a, div(sub(not(0), div(b, 2)), RAY))) {
        mstore(0, Panic_ErrorSelector)
        mstore(Panic_ErrorCodePointer, Panic_Arithmetic)
        revert(Error_SelectorPointer, Panic_ErrorLength)
      }

      c := div(add(mul(a, RAY), div(b, 2)), b)
    }
  }

  // ░░▒▒▓▓██ [ INTEREST ] ─────────────────────────────────────────────────────

  // ┌─ calculateLinearInterestFromBips ─────
  /// @dev calculate linear interest over the elapsed interval.
  ///
  /// @param rateBip   annual interest rate, in bips.
  /// @param timeDelta seconds since the last accrual.
  ///
  /// @return result linear interest over `timeDelta`, in ray.
  function calculateLinearInterestFromBips(uint256 rateBip, uint256 timeDelta) internal pure returns (uint256 result) {
    uint256 rate = rateBip.bipToRay();
    uint256 accumulatedInterestRay = rate * timeDelta;
    unchecked {
      return accumulatedInterestRay / SECONDS_IN_365_DAYS;
    }
  }
}

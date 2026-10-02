pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MathUtilsExternal
//  \ ^ /   External adapters for bounded and fixed-point arithmetic.
//    V
//
//  BOUNDS AND SELECTION
//  min(...)
//  max(...)
//  satSub(...)
//  satAdd(...)
//  ternary(...)
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

import 'src/libraries/MathUtils.sol';

// ┌─ MathUtilsExternal ────────────────────────────────────────────────────────
library MathUtilsExternal {
  error MulDivFailed();

  // ░░▒▒▓▓██ [ BOUNDS AND SELECTION ] ─────────────────────────────────────────

  // ┌─ min ─────
  function min(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.min(a, b);
  }

  // ┌─ max ─────
  function max(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.max(a, b);
  }

  // ┌─ satSub ─────
  function satSub(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.satSub(a, b);
  }

  // ┌─ satAdd ─────
  function satAdd(uint256 a, uint256 b, uint256 maxValue) external pure returns (uint256 c) {
    return MathUtils.satAdd(a, b, maxValue);
  }

  // ┌─ ternary ─────
  function ternary(bool condition, uint256 valueIfTrue, uint256 valueIfFalse) external pure returns (uint256 c) {
    return MathUtils.ternary(condition, valueIfTrue, valueIfFalse);
  }

  // ░░▒▒▓▓██ [ MULTIPLY AND DIVIDE ] ──────────────────────────────────────────

  // ┌─ mulDiv ─────
  function mulDiv(uint256 x, uint256 y, uint256 d) external pure returns (uint256 z) {
    return MathUtils.mulDiv(x, y, d);
  }

  // ┌─ mulDivUp ─────
  function mulDivUp(uint256 x, uint256 y, uint256 d) external pure returns (uint256 z) {
    return MathUtils.mulDivUp(x, y, d);
  }

  // ░░▒▒▓▓██ [ BASIS POINTS ] ─────────────────────────────────────────────────

  // ┌─ bipMul ─────
  function bipMul(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.bipMul(a, b);
  }

  // ┌─ bipDiv ─────
  function bipDiv(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.bipDiv(a, b);
  }

  // ┌─ bipToRay ─────
  function bipToRay(uint256 a) external pure returns (uint256 b) {
    return MathUtils.bipToRay(a);
  }

  // ░░▒▒▓▓██ [ RAY ARITHMETIC ] ───────────────────────────────────────────────

  // ┌─ rayMul ─────
  function rayMul(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.rayMul(a, b);
  }

  // ┌─ rayDiv ─────
  function rayDiv(uint256 a, uint256 b) external pure returns (uint256 c) {
    return MathUtils.rayDiv(a, b);
  }

  // ░░▒▒▓▓██ [ INTEREST ] ─────────────────────────────────────────────────────

  // ┌─ calculateLinearInterestFromBips ─────
  function calculateLinearInterestFromBips(uint256 rateBip, uint256 timeDelta) external pure returns (uint256 result) {
    return MathUtils.calculateLinearInterestFromBips(rateBip, timeDelta);
  }
}

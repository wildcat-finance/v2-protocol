// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // SafeCastLib
//  \ ^ /   Checked unsigned narrowing casts with arithmetic panics.
//    V
//
//  UNSIGNED CASTS
//  toUint8(...)
//  toUint16(...)
//  toUint24(...)
//  toUint32(...)
//  toUint40(...)
//  toUint48(...)
//  toUint56(...)
//  toUint64(...)
//  toUint72(...)
//  toUint80(...)
//  toUint88(...)
//  toUint96(...)
//  toUint104(...)
//  toUint112(...)
//  toUint120(...)
//  toUint128(...)
//  toUint136(...)
//  toUint144(...)
//  toUint152(...)
//  toUint160(...)
//  toUint168(...)
//  toUint176(...)
//  toUint184(...)
//  toUint192(...)
//  toUint200(...)
//  toUint208(...)
//  toUint216(...)
//  toUint224(...)
//  toUint232(...)
//  toUint240(...)
//  toUint248(...)
//
//  OVERFLOW GUARD
//  _assertNonOverflow(...)
// ═════

import './Errors.sol';

// ┌─ SafeCastLib ──────────────────────────────────────────────────────────────
library SafeCastLib {
  // ░░▒▒▓▓██ [ UNSIGNED CASTS ] ───────────────────────────────────────────────

  // ┌─ toUint8 ─────
  function toUint8(uint256 x) internal pure returns (uint8 y) {
    _assertNonOverflow(x == (y = uint8(x)));
  }

  // ┌─ toUint16 ─────
  function toUint16(uint256 x) internal pure returns (uint16 y) {
    _assertNonOverflow(x == (y = uint16(x)));
  }

  // ┌─ toUint24 ─────
  function toUint24(uint256 x) internal pure returns (uint24 y) {
    _assertNonOverflow(x == (y = uint24(x)));
  }

  // ┌─ toUint32 ─────
  function toUint32(uint256 x) internal pure returns (uint32 y) {
    _assertNonOverflow(x == (y = uint32(x)));
  }

  // ┌─ toUint40 ─────
  function toUint40(uint256 x) internal pure returns (uint40 y) {
    _assertNonOverflow(x == (y = uint40(x)));
  }

  // ┌─ toUint48 ─────
  function toUint48(uint256 x) internal pure returns (uint48 y) {
    _assertNonOverflow(x == (y = uint48(x)));
  }

  // ┌─ toUint56 ─────
  function toUint56(uint256 x) internal pure returns (uint56 y) {
    _assertNonOverflow(x == (y = uint56(x)));
  }

  // ┌─ toUint64 ─────
  function toUint64(uint256 x) internal pure returns (uint64 y) {
    _assertNonOverflow(x == (y = uint64(x)));
  }

  // ┌─ toUint72 ─────
  function toUint72(uint256 x) internal pure returns (uint72 y) {
    _assertNonOverflow(x == (y = uint72(x)));
  }

  // ┌─ toUint80 ─────
  function toUint80(uint256 x) internal pure returns (uint80 y) {
    _assertNonOverflow(x == (y = uint80(x)));
  }

  // ┌─ toUint88 ─────
  function toUint88(uint256 x) internal pure returns (uint88 y) {
    _assertNonOverflow(x == (y = uint88(x)));
  }

  // ┌─ toUint96 ─────
  function toUint96(uint256 x) internal pure returns (uint96 y) {
    _assertNonOverflow(x == (y = uint96(x)));
  }

  // ┌─ toUint104 ─────
  function toUint104(uint256 x) internal pure returns (uint104 y) {
    _assertNonOverflow(x == (y = uint104(x)));
  }

  // ┌─ toUint112 ─────
  function toUint112(uint256 x) internal pure returns (uint112 y) {
    _assertNonOverflow(x == (y = uint112(x)));
  }

  // ┌─ toUint120 ─────
  function toUint120(uint256 x) internal pure returns (uint120 y) {
    _assertNonOverflow(x == (y = uint120(x)));
  }

  // ┌─ toUint128 ─────
  function toUint128(uint256 x) internal pure returns (uint128 y) {
    _assertNonOverflow(x == (y = uint128(x)));
  }

  // ┌─ toUint136 ─────
  function toUint136(uint256 x) internal pure returns (uint136 y) {
    _assertNonOverflow(x == (y = uint136(x)));
  }

  // ┌─ toUint144 ─────
  function toUint144(uint256 x) internal pure returns (uint144 y) {
    _assertNonOverflow(x == (y = uint144(x)));
  }

  // ┌─ toUint152 ─────
  function toUint152(uint256 x) internal pure returns (uint152 y) {
    _assertNonOverflow(x == (y = uint152(x)));
  }

  // ┌─ toUint160 ─────
  function toUint160(uint256 x) internal pure returns (uint160 y) {
    _assertNonOverflow(x == (y = uint160(x)));
  }

  // ┌─ toUint168 ─────
  function toUint168(uint256 x) internal pure returns (uint168 y) {
    _assertNonOverflow(x == (y = uint168(x)));
  }

  // ┌─ toUint176 ─────
  function toUint176(uint256 x) internal pure returns (uint176 y) {
    _assertNonOverflow(x == (y = uint176(x)));
  }

  // ┌─ toUint184 ─────
  function toUint184(uint256 x) internal pure returns (uint184 y) {
    _assertNonOverflow(x == (y = uint184(x)));
  }

  // ┌─ toUint192 ─────
  function toUint192(uint256 x) internal pure returns (uint192 y) {
    _assertNonOverflow(x == (y = uint192(x)));
  }

  // ┌─ toUint200 ─────
  function toUint200(uint256 x) internal pure returns (uint200 y) {
    _assertNonOverflow(x == (y = uint200(x)));
  }

  // ┌─ toUint208 ─────
  function toUint208(uint256 x) internal pure returns (uint208 y) {
    _assertNonOverflow(x == (y = uint208(x)));
  }

  // ┌─ toUint216 ─────
  function toUint216(uint256 x) internal pure returns (uint216 y) {
    _assertNonOverflow(x == (y = uint216(x)));
  }

  // ┌─ toUint224 ─────
  function toUint224(uint256 x) internal pure returns (uint224 y) {
    _assertNonOverflow(x == (y = uint224(x)));
  }

  // ┌─ toUint232 ─────
  function toUint232(uint256 x) internal pure returns (uint232 y) {
    _assertNonOverflow(x == (y = uint232(x)));
  }

  // ┌─ toUint240 ─────
  function toUint240(uint256 x) internal pure returns (uint240 y) {
    _assertNonOverflow(x == (y = uint240(x)));
  }

  // ┌─ toUint248 ─────
  function toUint248(uint256 x) internal pure returns (uint248 y) {
    _assertNonOverflow(x == (y = uint248(x)));
  }

  // ░░▒▒▓▓██ [ OVERFLOW GUARD ] ───────────────────────────────────────────────

  // ┌─ _assertNonOverflow ─────
  function _assertNonOverflow(bool didNotOverflow) private pure {
    assembly ('memory-safe') {
      if iszero(didNotOverflow) {
        mstore(0, Panic_ErrorSelector)
        mstore(Panic_ErrorCodePointer, Panic_Arithmetic)
        revert(Error_SelectorPointer, Panic_ErrorLength)
      }
    }
  }
}

pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // SafeCastLibExternal
// ║  ██▀▀     ▀▀██   External adapters for checked unsigned integer casts.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  UNSIGNED CASTS
// ║  toUint8(...)
// ║  toUint16(...)
// ║  toUint24(...)
// ║  toUint32(...)
// ║  toUint40(...)
// ║  toUint48(...)
// ║  toUint56(...)
// ║  toUint64(...)
// ║  toUint72(...)
// ║  toUint80(...)
// ║  toUint88(...)
// ║  toUint96(...)
// ║  toUint104(...)
// ║  toUint112(...)
// ║  toUint120(...)
// ║  toUint128(...)
// ║  toUint136(...)
// ║  toUint144(...)
// ║  toUint152(...)
// ║  toUint160(...)
// ║  toUint168(...)
// ║  toUint176(...)
// ║  toUint184(...)
// ║  toUint192(...)
// ║  toUint200(...)
// ║  toUint208(...)
// ║  toUint216(...)
// ║  toUint224(...)
// ║  toUint232(...)
// ║  toUint240(...)
// ║  toUint248(...)
// ╚═════

import { SafeCastLib } from 'src/libraries/SafeCastLib.sol';

// ┌─ SafeCastLibExternal ──────────────────────────────────────────────────────
contract SafeCastLibExternal {
  // ░░▒▒▓▓██ [ UNSIGNED CASTS ] ───────────────────────────────────────────────

  // ┌─ toUint8 ─────
  function toUint8(uint256 x) external pure returns (uint8 y) {
    return SafeCastLib.toUint8(x);
  }

  // ┌─ toUint16 ─────
  function toUint16(uint256 x) external pure returns (uint16 y) {
    return SafeCastLib.toUint16(x);
  }

  // ┌─ toUint24 ─────
  function toUint24(uint256 x) external pure returns (uint24 y) {
    return SafeCastLib.toUint24(x);
  }

  // ┌─ toUint32 ─────
  function toUint32(uint256 x) external pure returns (uint32 y) {
    return SafeCastLib.toUint32(x);
  }

  // ┌─ toUint40 ─────
  function toUint40(uint256 x) external pure returns (uint40 y) {
    return SafeCastLib.toUint40(x);
  }

  // ┌─ toUint48 ─────
  function toUint48(uint256 x) external pure returns (uint48 y) {
    return SafeCastLib.toUint48(x);
  }

  // ┌─ toUint56 ─────
  function toUint56(uint256 x) external pure returns (uint56 y) {
    return SafeCastLib.toUint56(x);
  }

  // ┌─ toUint64 ─────
  function toUint64(uint256 x) external pure returns (uint64 y) {
    return SafeCastLib.toUint64(x);
  }

  // ┌─ toUint72 ─────
  function toUint72(uint256 x) external pure returns (uint72 y) {
    return SafeCastLib.toUint72(x);
  }

  // ┌─ toUint80 ─────
  function toUint80(uint256 x) external pure returns (uint80 y) {
    return SafeCastLib.toUint80(x);
  }

  // ┌─ toUint88 ─────
  function toUint88(uint256 x) external pure returns (uint88 y) {
    return SafeCastLib.toUint88(x);
  }

  // ┌─ toUint96 ─────
  function toUint96(uint256 x) external pure returns (uint96 y) {
    return SafeCastLib.toUint96(x);
  }

  // ┌─ toUint104 ─────
  function toUint104(uint256 x) external pure returns (uint104 y) {
    return SafeCastLib.toUint104(x);
  }

  // ┌─ toUint112 ─────
  function toUint112(uint256 x) external pure returns (uint112 y) {
    return SafeCastLib.toUint112(x);
  }

  // ┌─ toUint120 ─────
  function toUint120(uint256 x) external pure returns (uint120 y) {
    return SafeCastLib.toUint120(x);
  }

  // ┌─ toUint128 ─────
  function toUint128(uint256 x) external pure returns (uint128 y) {
    return SafeCastLib.toUint128(x);
  }

  // ┌─ toUint136 ─────
  function toUint136(uint256 x) external pure returns (uint136 y) {
    return SafeCastLib.toUint136(x);
  }

  // ┌─ toUint144 ─────
  function toUint144(uint256 x) external pure returns (uint144 y) {
    return SafeCastLib.toUint144(x);
  }

  // ┌─ toUint152 ─────
  function toUint152(uint256 x) external pure returns (uint152 y) {
    return SafeCastLib.toUint152(x);
  }

  // ┌─ toUint160 ─────
  function toUint160(uint256 x) external pure returns (uint160 y) {
    return SafeCastLib.toUint160(x);
  }

  // ┌─ toUint168 ─────
  function toUint168(uint256 x) external pure returns (uint168 y) {
    return SafeCastLib.toUint168(x);
  }

  // ┌─ toUint176 ─────
  function toUint176(uint256 x) external pure returns (uint176 y) {
    return SafeCastLib.toUint176(x);
  }

  // ┌─ toUint184 ─────
  function toUint184(uint256 x) external pure returns (uint184 y) {
    return SafeCastLib.toUint184(x);
  }

  // ┌─ toUint192 ─────
  function toUint192(uint256 x) external pure returns (uint192 y) {
    return SafeCastLib.toUint192(x);
  }

  // ┌─ toUint200 ─────
  function toUint200(uint256 x) external pure returns (uint200 y) {
    return SafeCastLib.toUint200(x);
  }

  // ┌─ toUint208 ─────
  function toUint208(uint256 x) external pure returns (uint208 y) {
    return SafeCastLib.toUint208(x);
  }

  // ┌─ toUint216 ─────
  function toUint216(uint256 x) external pure returns (uint216 y) {
    return SafeCastLib.toUint216(x);
  }

  // ┌─ toUint224 ─────
  function toUint224(uint256 x) external pure returns (uint224 y) {
    return SafeCastLib.toUint224(x);
  }

  // ┌─ toUint232 ─────
  function toUint232(uint256 x) external pure returns (uint232 y) {
    return SafeCastLib.toUint232(x);
  }

  // ┌─ toUint240 ─────
  function toUint240(uint256 x) external pure returns (uint240 y) {
    return SafeCastLib.toUint240(x);
  }

  // ┌─ toUint248 ─────
  function toUint248(uint256 x) external pure returns (uint248 y) {
    return SafeCastLib.toUint248(x);
  }
}

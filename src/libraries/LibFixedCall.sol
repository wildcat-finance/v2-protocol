// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LibFixedCall
//  \ ^ /   Fixed-width static calls with strict ABI validation.
//    V
//
//  STATIC QUERIES
//  readWord(...)
//  readBool(...)
// ═════

// ┌─ LibFixedCall ─────────────────────────────────────────────────────────────
library LibFixedCall {
  // ░░▒▒▓▓██ [ STATIC QUERIES ] ───────────────────────────────────────────────

  // ┌─ readWord ─────
  /// @dev read the full ABI word. callers with narrower return types need their own range check.
  function readWord(address target, bytes4 selector) internal view returns (uint256 value) {
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      if iszero(staticcall(gas(), target, add(pointer, 0x1c), 0x04, pointer, 0x20)) {
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      value := mload(pointer)
    }
  }

  // ┌─ readBool ─────
  /// @dev same ABI rules as a Solidity bool call: reject short/dirty returns, accept trailing
  ///      data, and bubble reverts. the success path only copies the one word we need.
  function readBool(address target, bytes4 selector, address argument) internal view returns (bool value) {
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), and(argument, 0xffffffffffffffffffffffffffffffffffffffff))
      if iszero(staticcall(gas(), target, add(pointer, 0x1c), 0x24, pointer, 0x20)) {
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      value := mload(pointer)
      if gt(value, 1) {
        revert(0, 0)
      }
    }
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

library LibFixedCall {
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

  function readAddress(address target, bytes4 selector) internal view returns (address value) {
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
      if shr(160, value) {
        revert(0, 0)
      }
    }
  }

  function readAddress(
    address target,
    bytes4 selector,
    address argument
  ) internal view returns (address value) {
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), argument)
      if iszero(staticcall(gas(), target, add(pointer, 0x1c), 0x24, pointer, 0x20)) {
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      value := mload(pointer)
      if shr(160, value) {
        revert(0, 0)
      }
    }
  }

  function readBool(
    address target,
    bytes4 selector,
    address argument
  ) internal view returns (bool value) {
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), argument)
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

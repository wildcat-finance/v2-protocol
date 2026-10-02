// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // TransientBytesArray
//  \ ^ /   Transaction-scoped byte storage, clearing, and decoding.
//    V
//
//  WRITES
//  write(...)
//  setEmpty(...)
//
//  READS
//  read(...)
//  readToPointer(...)
// ═════

import {
  Panic_ErrorSelector,
  Panic_ErrorCodePointer,
  Panic_InvalidStorageByteArray,
  Error_SelectorPointer,
  Panic_ErrorLength
} from '../libraries/Errors.sol';

/// @notice transient-storage slot holding bytes in Solidity's storage encoding.
/// @dev contents only survive the current transaction.
type TransientBytesArray is uint256;

using LibTransientBytesArray for TransientBytesArray global;

// ┌─ LibTransientBytesArray ───────────────────────────────────────────────────
library LibTransientBytesArray {
  // ░░▒▒▓▓██ [ WRITES ] ───────────────────────────────────────────────────────

  // ┌─ write ─────
  /// @dev write dynamic bytes to transient storage.
  ///
  /// @param transientSlot transient slot holding the bytes header.
  /// @param memoryPointer memory array to write.
  function write(TransientBytesArray transientSlot, bytes memory memoryPointer) internal {
    assembly {
      let length := mload(memoryPointer)
      memoryPointer := add(memoryPointer, 0x20)
      switch lt(length, 32)
      case 0 {
        // long encoding: the header holds length * 2 + 1; data lives at keccak256(slot).
        tstore(transientSlot, add(1, mul(2, length)))
        mstore(0, transientSlot)
        let dataTSlot := keccak256(0, 0x20)
        let i := 0
        for { } lt(i, length) {
          i := add(i, 0x20)
        } {
          tstore(dataTSlot, mload(add(memoryPointer, i)))
          dataTSlot := add(dataTSlot, 1)
        }
      }
      case 1 {
        // short encoding: up to 31 data bytes, then length * 2 in the final byte.
        let lengthByte := mul(2, length)
        let data := mload(memoryPointer)
        tstore(transientSlot, or(data, lengthByte))
      }
    }
  }

  // ┌─ setEmpty ─────
  /// @dev write the empty-array encoding; a later call can overwrite it in the same transaction.
  function setEmpty(TransientBytesArray transientSlot) internal {
    assembly {
      tstore(transientSlot, 0)
    }
  }

  // ░░▒▒▓▓██ [ READS ] ────────────────────────────────────────────────────────

  // ┌─ read ─────
  /// @dev decode the transient byte array into newly allocated memory.
  function read(TransientBytesArray transientSlot) internal view returns (bytes memory data) {
    uint256 dataPointer;
    assembly {
      dataPointer := mload(0x40)
      data := dataPointer
      mstore(data, 0)
    }
    uint256 endPointer = readToPointer(transientSlot, dataPointer);
    assembly {
      mstore(0x40, endPointer)
    }
  }

  // ┌─ readToPointer ─────
  /// @dev decode transient bytes into the caller's memory buffer.
  ///
  /// @param transientSlot transient slot holding the bytes header.
  /// @param memoryPointer start of the destination memory buffer.
  ///
  /// @return endPointer end of the decoded memory array.
  function readToPointer(
    TransientBytesArray transientSlot,
    uint256 memoryPointer
  )
    internal
    view
    returns (uint256 endPointer)
  {
    assembly {
      function extractByteArrayLength(data) -> length {
        length := div(data, 2)
        let outOfPlaceEncoding := and(data, 1)
        if iszero(outOfPlaceEncoding) {
          length := and(length, 0x7f)
        }

        if eq(outOfPlaceEncoding, lt(length, 32)) {
          // Panic(uint256)
          mstore(0, Panic_ErrorSelector)
          // malformed storage-byte-array encoding: Panic(0x22).
          mstore(Panic_ErrorCodePointer, Panic_InvalidStorageByteArray)
          // revert(abi.encodeWithSignature("Panic(uint256)", 0x22))
          revert(Error_SelectorPointer, Panic_ErrorLength)
        }
      }
      let slotValue := tload(transientSlot)
      let length := extractByteArrayLength(slotValue)
      mstore(memoryPointer, length)
      memoryPointer := add(memoryPointer, 0x20)
      switch and(slotValue, 1)
      case 0 {
        // short byte array
        let value := and(slotValue, not(0xff))
        mstore(memoryPointer, value)
        endPointer := add(memoryPointer, 0x20)
      }
      case 1 {
        // long byte array
        mstore(0, transientSlot)
        let dataTSlot := keccak256(0, 0x20)
        let i := 0
        for { } lt(i, length) {
          i := add(i, 0x20)
        } {
          mstore(add(memoryPointer, i), tload(dataTSlot))
          dataTSlot := add(dataTSlot, 1)
        }
        endPointer := add(memoryPointer, i)
      }
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // FIFOQueue
// ║  ██▀▀     ▀▀██   Packed FIFO storage, queue updates, and ordered queries.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  QUEUE UPDATES
// ║  push(...)
// ║  shift(...)
// ║  shiftN(...)
// ║
// ║  QUEUE QUERIES
// ║  empty(...)
// ║  length(...)
// ║  first(...)
// ║  at(...)
// ║  values(...)
// ║  _valueAt(...)
// ╚═════

/// @notice storage queue of packed `uint32` values.
///
/// @dev eight values share each storage word. indexes only move forward.
///
/// @param startIndex absolute index of the first live value.
/// @param nextIndex  absolute index where the next value will be appended.
/// @param data       packed queue words keyed by absolute word index.
struct FIFOQueue {
  uint128 startIndex;
  uint128 nextIndex;
  mapping(uint256 => uint256) data;
}

// @todo add a memory view with (nextIndex, startIndex, storageSlot) only if chained queue
//       operations become frequent enough to justify it.

using FIFOQueueLib for FIFOQueue global;

// ┌─ FIFOQueueLib ─────────────────────────────────────────────────────────────
library FIFOQueueLib {
  /// @notice the requested position doesn't contain a live queue value.
  error FIFOQueueOutOfBounds();

  uint256 internal constant ValuesPerWord = 8;
  uint256 internal constant ValueOffsetMask = ValuesPerWord - 1;
  uint256 internal constant BitsPerValue = 32;

  // ░░▒▒▓▓██ [ QUEUE UPDATES ] ────────────────────────────────────────────────

  // ┌─ push ─────
  /// @dev append `value` without reusing consumed indexes.
  function push(FIFOQueue storage arr, uint32 value) internal {
    uint128 nextIndex = arr.nextIndex;
    uint256 wordIndex = nextIndex / ValuesPerWord;
    uint256 offset = (nextIndex & ValueOffsetMask) * BitsPerValue;
    arr.data[wordIndex] |= uint256(value) << offset;
    arr.nextIndex = nextIndex + 1;
  }

  // ┌─ shift ─────
  /// @dev remove the oldest value; delete packed words only once fully consumed.
  function shift(FIFOQueue storage arr) internal {
    uint128 startIndex = arr.startIndex;
    if (startIndex == arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    uint128 newStartIndex = startIndex + 1;
    // retain a partial word until all eight positions are consumed. this avoids extra
    // zero-to-nonzero writes and retains at most one consumed-but-uncleared word.
    if ((newStartIndex & ValueOffsetMask) == 0) {
      delete arr.data[startIndex / ValuesPerWord];
    }
    arr.startIndex = newStartIndex;
  }

  // ┌─ shiftN ─────
  /// @dev remove the oldest `n` values. revert if fewer are live.
  function shiftN(FIFOQueue storage arr, uint128 n) internal {
    uint128 startIndex = arr.startIndex;
    uint128 newStartIndex = startIndex + n;
    uint128 nextIndex = arr.nextIndex;
    if (newStartIndex > nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    if (n == 0) return;

    uint256 wordIndex = startIndex / ValuesPerWord;
    uint256 endWordIndex = newStartIndex / ValuesPerWord;
    while (wordIndex < endWordIndex) {
      delete arr.data[wordIndex];
      unchecked {
        ++wordIndex;
      }
    }
    arr.startIndex = newStartIndex;
  }

  // ░░▒▒▓▓██ [ QUEUE QUERIES ] ────────────────────────────────────────────────

  // ┌─ empty ─────
  /// @dev return true when the queue has no live values.
  function empty(FIFOQueue storage arr) internal view returns (bool) {
    return arr.nextIndex == arr.startIndex;
  }

  // ┌─ length ─────
  /// @dev return the number of live values.
  function length(FIFOQueue storage arr) internal view returns (uint128) {
    return arr.nextIndex - arr.startIndex;
  }

  // ┌─ first ─────
  /// @dev return the oldest live value. an empty queue reverts.
  function first(FIFOQueue storage arr) internal view returns (uint32) {
    if (arr.startIndex == arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    return _valueAt(arr, arr.startIndex);
  }

  // ┌─ at ─────
  /// @dev return the value at a zero-based live-queue index.
  function at(FIFOQueue storage arr, uint256 index) internal view returns (uint32) {
    index += arr.startIndex;
    if (index >= arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    return _valueAt(arr, index);
  }

  // ┌─ values ─────
  /// @dev copy every live value to memory in FIFO order.
  function values(FIFOQueue storage arr) internal view returns (uint32[] memory _values) {
    uint256 startIndex = arr.startIndex;
    uint256 nextIndex = arr.nextIndex;
    uint256 len = nextIndex - startIndex;
    _values = new uint32[](len);

    for (uint256 i = 0; i < len; i++) {
      _values[i] = _valueAt(arr, startIndex + i);
    }

    return _values;
  }

  // ┌─ _valueAt ─────
  function _valueAt(FIFOQueue storage arr, uint256 index) private view returns (uint32) {
    uint256 word = arr.data[index / ValuesPerWord];
    uint256 offset = (index & ValueOffsetMask) * BitsPerValue;
    return uint32(word >> offset);
  }
}

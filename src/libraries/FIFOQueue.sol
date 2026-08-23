// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

struct FIFOQueue {
  uint128 startIndex;
  uint128 nextIndex;
  mapping(uint256 => uint256) data;
}

// @todo - Add a memory view with (nextIndex, startIndex, storageSlot) if call sites start chaining
//         queue operations often enough for the extra machinery to pay for itself.

using FIFOQueueLib for FIFOQueue global;

library FIFOQueueLib {
  error FIFOQueueOutOfBounds();

  uint256 internal constant ValuesPerWord = 8;
  uint256 internal constant ValueOffsetMask = ValuesPerWord - 1;
  uint256 internal constant BitsPerValue = 32;

  function _valueAt(FIFOQueue storage arr, uint256 index) private view returns (uint32) {
    uint256 word = arr.data[index / ValuesPerWord];
    uint256 offset = (index & ValueOffsetMask) * BitsPerValue;
    return uint32(word >> offset);
  }

  function empty(FIFOQueue storage arr) internal view returns (bool) {
    return arr.nextIndex == arr.startIndex;
  }

  function first(FIFOQueue storage arr) internal view returns (uint32) {
    if (arr.startIndex == arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    return _valueAt(arr, arr.startIndex);
  }

  function at(FIFOQueue storage arr, uint256 index) internal view returns (uint32) {
    index += arr.startIndex;
    if (index >= arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    return _valueAt(arr, index);
  }

  function length(FIFOQueue storage arr) internal view returns (uint128) {
    return arr.nextIndex - arr.startIndex;
  }

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

  function push(FIFOQueue storage arr, uint32 value) internal {
    uint128 nextIndex = arr.nextIndex;
    uint256 wordIndex = nextIndex / ValuesPerWord;
    uint256 offset = (nextIndex & ValueOffsetMask) * BitsPerValue;
    arr.data[wordIndex] |= uint256(value) << offset;
    arr.nextIndex = nextIndex + 1;
  }

  function shift(FIFOQueue storage arr) internal {
    uint128 startIndex = arr.startIndex;
    if (startIndex == arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    uint128 newStartIndex = startIndex + 1;
    // Partial words stay live until all eight positions have been consumed.
    // That avoids extra zero-to-nonzero writes and caps retained storage at one word.
    if ((newStartIndex & ValueOffsetMask) == 0) {
      delete arr.data[startIndex / ValuesPerWord];
    }
    arr.startIndex = newStartIndex;
  }

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
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { LibBit } from 'solady/utils/LibBit.sol';

using LibBit for uint256;

function bytes32ToString(bytes32 value) pure returns (string memory str) {
  uint256 size;
  unchecked {
    uint256 sizeInBits = 256 - uint256(value).ffs();
    size = (sizeInBits + 7) / 8;
  }
  assembly {
    str := mload(0x40)
    mstore(0x40, add(str, 0x40))
    mstore(str, size)
    mstore(add(str, 0x20), value)
  }
}

function queryStringOrBytes32AsString(
  address target,
  uint256 leftPaddedFunctionSelector,
  uint256 leftPaddedGenericErrorSelector
) view returns (string memory str) {
  bool isBytes32;
  assembly {
    mstore(0, leftPaddedFunctionSelector)
    let status := staticcall(gas(), target, 0x1c, 0x04, 0, 0)
    isBytes32 := eq(returndatasize(), 0x20)
    // If call fails or function returns invalid data, revert.
    // Strings are always right padded to full words - if the returndata
    // is not 32 bytes (string encoded as bytes32) or >95 bytes (minimum abi
    // encoded string) it is an invalid string.
    if or(iszero(status), iszero(or(isBytes32, gt(returndatasize(), 0x5f)))) {
      // Check if call failed
      if iszero(status) {
        // Check if any revert data was given
        if returndatasize() {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
        // If not, throw a generic error
        mstore(0, leftPaddedGenericErrorSelector)
        revert(0x1c, 0x04)
      }
      // If the returndata is the wrong size, `revert InvalidReturnDataString()`
      mstore(0, 0x4cb9c000)
      revert(0x1c, 0x04)
    }
  }
  if (isBytes32) {
    bytes32 value;
    assembly {
      returndatacopy(0x00, 0x00, 0x20)
      value := mload(0)
    }
    str = bytes32ToString(value);
  } else {
    // If returndata is a string, validate its canonical ABI shape before
    // copying the length and value into a newly allocated string.
    assembly {
      let returnSize := returndatasize()
      returndatacopy(0, 0, 0x40)
      let length := mload(0x20)
      let paddedLength := and(add(length, 0x1f), not(0x1f))
      if or(
        xor(mload(0), 0x20),
        or(lt(paddedLength, length), xor(returnSize, add(0x40, paddedLength)))
      ) {
        mstore(0, 0x4cb9c000)
        revert(0x1c, 0x04)
      }

      str := mload(0x40)
      let allocSize := add(0x20, paddedLength)
      mstore(0x40, add(str, allocSize))
      // Copy returndata after the offset
      returndatacopy(str, 0x20, allocSize)
    }
  }
}

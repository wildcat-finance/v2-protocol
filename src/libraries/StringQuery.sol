// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { LibBit } from 'solady/utils/LibBit.sol';

using LibBit for uint256;

/// @notice converts a left-aligned, null-padded `bytes32` string to dynamic form.
/// @dev embedded nulls are preserved; only trailing zero bytes are removed.
function bytes32ToString(bytes32 value) pure returns (string memory str) {
  uint256 size;
  unchecked {
    // `bytes32` strings are left-aligned, so the trailing zero bits tell us where the
    // text ends. `ffs` returns 256 for an empty word, which leaves the length at zero.
    uint256 sizeInBits = 256 - uint256(value).ffs();
    size = (sizeInBits + 7) / 8;
  }
  assembly {
    // a memory string is a length word followed by its data. reserve both words,
    // then write the length we just found and the original bytes32 value as-is.
    str := mload(0x40)
    mstore(0x40, add(str, 0x40))
    mstore(str, size)
    mstore(add(str, 0x20), value)
  }
}

/// @notice reads token metadata that may return either `string` or legacy `bytes32`.
/// @dev bubbles target revert data when present. malformed successful returndata reverts with
///      `InvalidReturnDataString`; an empty target revert uses `leftPaddedGenericErrorSelector`.
/// @param target contract queried with a no-argument static call.
/// @param leftPaddedFunctionSelector selector stored in the low four bytes of a word.
/// @param leftPaddedGenericErrorSelector fallback custom-error selector in the low four bytes.
function queryStringOrBytes32AsString(
  address target,
  uint256 leftPaddedFunctionSelector,
  uint256 leftPaddedGenericErrorSelector
) view returns (string memory str) {
  bool isBytes32;
  assembly {
    // the selector is left-padded, so its four useful bytes start at 0x1c.
    mstore(0, leftPaddedFunctionSelector)
    // leave the return buffer alone for now. we validate the shape before copying it.
    let status := staticcall(gas(), target, 0x1c, 0x04, 0, 0)
    isBytes32 := eq(returndatasize(), 0x20)
    // 32 bytes is the legacy bytes32 form. for dynamic strings, this helper expects
    // an offset, a length, and at least one padded data word, so 64-byte returns are out.
    if or(iszero(status), iszero(or(isBytes32, gt(returndatasize(), 0x5f)))) {
      if iszero(status) {
        // keep the target's error when it gave us one.
        if returndatasize() {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
        // no returndata means there's nothing useful to bubble, so use the generic error.
        mstore(0, leftPaddedGenericErrorSelector)
        revert(0x1c, 0x04)
      }
      // the call worked but its return shape didn't. that's InvalidReturnDataString.
      mstore(0, 0x4cb9c000)
      revert(0x1c, 0x04)
    }
  }
  if (isBytes32) {
    bytes32 value;
    assembly {
      // the first call didn't copy returndata. pull the one bytes32 word into scratch now.
      returndatacopy(0x00, 0x00, 0x20)
      value := mload(0)
    }
    str = bytes32ToString(value);
  } else {
    assembly {
      // the dynamic header is [offset][length]. copy just that into scratch first.
      let returnSize := returndatasize()
      returndatacopy(0, 0, 0x40)
      let length := mload(0x20)
      // round the declared length up to an ABI word. wrapping below `length` means
      // the addition overflowed, which is just malformed returndata with extra steps.
      let paddedLength := and(add(length, 0x1f), not(0x1f))
      // data has to start at 0x40 and fit inside returndata. extra trailing bytes are fine.
      if or(
        xor(mload(0), 0x20),
        or(lt(paddedLength, length), gt(paddedLength, sub(returnSize, 0x40)))
      ) {
        mstore(0, 0x4cb9c000)
        revert(0x1c, 0x04)
      }

      str := mload(0x40)
      let allocSize := add(0x20, paddedLength)
      mstore(0x40, add(str, allocSize))
      // start at returndata 0x20 so memory gets [length][data]. leave any trailing
      // returndata behind; it isn't part of the declared string.
      returndatacopy(str, 0x20, allocSize)
    }
  }
}

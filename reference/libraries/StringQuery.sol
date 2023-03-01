// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import './Math.sol';

uint256 constant InvalidReturnDataString_selector = 0x4cb9c00000000000000000000000000000000000000000000000000000000000;

uint256 constant SixtyThreeBytes = 0x3f;
uint256 constant ThirtyOneBytes = 0x1f;
uint256 constant OnlyFullWordMask = 0xffffffe0;

error InvalidReturnDataString();
error InvalidCompactString();

function queryStringOrBytes32AsString(
	address target,
	uint256 rightPaddedFunctionSelector,
	uint256 rightPaddedGenericErrorSelector
) view returns (string memory str) {
	bool isBytes32;
	assembly {
		// Cache the free memory pointer to restore it after it is overwritten
		mstore(0, rightPaddedFunctionSelector)
		let status := staticcall(gas(), target, 0, 0x04, 0, 0)
		isBytes32 := eq(returndatasize(), 0x20)
		// If call fails or function returns invalid data, revert.
		// Strings are always right padded to full words - if the returndata
		// is not 32 bytes (string encoded as bytes32) or 96 bytes (abi encoded
		// string) it is either an invalid string or too large.
		if or(iszero(status), iszero(or(isBytes32, eq(returndatasize(), 0x60)))) {
			// Check if call failed
			if iszero(status) {
				// Check if any revert data was given
				if returndatasize() {
					returndatacopy(0, 0, returndatasize())
					revert(0, returndatasize())
				}
				// If not, throw a generic error
				mstore(0, rightPaddedGenericErrorSelector)
				revert(0, 0x04)
			}
			// If the returndata is the wrong size, throw InvalidReturnDataString
			mstore(0, InvalidReturnDataString_selector)
			revert(0, 0x04)
		}
	}
	if (isBytes32) {
		uint256 value;
		assembly {
			returndatacopy(0x00, 0x00, 0x20)
			value := mload(0)
		}
		uint256 size;
		unchecked {
			uint256 sizeInBits = 255 - Math.lowestBitSet(value);
			size = (sizeInBits + 7) / 8;
		}
		assembly {
			str := mload(0x40)
			mstore(0x40, add(str, 0x40))
			mstore(str, size)
			mstore(add(str, 0x20), value)
		}
	} else {
		// If returndata is a string, copy the length and value
		assembly {
			str := mload(0x40)
			// Get allocation size for the string including the length and data.
			// Rounding down returndatasize to nearest word because the returndata
			// has an extra offset word.
			let allocSize := and(sub(returndatasize(), 1), OnlyFullWordMask)
			mstore(0x40, add(str, allocSize))
			// Copy returndata after the offset
			returndatacopy(str, 0x20, sub(returndatasize(), 0x20))
		}
	}
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

type PRNG is uint256;
using LibPRNG for PRNG global;

function seedPRNG(uint256 seed) pure returns (PRNG prng) {
  assembly {
    prng := mload(0x40)
    mstore(prng, seed)
    mstore(0x40, add(prng, 0x20))
  }
}

library LibPRNG {
  function nextBytes(PRNG self, uint256 length) internal pure returns (bytes memory data) {
    assembly {
      data := mload(0x40)
      mstore(data, length)
      let pointer := add(data, 0x20)
      let i := 0
      for {

      } lt(i, length) {

      } {
        let result := keccak256(self, 0x20)
        mstore(self, result)
        mstore(add(pointer, i), result)
        i := add(i, 0x20)
      }
      let extraBytes := sub(i, length)
      calldatacopy(add(pointer, length), calldatasize(), extraBytes)
      mstore(0x40, add(pointer, i))
    }
  }
}

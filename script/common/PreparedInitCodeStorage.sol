// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @dev installs the reviewed runtime image. all splitting happens during preparation.
contract PreparedInitCodeStorage {
  constructor(bytes memory runtimeCode) {
    assembly ('memory-safe') {
      return(add(runtimeCode, 0x20), mload(runtimeCode))
    }
  }
}

/// @dev binds the already-deployed secondary into the prepared primary's footer.
///      the reader, payload and lengths are copied unchanged.
contract LinkedInitCodeStorage {
  constructor(bytes memory runtimeCode, address secondary) {
    require(runtimeCode.length >= 32 && secondary != address(0), 'Invalid split storage link');
    assembly ('memory-safe') {
      // the last word is eight payload bytes, the address, then both two-byte lengths.
      // write within that word so an aligned runtime doesn't clobber the next allocation.
      let lastWord := add(runtimeCode, mload(runtimeCode))
      let addressMask := shl(32, 0xffffffffffffffffffffffffffffffffffffffff)
      let word := mload(lastWord)
      if and(word, addressMask) {
        revert(0, 0)
      }
      mstore(lastWord, or(word, shl(32, and(secondary, 0xffffffffffffffffffffffffffffffffffffffff))))
      return(add(runtimeCode, 0x20), mload(runtimeCode))
    }
  }
}

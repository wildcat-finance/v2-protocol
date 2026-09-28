// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { LibZip } from 'solady/utils/LibZip.sol';

/// @notice optional single-contract storage for compressed creation code.
/// @dev the stored runtime decompresses and returns the original bytes on STATICCALL.
///      CompressedInitCodeReader is a runtime blueprint, not a second deployed contract.
library LibCompressedInitCode {
  error InitCodeDeploymentFailed();

  /// @dev keep the encoder shared by deployment and artifact verification.
  function getStorageRuntime(bytes memory initCode) internal pure returns (bytes memory runtime) {
    // creation itself is capped at 49,152 bytes, even if its compressed storage fits.
    if (initCode.length > 49_152) revert InitCodeDeploymentFailed();
    bytes memory compressed = LibZip.flzCompress(initCode);
    runtime = abi.encodePacked(
      type(CompressedInitCodeReader).runtimeCode,
      compressed,
      bytes2(uint16(compressed.length))
    );
    // the cap also keeps the length footer well inside uint16.
    if (runtime.length > 24_576) revert InitCodeDeploymentFailed();
  }

  function deployInitCode(bytes memory initCode) internal returns (address storageContract) {
    bytes memory runtime = getStorageRuntime(initCode);
    assembly ('memory-safe') {
      let size := mload(runtime)
      // PUSH2 size; PUSH0; DUP2; PUSH1 10; PUSH0; CODECOPY; RETURN.
      // unlike raw storage, the first runtime byte belongs to the reader, not STOP.
      mstore(runtime, or(shl(56, size), 0x6100005f81600a5f39f3))
      storageContract := create(0, add(runtime, 22), add(size, 10))
      mstore(runtime, size)
      if iszero(storageContract) {
        mstore(0, 0x11c8c3c0) // InitCodeDeploymentFailed()
        revert(0x1c, 4)
      }
    }
  }
}

/// @dev deployed only as the prefix of a single compressed storage contract. the encoder
///      appends a valid FastLZ stream and its two-byte length; there is no mutable storage.
contract CompressedInitCodeReader {
  fallback() external {
    bytes memory compressed;
    assembly ('memory-safe') {
      let size := codesize()
      codecopy(0, sub(size, 2), 2)
      let length := shr(240, mload(0))
      if gt(add(length, 2), size) {
        revert(0, 0)
      }
      compressed := mload(0x40)
      mstore(compressed, length)
      let data := add(compressed, 0x20)
      codecopy(data, sub(sub(size, 2), length), length)
      mstore(add(data, length), 0)
      mstore(0x40, add(add(data, length), 0x20))
    }
    bytes memory initCode = LibZip.flzDecompress(compressed);
    assembly ('memory-safe') {
      return(add(initCode, 0x20), mload(initCode))
    }
  }
}

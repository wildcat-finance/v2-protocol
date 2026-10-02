// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LibSplitInitCode
//  \ ^ /   Split creation-code storage and runtime reconstruction.
//    V
//
//  STORAGE DEPLOYMENT
//  deployInitCode(...)
//  _deployRuntime(...)
//
//  CHUNK ENCODING
//  getSecondaryRuntime(...)
//  getPrimaryRuntime(...)
//  _firstLength(...)
//  _slice(...)
//  firstChunkCapacity()
//  maximumInitCodeSize()
//
//  STORAGE QUERIES
//  getSecondaryAddress(...)
//
//  SPLIT READER
//  fallback()
// ═════

// ┌─ LibSplitInitCode ─────────────────────────────────────────────────────────
/// @notice two-contract storage for uncompressed creation code.
///
/// @dev the primary holds the reader and first chunk; the secondary is STOP plus the rest.
///      factories still receive one address and authenticate the reconstructed initcode hash.
library LibSplitInitCode {
  error InitCodeDeploymentFailed();

  uint256 internal constant FooterSize = 24;
  uint256 internal constant CodeSizeLimit = 24_576;

  // ░░▒▒▓▓██ [ STORAGE DEPLOYMENT ] ───────────────────────────────────────────

  // ┌─ deployInitCode ─────
  function deployInitCode(bytes memory initCode) internal returns (address primary, address secondary) {
    secondary = _deployRuntime(getSecondaryRuntime(initCode));
    primary = _deployRuntime(getPrimaryRuntime(initCode, secondary));
  }

  // ┌─ _deployRuntime ─────
  function _deployRuntime(bytes memory runtime) private returns (address deployed) {
    assembly ('memory-safe') {
      let size := mload(runtime)
      // PUSH2 size; PUSH0; DUP2; PUSH1 10; PUSH0; CODECOPY; RETURN.
      mstore(runtime, or(shl(56, size), 0x6100005f81600a5f39f3))
      deployed := create(0, add(runtime, 22), add(size, 10))
      mstore(runtime, size)
      if iszero(deployed) {
        mstore(0, 0x11c8c3c0) // InitCodeDeploymentFailed()
        revert(0x1c, 4)
      }
    }
  }

  // ░░▒▒▓▓██ [ CHUNK ENCODING ] ───────────────────────────────────────────────

  // ┌─ getSecondaryRuntime ─────
  function getSecondaryRuntime(bytes memory initCode) internal pure returns (bytes memory) {
    uint256 firstLength = _firstLength(initCode);
    return bytes.concat(hex'00', _slice(initCode, firstLength, initCode.length - firstLength));
  }

  // ┌─ getPrimaryRuntime ─────
  function getPrimaryRuntime(bytes memory initCode, address secondary) internal pure returns (bytes memory) {
    uint256 firstLength = _firstLength(initCode);
    return abi.encodePacked(
      type(SplitInitCodeReader).runtimeCode,
      _slice(initCode, 0, firstLength),
      bytes20(secondary),
      bytes2(uint16(firstLength)),
      bytes2(uint16(initCode.length - firstLength))
    );
  }

  // ┌─ _firstLength ─────
  function _firstLength(bytes memory initCode) private pure returns (uint256) {
    if (initCode.length > maximumInitCodeSize()) revert InitCodeDeploymentFailed();
    uint256 capacity = firstChunkCapacity();
    return initCode.length < capacity ? initCode.length : capacity;
  }

  // ┌─ _slice ─────
  function _slice(bytes memory original, uint256 offset, uint256 length) private pure returns (bytes memory result) {
    result = new bytes(length);
    assembly ('memory-safe') {
      mcopy(add(result, 0x20), add(add(original, 0x20), offset), length)
    }
  }

  // ┌─ firstChunkCapacity ─────
  function firstChunkCapacity() internal pure returns (uint256) {
    return CodeSizeLimit - type(SplitInitCodeReader).runtimeCode.length - FooterSize;
  }

  // ┌─ maximumInitCodeSize ─────
  function maximumInitCodeSize() internal pure returns (uint256) {
    return firstChunkCapacity() + CodeSizeLimit - 1;
  }

  // ░░▒▒▓▓██ [ STORAGE QUERIES ] ──────────────────────────────────────────────

  // ┌─ getSecondaryAddress ─────
  /// @dev read the link only. callers must still authenticate both complete runtimes.
  function getSecondaryAddress(address primary) internal view returns (address secondary) {
    uint256 size = primary.code.length;
    if (size < FooterSize || primary.code[0] == bytes1(0)) return address(0);
    assembly ('memory-safe') {
      extcodecopy(primary, 0, sub(size, 24), 20)
      secondary := shr(96, mload(0))
    }
  }
}

// ┌─ SplitInitCodeReader ──────────────────────────────────────────────────────
/// @dev runtime blueprint only; no third contract is deployed. the last 24 bytes are
///      secondary address (20), first-chunk length (2), and second-chunk length (2).
contract SplitInitCodeReader {
  // ░░▒▒▓▓██ [ SPLIT READER ] ─────────────────────────────────────────────────

  // ┌─ fallback ─────
  fallback() external {
    assembly ('memory-safe') {
      let size := codesize()
      if lt(size, 24) {
        revert(0, 0)
      }
      codecopy(0, sub(size, 24), 24)
      let footer := mload(0)
      let secondary := shr(96, footer)
      let firstLength := and(shr(80, footer), 0xffff)
      let secondLength := and(shr(64, footer), 0xffff)
      if or(gt(add(firstLength, 24), size), gt(add(firstLength, secondLength), 49152)) {
        revert(0, 0)
      }
      // EXTCODECOPY pads missing bytes with zero. require the exact secondary length first.
      if iszero(eq(extcodesize(secondary), add(secondLength, 1))) {
        revert(0, 0)
      }
      extcodecopy(secondary, 0, 0, 1)
      if byte(0, mload(0)) {
        revert(0, 0)
      }
      let output := mload(0x40)
      codecopy(output, sub(sub(size, 24), firstLength), firstLength)
      extcodecopy(secondary, add(output, firstLength), 1, secondLength)
      return(output, add(firstLength, secondLength))
    }
  }
}

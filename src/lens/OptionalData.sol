// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice distinguishes an unavailable getter from a real zero value.
struct OptionalUintDataV2_5 {
  bool isPresent;
  uint256 value;
}

/// @notice distinguishes an unavailable hash getter from its returned value.
struct OptionalBytes32Data {
  bool isPresent;
  bytes32 value;
}

/// @notice bounded return-data reads for optional lens fields.
library OptionalDataLib {
  function readWord(
    address target,
    bytes memory callData
  ) internal view returns (bool success, uint256 value) {
    assembly ('memory-safe') {
      // copy one word. a missing, reverting, or short getter is unavailable; extra words
      // don't belong to this field and don't need to be copied.
      let ptr := mload(0x40)
      success := staticcall(gas(), target, add(callData, 0x20), mload(callData), ptr, 0x20)
      success := and(success, iszero(lt(returndatasize(), 0x20)))
      if success {
        value := mload(ptr)
      }
    }
  }
}

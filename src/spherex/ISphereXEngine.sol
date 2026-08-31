// SPDX-License-Identifier: UNLICENSED
// (c) SphereX 2023 Terms&Conditions
pragma solidity 0.8.25;

/// @dev state carried between the pre- and post-validation halves of a protected call.
struct ModifierLocals {
  bytes32[] storageSlots;
  bytes32[] valuesBefore;
  uint256 gas;
  address engine;
}

/// @title SphereX engine interface
/// @author SphereX Technologies ltd
/// @notice validation surface called by SphereX-protected contracts around external and internal
///         work.
/// @dev complete rule semantics live in the configured engine implementation.
interface ISphereXEngine {
  /// @notice starts validation for an external call and returns storage slots to snapshot.
  function sphereXValidatePre(
    int256 num,
    address sender,
    bytes calldata data
  ) external returns (bytes32[] memory);

  /// @notice completes validation for an external call using before and after storage values.
  function sphereXValidatePost(
    int256 num,
    uint256 gas,
    bytes32[] calldata valuesBefore,
    bytes32[] calldata valuesAfter
  ) external;

  /// @notice starts validation for an engine-identified internal call.
  function sphereXValidateInternalPre(int256 num) external returns (bytes32[] memory);

  /// @notice completes validation for an engine-identified internal call.
  function sphereXValidateInternalPost(
    int256 num,
    uint256 gas,
    bytes32[] calldata valuesBefore,
    bytes32[] calldata valuesAfter
  ) external;

  /// @notice allows a protected contract to send validation calls to the engine.
  function addAllowedSenderOnChain(address sender) external;

  /// @notice returns whether the engine implements `interfaceId` under ERC-165.
  /// @dev copied into this interface instead of importing OpenZeppelin to avoid version collisions.
  ///      the call must use less than 30,000 gas. see
  ///      https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified.
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

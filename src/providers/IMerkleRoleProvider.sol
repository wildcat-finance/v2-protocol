// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';
import '../access/IManagedRoleProvider.sol';

/// @notice proof-based provider for a mutable Merkle root of address membership.
/// @dev leaves are `keccak256(abi.encode(account))` and proofs use sorted pairs. this is not a pull
///      provider because credential checks need a caller-supplied proof.
interface IMerkleRoleProvider is IRoleProvider, IManagedRoleProvider {
  /// @notice emitted when the administrator replaces the membership root.
  event RootUpdated(
    address indexed administrator,
    bytes32 previousRoot,
    bytes32 newRoot
  );

  /// @notice current address-membership root.
  function root() external view returns (bytes32);

  /// @notice replaces the root without changing provider address or hook attachments.
  function updateRoot(bytes32 newRoot) external;

  /// @notice verifies `account` against the current root with a sorted-pair proof.
  function isMember(address account, bytes32[] calldata proof) external view returns (bool);
}

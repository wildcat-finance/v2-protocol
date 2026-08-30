// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';
import '../access/IManagedRoleProvider.sol';

/// @notice enumerable pull provider backed by one administrator-managed address set.
/// @dev the same provider can be attached to several hooks. membership belongs here; each hook
///      independently decides its TTL and whether to trust this provider.
interface IAccessListRoleProvider is IRoleProvider, IManagedRoleProvider {
  /// @notice emitted when the administrator adds a member.
  event MemberAdded(address indexed administrator, address indexed account);
  /// @notice emitted when the administrator removes a member.
  event MemberRemoved(address indexed administrator, address indexed account);

  /// @dev the requested member is the zero address.
  error InvalidMember();
  /// @dev the requested account is already a member.
  error MemberAlreadyExists();
  /// @dev the requested account is not a member.
  error MemberNotFound();
  /// @dev the requested pagination start exceeds the requested end.
  error InvalidPaginationRange();

  /// @notice says whether `account` is in the current set.
  function isMember(address account) external view returns (bool);

  /// @notice adds one nonzero account; reverts if it is already a member.
  function addMember(address account) external;

  /// @notice adds every account atomically; one invalid or duplicate entry reverts the batch.
  function addMembers(address[] calldata accounts) external;

  /// @notice removes one account; reverts if it is not a member.
  function removeMember(address account) external;

  /// @notice removes every account atomically; one missing entry reverts the batch.
  function removeMembers(address[] calldata accounts) external;

  /// @notice returns every current member in unstable enumeration order.
  function getMembers() external view returns (address[] memory);

  /// @notice returns members in the half-open range `[start, end)`.
  /// @dev `end` is clamped to the current count. `start > end` reverts; an empty range returns an
  ///      empty array. enumeration order is not stable across removals.
  function getMembers(uint256 start, uint256 end) external view returns (address[] memory);

  /// @notice returns the current number of members.
  function getMembersCount() external view returns (uint256);
}

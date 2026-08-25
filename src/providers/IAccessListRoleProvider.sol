// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../access/IRoleProvider.sol';
import '../access/IManagedRoleProvider.sol';

interface IAccessListRoleProvider is IRoleProvider, IManagedRoleProvider {
  event MemberAdded(address indexed administrator, address indexed account);
  event MemberRemoved(address indexed administrator, address indexed account);

  error InvalidMember();
  error MemberAlreadyExists();
  error MemberNotFound();
  error InvalidPaginationRange();

  function isMember(address account) external view returns (bool);

  function addMember(address account) external;

  function addMembers(address[] calldata accounts) external;

  function removeMember(address account) external;

  function removeMembers(address[] calldata accounts) external;

  function getMembers() external view returns (address[] memory);

  function getMembers(uint256 start, uint256 end) external view returns (address[] memory);

  function getMembersCount() external view returns (uint256);
}

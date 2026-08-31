// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../libraries/SafeCastLib.sol';
import './IAccessListRoleProvider.sol';
import './ManagedRoleProvider.sol';

using SafeCastLib for uint256;

/// @notice pull provider backed by one enumerable address set.
/// @dev membership and provider administration live here. each attached hook independently
///      decides whether to trust this provider and how long a positive answer survives removal
///      from the set.
contract AccessListRoleProvider is IAccessListRoleProvider, ManagedRoleProvider {
  using EnumerableSet for EnumerableSet.AddressSet;

  bool public constant override isPullProvider = true;

  EnumerableSet.AddressSet internal _members;

  /// @param administrator_ initial authority over membership and provider administration.
  /// @param initialMembers initial nonzero members. a duplicate reverts deployment.
  constructor(
    address administrator_,
    address[] memory initialMembers
  ) ManagedRoleProvider(administrator_) {
    _addMembers(initialMembers);
  }

  // ========================================================================== //
  //                              Member updates                                //
  // ========================================================================== //

  function addMember(address account) external override onlyAdministrator {
    _addMember(account);
  }

  function addMembers(address[] calldata accounts) external override onlyAdministrator {
    for (uint256 i; i < accounts.length; i++) {
      _addMember(accounts[i]);
    }
  }

  function _addMembers(address[] memory accounts) internal {
    for (uint256 i; i < accounts.length; i++) {
      _addMember(accounts[i]);
    }
  }

  function _addMember(address account) internal {
    if (account == address(0)) revert InvalidMember();
    if (!_members.add(account)) revert MemberAlreadyExists();
    emit MemberAdded(administrator, account);
  }

  function removeMember(address account) external override onlyAdministrator {
    _removeMember(account);
  }

  function removeMembers(address[] calldata accounts) external override onlyAdministrator {
    for (uint256 i; i < accounts.length; i++) {
      _removeMember(accounts[i]);
    }
  }

  function _removeMember(address account) internal {
    if (!_members.remove(account)) revert MemberNotFound();
    emit MemberRemoved(administrator, account);
  }

  // ========================================================================== //
  //                              Member queries                                //
  // ========================================================================== //

  function isMember(address account) external view override returns (bool) {
    return _members.contains(account);
  }

  function getMembers() external view override returns (address[] memory) {
    return _members.values();
  }

  function getMembers(
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory members) {
    if (start > end) revert InvalidPaginationRange();
    uint256 length = _members.length();
    if (end > length) end = length;
    if (start >= end) return new address[](0);

    members = new address[](end - start);
    for (uint256 i; i < members.length; i++) {
      members[i] = _members.at(start + i);
    }
  }

  function getMembersCount() external view override returns (uint256) {
    return _members.length();
  }

  // ========================================================================== //
  //                            Credential queries                              //
  // ========================================================================== //

  /// @dev returns the current timestamp for a member and zero for everyone else.
  function getCredential(
    address account
  ) external view override returns (uint32 credentialTimestamp) {
    if (_members.contains(account)) credentialTimestamp = block.timestamp.toUint32();
  }

  /// @dev membership needs no caller-supplied data, so this answers the same query as
  ///      `getCredential` and ignores the payload.
  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 credentialTimestamp) {
    if (_members.contains(account)) credentialTimestamp = block.timestamp.toUint32();
  }
}

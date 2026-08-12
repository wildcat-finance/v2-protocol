// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../libraries/SafeCastLib.sol';
import './IAccessListRoleProvider.sol';

using SafeCastLib for uint256;

/**
 * @dev Pull-based role provider for one reusable address list. The provider owns
 *      membership. Hooks decide whether to trust it and how long to cache its answers.
 */
contract AccessListRoleProvider is IAccessListRoleProvider {
  using EnumerableSet for EnumerableSet.AddressSet;

  bool public constant override isPullProvider = true;

  address public override administrator;
  address public override pendingAdministrator;

  EnumerableSet.AddressSet internal _members;

  modifier onlyAdministrator() {
    if (msg.sender != administrator) revert CallerNotAdministrator();
    _;
  }

  constructor(address administrator_, address[] memory initialMembers) {
    if (administrator_ == address(0)) revert InvalidAdministratorTransferTarget();
    administrator = administrator_;
    _addMembers(initialMembers);
  }

  // ========================================================================== //
  //                         Administrator transfer                             //
  // ========================================================================== //

  function requestAdministratorTransfer(
    address newAdministrator
  ) external override onlyAdministrator {
    if (newAdministrator == address(0) || newAdministrator == administrator) {
      revert InvalidAdministratorTransferTarget();
    }
    address previousPendingAdministrator = pendingAdministrator;
    pendingAdministrator = newAdministrator;
    emit AdministratorTransferRequested(
      msg.sender,
      previousPendingAdministrator,
      newAdministrator
    );
  }

  function cancelAdministratorTransfer() external override onlyAdministrator {
    address cancelledPendingAdministrator = pendingAdministrator;
    if (cancelledPendingAdministrator == address(0)) {
      revert NoPendingAdministratorTransfer();
    }
    pendingAdministrator = address(0);
    emit AdministratorTransferCancelled(msg.sender, cancelledPendingAdministrator);
  }

  function acceptAdministratorTransfer() external override {
    address newAdministrator = pendingAdministrator;
    if (msg.sender != newAdministrator) revert NotPendingAdministrator();

    address previousAdministrator = administrator;
    pendingAdministrator = address(0);
    administrator = newAdministrator;
    emit AdministratorTransferred(previousAdministrator, newAdministrator);
  }

  // ========================================================================== //
  //                              Member updates                                //
  // ========================================================================== //

  function addMember(address account) external override onlyAdministrator {
    _addMember(account);
  }

  function addMembers(address[] calldata accounts) external override onlyAdministrator {
    _addMembers(accounts);
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

  function getCredential(
    address account
  ) external view override returns (uint32 credentialTimestamp) {
    if (_members.contains(account)) credentialTimestamp = block.timestamp.toUint32();
  }

  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 credentialTimestamp) {
    if (_members.contains(account)) credentialTimestamp = block.timestamp.toUint32();
  }
}

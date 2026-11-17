// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProvider
//  \ ^ /   Shared wallet enrollment for v2.0, v2.1, and v2.5 hooks.
//    V
//
//  SETUP
//  constructor(...)
//
//  MEMBERSHIP
//  isMember(...)
//  addMember(...)
//  addMembers(...)
//  _addMember(...)
//  removeMember(...)
//  removeMembers(...)
//  _removeMember(...)
//
//  CREDENTIALS
//  getCredential(...)
//  validateCredential(...)
// ═════

import { IRoleProvider } from '../access/IRoleProvider.sol';
import { SafeCastLib } from '../libraries/SafeCastLib.sol';
import { ManagedRoleProvider } from './ManagedRoleProvider.sol';

// ┌─ KYCRoleProvider ──────────────────────────────────────────────────────────
/// @notice provide KYC credentials from one shared list of approved wallets.
///
/// @dev only the provider administrator can edit the list. each hooks instance decides whether to trust it.
contract KYCRoleProvider is IRoleProvider, ManagedRoleProvider {
  using SafeCastLib for uint256;

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev enrollment requires a nonzero wallet address.
  error InvalidMember();
  error MemberAlreadyExists();
  error MemberNotFound();

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  event MemberAdded(address indexed administrator, address indexed account);
  event MemberRemoved(address indexed administrator, address indexed account);

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  bool public constant override isPullProvider = true;

  /// @notice return the block timestamp of the wallet's current enrollment, or zero if unlisted.
  mapping(address account => uint256 timestamp) public addedAt;

  // ┌─ constructor ─────
  /// @param administrator_ initial nonzero address with authority over the list.
  constructor(address administrator_) ManagedRoleProvider(administrator_) { }

  // ░░▒▒▓▓██ [ MEMBERSHIP ] ───────────────────────────────────────────────────

  // ┌─ isMember ─────
  /// @notice report whether the wallet is currently enrolled.
  function isMember(address account) public view returns (bool) {
    return addedAt[account] != 0;
  }

  // ┌─ addMember ─────
  /// @notice enroll a nonzero wallet at the current block timestamp. a duplicate reverts.
  function addMember(address account) external onlyAdministrator {
    _addMember(account);
  }

  // ┌─ addMembers ─────
  /// @notice enroll every wallet in the batch. a zero address, existing member, or repeated entry reverts the call.
  function addMembers(address[] calldata accounts) external onlyAdministrator {
    for (uint256 i; i < accounts.length; ++i) {
      _addMember(accounts[i]);
    }
  }

  // ┌─ _addMember ─────
  function _addMember(address account) internal {
    if (account == address(0)) revert InvalidMember();
    if (isMember(account)) revert MemberAlreadyExists();

    addedAt[account] = block.timestamp;
    emit MemberAdded(msg.sender, account);
  }

  // ┌─ removeMember ─────
  /// @notice clear the wallet's enrollment. removing an unlisted wallet reverts.
  ///
  /// @dev fresh lookups return zero immediately. a hook can still honor a cached approval through its expiry timestamp.
  function removeMember(address account) external onlyAdministrator {
    _removeMember(account);
  }

  // ┌─ removeMembers ─────
  /// @notice remove every wallet in the batch. an unlisted wallet or a repeated entry reverts the whole batch.
  function removeMembers(address[] calldata accounts) external onlyAdministrator {
    for (uint256 i; i < accounts.length; ++i) {
      _removeMember(accounts[i]);
    }
  }

  // ┌─ _removeMember ─────
  function _removeMember(address account) internal {
    if (!isMember(account)) revert MemberNotFound();

    delete addedAt[account];
    emit MemberRemoved(msg.sender, account);
  }

  // ░░▒▒▓▓██ [ CREDENTIALS ] ──────────────────────────────────────────────────

  // ┌─ getCredential ─────
  /// @notice return the current block timestamp for a member, or zero for an unlisted wallet.
  ///
  /// @dev the hook measures its TTL from this lookup. `addedAt` records when the wallet enrolled.
  ///      a member lookup reverts if the block timestamp exceeds `type(uint32).max`.
  function getCredential(address account) public view override returns (uint32) {
    return isMember(account) ? block.timestamp.toUint32() : 0;
  }

  // ┌─ validateCredential ─────
  /// @dev the result matches `getCredential(account)` for any payload, including empty bytes.
  function validateCredential(address account, bytes calldata) external view override returns (uint32) {
    return getCredential(account);
  }
}

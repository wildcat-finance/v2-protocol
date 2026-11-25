// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRegistry
//  \ ^ /   Lender registration and keeper-synced KYC attribute cache.
//    V
//
//  SETUP
//  constructor(...)
//
//  KEEPERS
//  onlyKeeper()
//  onlyKeeperOrAdministrator()
//  setKeeper(...)
//  _setKeeper(...)
//
//  REGISTRATION
//  register()
//  pruneUnverifiedLenders(...)
//
//  ATTRIBUTES
//  setAttribute(...)
//  setAttributes(...)
//  _setAttribute(...)
//  removeAttribute(...)
//  removeAttributes(...)
//  _removeAttribute(...)
//  updateAttributes(...)
//
//  QUERIES
//  isRegistered(...)
//  getRegisteredLendersCount()
//  getRegisteredLenders(...)
//  getAttribute(...)
//  hasAttribute(...)
//  hasActiveAttribute(...)
//  meetsAttributes(...)
//  getLenderAttributeIds(...)
//  getLenderAttributes(...)
// ═════

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { SafeCastLib } from '../libraries/SafeCastLib.sol';
import { IKYCRegistry, KYCAttribute, KYCAttributeInput, KYCAttributeRemoval } from './IKYCRegistry.sol';
import { ManagedRoleProvider } from './ManagedRoleProvider.sol';

// ┌─ KYCRegistry ──────────────────────────────────────────────────────────────
/// @notice Wildcat-owned registry of enrolled lenders and their cached KYC attributes.
///
/// @dev makes no external calls; offchain keepers sync upstream KYC data here.
///      `hasActiveAttribute` enforces `expiresAt` (`issuedAt` is presence metadata, not an
///      activation gate), while `hasAttribute` ignores expiry so disqualifiers stay blocking
///      until a keeper removes them.
contract KYCRegistry is IKYCRegistry, ManagedRoleProvider {
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using SafeCastLib for uint256;

  mapping(address keeper => bool allowed) public override isKeeper;

  EnumerableSet.AddressSet internal _registeredLenders;

  mapping(address account => EnumerableSet.Bytes32Set) internal _lenderAttributeIds;
  mapping(address account => mapping(bytes32 attributeId => KYCAttribute)) internal _attributes;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param administrator_ initial nonzero authority over keeper management and admin transfers.
  /// @param initialKeepers initial nonzero keeper addresses authorized to sync attributes.
  constructor(address administrator_, address[] memory initialKeepers) ManagedRoleProvider(administrator_) {
    for (uint256 i; i < initialKeepers.length; ++i) {
      _setKeeper(initialKeepers[i], true);
    }
  }

  // ░░▒▒▓▓██ [ KEEPERS ] ──────────────────────────────────────────────────────

  // ┌─ onlyKeeper ─────
  modifier onlyKeeper() {
    if (!isKeeper[msg.sender]) revert CallerNotKeeper();
    _;
  }

  // ┌─ onlyKeeperOrAdministrator ─────
  modifier onlyKeeperOrAdministrator() {
    if (!isKeeper[msg.sender] && msg.sender != administrator) revert CallerNotKeeperOrAdministrator();
    _;
  }

  // ┌─ setKeeper ─────
  /// @notice grant or revoke keeper authority over lender attribute writes.
  function setKeeper(address keeper, bool allowed) external override onlyAdministrator {
    _setKeeper(keeper, allowed);
  }

  // ┌─ _setKeeper ─────
  function _setKeeper(address keeper, bool allowed) internal {
    if (keeper == address(0)) revert InvalidKeeper();
    isKeeper[keeper] = allowed;
    emit KeeperUpdated(administrator, keeper, allowed);
  }

  // ░░▒▒▓▓██ [ REGISTRATION ] ─────────────────────────────────────────────────

  // ┌─ register ─────
  /// @notice opt `msg.sender` into Wildcat's keeper sync set with no attributes.
  ///
  /// @dev reverts if `msg.sender` is already registered. only keepers can write attributes.
  function register() external override {
    if (!_registeredLenders.add(msg.sender)) revert AlreadyRegistered();
    emit LenderRegistered(msg.sender);
  }

  // ┌─ pruneUnverifiedLenders ─────
  /// @notice remove registered wallets that still hold zero attributes.
  ///
  /// @dev cleans out empty registrations without touching verified wallets.
  function pruneUnverifiedLenders(address[] calldata accounts) external override onlyKeeperOrAdministrator {
    for (uint256 i; i < accounts.length; ++i) {
      address account = accounts[i];
      if (!_registeredLenders.contains(account)) revert LenderNotRegistered();
      if (_lenderAttributeIds[account].length() != 0) revert LenderHasAttributes();

      _registeredLenders.remove(account);
      emit LenderRemoved(msg.sender, account);
    }
  }

  // ░░▒▒▓▓██ [ ATTRIBUTES ] ───────────────────────────────────────────────────

  // ┌─ setAttribute ─────
  /// @notice write or refresh one lender attribute, auto-registering the wallet if absent.
  function setAttribute(KYCAttributeInput calldata input) external override onlyKeeper {
    _setAttribute(input);
  }

  // ┌─ setAttributes ─────
  /// @notice write or refresh a batch of lender attributes atomically.
  function setAttributes(KYCAttributeInput[] calldata inputs) external override onlyKeeper {
    for (uint256 i; i < inputs.length; ++i) {
      _setAttribute(inputs[i]);
    }
  }

  // ┌─ _setAttribute ─────
  function _setAttribute(KYCAttributeInput calldata input) internal {
    if (input.account == address(0)) revert InvalidAccount();
    if (input.attributeId == bytes32(0)) revert InvalidAttributeId();

    // `issuedAt` doubles as the presence sentinel for both active and fail-closed checks.
    if (input.issuedAt == 0 || (input.expiresAt != 0 && input.expiresAt < input.issuedAt)) {
      revert InvalidTimestamps();
    }

    if (_registeredLenders.add(input.account)) {
      emit LenderRegistered(input.account);
    }

    _lenderAttributeIds[input.account].add(input.attributeId);
    _attributes[input.account][input.attributeId] = KYCAttribute({
      issuedAt: input.issuedAt,
      expiresAt: input.expiresAt,
      updatedAt: block.timestamp.toUint40(),
      sourceId: input.sourceId
    });
    emit AttributeSet(msg.sender, input.account, input.attributeId, input.issuedAt, input.expiresAt, input.sourceId);
  }

  // ┌─ removeAttribute ─────
  /// @notice delete one attribute from `account`. reverts if it isn't set.
  function removeAttribute(address account, bytes32 attributeId) external override onlyKeeper {
    _removeAttribute(account, attributeId);
  }

  // ┌─ removeAttributes ─────
  /// @notice delete a batch of lender attributes atomically.
  function removeAttributes(KYCAttributeRemoval[] calldata removals) external override onlyKeeper {
    for (uint256 i; i < removals.length; ++i) {
      _removeAttribute(removals[i].account, removals[i].attributeId);
    }
  }

  // ┌─ _removeAttribute ─────
  function _removeAttribute(address account, bytes32 attributeId) internal {
    if (!_lenderAttributeIds[account].remove(attributeId)) revert AttributeNotFound();
    delete _attributes[account][attributeId];
    emit AttributeRemoved(msg.sender, account, attributeId);
  }

  // ┌─ updateAttributes ─────
  /// @notice apply removals and writes atomically in one transaction.
  ///
  /// @dev runs removals before sets so a replaced key ends up set.
  function updateAttributes(
    KYCAttributeInput[] calldata sets,
    KYCAttributeRemoval[] calldata removals
  )
    external
    override
    onlyKeeper
  {
    for (uint256 i; i < removals.length; ++i) {
      _removeAttribute(removals[i].account, removals[i].attributeId);
    }
    for (uint256 i; i < sets.length; ++i) {
      _setAttribute(sets[i]);
    }
  }

  // ░░▒▒▓▓██ [ QUERIES ] ──────────────────────────────────────────────────────

  // ┌─ isRegistered ─────
  function isRegistered(address account) external view override returns (bool) {
    return _registeredLenders.contains(account);
  }

  // ┌─ getRegisteredLendersCount ─────
  function getRegisteredLendersCount() external view override returns (uint256) {
    return _registeredLenders.length();
  }

  // ┌─ getRegisteredLenders ─────
  function getRegisteredLenders(uint256 start, uint256 end) external view override returns (address[] memory lenders) {
    if (start > end) revert InvalidPaginationRange();
    uint256 total = _registeredLenders.length();
    if (end > total) end = total;
    if (start >= end) return new address[](0);

    lenders = new address[](end - start);
    for (uint256 i; i < lenders.length; ++i) {
      lenders[i] = _registeredLenders.at(start + i);
    }
  }

  // ┌─ getAttribute ─────
  function getAttribute(address account, bytes32 attributeId) external view override returns (KYCAttribute memory) {
    return _attributes[account][attributeId];
  }

  // ┌─ hasAttribute ─────
  /// @dev ignores `expiresAt` so negative checks fail closed until a keeper removes the key.
  function hasAttribute(address account, bytes32 attributeId) external view override returns (bool) {
    return _attributes[account][attributeId].issuedAt != 0;
  }

  // ┌─ hasActiveAttribute ─────
  /// @dev `issuedAt` is presence metadata only; `expiresAt` is the only time gate.
  function hasActiveAttribute(address account, bytes32 attributeId) public view override returns (bool) {
    KYCAttribute memory attr = _attributes[account][attributeId];
    return attr.issuedAt != 0 && (attr.expiresAt == 0 || block.timestamp <= attr.expiresAt);
  }

  // ┌─ meetsAttributes ─────
  function meetsAttributes(
    address account,
    bytes32[] calldata required,
    bytes32[] calldata forbidden
  )
    external
    view
    override
    returns (bool)
  {
    mapping(bytes32 => KYCAttribute) storage attrs = _attributes[account];

    for (uint256 i; i < required.length; ++i) {
      KYCAttribute memory attr = attrs[required[i]];
      if (attr.issuedAt == 0 || (attr.expiresAt != 0 && block.timestamp > attr.expiresAt)) return false;
    }

    for (uint256 i; i < forbidden.length; ++i) {
      if (attrs[forbidden[i]].issuedAt != 0) return false;
    }

    return true;
  }

  // ┌─ getLenderAttributeIds ─────
  function getLenderAttributeIds(address account) external view override returns (bytes32[] memory) {
    return _lenderAttributeIds[account].values();
  }

  // ┌─ getLenderAttributes ─────
  function getLenderAttributes(address account)
    external
    view
    override
    returns (bytes32[] memory attributeIds, KYCAttribute[] memory records)
  {
    attributeIds = _lenderAttributeIds[account].values();
    uint256 count = attributeIds.length;
    records = new KYCAttribute[](count);
    for (uint256 i; i < count; ++i) {
      records[i] = _attributes[account][attributeIds[i]];
    }
  }
}

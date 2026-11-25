// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IKYCRegistry
//  \ ^ /   Lender registration and keeper-synced KYC attribute cache.
//    V
//
//  KEEPERS
//  isKeeper(...)
//  setKeeper(...)
//
//  REGISTRATION
//  register()
//  pruneUnverifiedLenders(...)
//
//  ATTRIBUTES
//  setAttribute(...)
//  setAttributes(...)
//  removeAttribute(...)
//  removeAttributes(...)
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

import '../access/IManagedRoleProvider.sol';

/// @notice cached attribute metadata for a lender, packed into 16 bytes.
///
/// @param issuedAt  nonzero presence and issuance timestamp; doesn't gate future activation on read.
/// @param expiresAt inclusive expiry timestamp, or zero if it doesn't expire.
/// @param updatedAt block timestamp of the last keeper write.
/// @param sourceId  provenance tag for the attribute source (e.g. Wildcat, Soma).
struct KYCAttribute {
  uint40 issuedAt;
  uint40 expiresAt;
  uint40 updatedAt;
  uint8 sourceId;
}

/// @notice input tuple for writing one lender attribute.
struct KYCAttributeInput {
  address account;
  bytes32 attributeId;
  uint40 issuedAt;
  uint40 expiresAt;
  uint8 sourceId;
}

/// @notice input tuple for removing one lender attribute.
struct KYCAttributeRemoval {
  address account;
  bytes32 attributeId;
}

// ┌─ IKYCRegistry ─────────────────────────────────────────────────────────────
/// @notice Wildcat-owned lender registry and attribute cache, decoupled from upstream KYC providers.
///
/// @dev lenders can opt in via `register`, or keepers auto-register them on the first write.
///      positive checks use `hasActiveAttribute`; negative checks use `hasAttribute` so
///      disqualifying flags don't expire into allowed.
interface IKYCRegistry is IManagedRoleProvider {
  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when the administrator grants or revokes keeper authority.
  event KeeperUpdated(address indexed administrator, address indexed keeper, bool allowed);

  /// @notice emitted when a wallet enters the registered lender set.
  event LenderRegistered(address indexed account);

  /// @notice emitted when an unverified wallet is pruned from the registered lender set.
  event LenderRemoved(address indexed caller, address indexed account);

  /// @notice emitted when a keeper writes or refreshes a lender attribute.
  event AttributeSet(
    address indexed keeper,
    address indexed account,
    bytes32 indexed attributeId,
    uint40 issuedAt,
    uint40 expiresAt,
    uint8 sourceId
  );

  /// @notice emitted when a keeper deletes a lender attribute.
  event AttributeRemoved(address indexed keeper, address indexed account, bytes32 indexed attributeId);

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev caller isn't an authorized keeper.
  error CallerNotKeeper();

  /// @dev caller is neither an authorized keeper nor the registry administrator.
  error CallerNotKeeperOrAdministrator();

  /// @dev lender account can't be zero.
  error InvalidAccount();

  /// @dev attribute key can't be zero.
  error InvalidAttributeId();

  /// @dev keeper address can't be zero.
  error InvalidKeeper();

  /// @dev `issuedAt` must be nonzero, and a nonzero `expiresAt` can't precede `issuedAt`.
  error InvalidTimestamps();

  /// @dev wallet is already in the registered lender set.
  error AlreadyRegistered();

  /// @dev wallet isn't in the registered lender set.
  error LenderNotRegistered();

  /// @dev can't prune a wallet that still holds attributes.
  error LenderHasAttributes();

  /// @dev wallet doesn't hold that attribute.
  error AttributeNotFound();

  /// @dev pagination `start` exceeds `end`.
  error InvalidPaginationRange();

  // ░░▒▒▓▓██ [ KEEPERS ] ──────────────────────────────────────────────────────

  // ┌─ isKeeper ─────
  /// @notice report whether `keeper` can write and remove lender attributes.
  function isKeeper(address keeper) external view returns (bool);

  // ┌─ setKeeper ─────
  /// @notice grant or revoke keeper authority over attribute updates.
  function setKeeper(address keeper, bool allowed) external;

  // ░░▒▒▓▓██ [ REGISTRATION ] ─────────────────────────────────────────────────

  // ┌─ register ─────
  /// @notice enroll `msg.sender` into the registered lender set with no attributes.
  function register() external;

  // ┌─ pruneUnverifiedLenders ─────
  /// @notice remove registered wallets that hold zero attributes.
  ///
  /// @dev atomic batch: any unregistered wallet or wallet with attributes reverts the call.
  function pruneUnverifiedLenders(address[] calldata accounts) external;

  // ░░▒▒▓▓██ [ ATTRIBUTES ] ───────────────────────────────────────────────────

  // ┌─ setAttribute ─────
  /// @notice write or refresh one lender attribute, auto-registering the wallet if needed.
  function setAttribute(KYCAttributeInput calldata input) external;

  // ┌─ setAttributes ─────
  /// @notice write or refresh a batch of lender attributes atomically.
  function setAttributes(KYCAttributeInput[] calldata inputs) external;

  // ┌─ removeAttribute ─────
  /// @notice delete one attribute from a wallet.
  function removeAttribute(address account, bytes32 attributeId) external;

  // ┌─ removeAttributes ─────
  /// @notice delete a batch of lender attributes atomically.
  function removeAttributes(KYCAttributeRemoval[] calldata removals) external;

  // ┌─ updateAttributes ─────
  /// @notice apply attribute removals and writes atomically in one keeper transaction.
  ///
  /// @dev runs `removals` before `sets` so a replaced key ends up set.
  function updateAttributes(KYCAttributeInput[] calldata sets, KYCAttributeRemoval[] calldata removals) external;

  // ░░▒▒▓▓██ [ QUERIES ] ──────────────────────────────────────────────────────

  // ┌─ isRegistered ─────
  /// @notice report whether `account` is in the registered lender set.
  function isRegistered(address account) external view returns (bool);

  // ┌─ getRegisteredLendersCount ─────
  /// @notice count wallets in the registered lender set.
  function getRegisteredLendersCount() external view returns (uint256);

  // ┌─ getRegisteredLenders ─────
  /// @notice return a half-open `[start, end)` page of registered lenders.
  ///
  /// @dev clamps `end` to the set length. ordering shifts when wallets are pruned.
  function getRegisteredLenders(uint256 start, uint256 end) external view returns (address[] memory lenders);

  // ┌─ getAttribute ─────
  /// @notice return the stored metadata for `(account, attributeId)`, or all zeros if absent.
  function getAttribute(address account, bytes32 attributeId) external view returns (KYCAttribute memory);

  // ┌─ hasAttribute ─────
  /// @notice report whether `attributeId` is present on `account`, ignoring `expiresAt`.
  ///
  /// @dev used for fail-closed negative checks; disqualifiers stay blocking until removed.
  function hasAttribute(address account, bytes32 attributeId) external view returns (bool);

  // ┌─ hasActiveAttribute ─────
  /// @notice report whether `attributeId` is present on `account` and unexpired at `block.timestamp`.
  function hasActiveAttribute(address account, bytes32 attributeId) external view returns (bool);

  // ┌─ meetsAttributes ─────
  /// @notice report whether `account` holds every active key in `required` and none in `forbidden`.
  ///
  /// @dev evaluates both lists in one call so providers don't loop external calls per attribute.
  function meetsAttributes(
    address account,
    bytes32[] calldata required,
    bytes32[] calldata forbidden
  )
    external
    view
    returns (bool);

  // ┌─ getLenderAttributeIds ─────
  /// @notice return all attribute keys currently stored for `account`.
  function getLenderAttributeIds(address account) external view returns (bytes32[] memory);

  // ┌─ getLenderAttributes ─────
  /// @notice return all attribute keys and matching metadata records stored for `account`.
  function getLenderAttributes(address account)
    external
    view
    returns (bytes32[] memory attributeIds, KYCAttribute[] memory records);
}

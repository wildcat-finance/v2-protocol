// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProvider
//  \ ^ /   Immutable, attribute-backed KYC policy provider for v2.x hooks.
//    V
//
//  SETUP
//  constructor(...)
//
//  POLICY
//  requiredAttributes()
//  forbiddenAttributes()
//  meetsPolicy(...)
//
//  CREDENTIALS
//  getCredential(...)
//  validateCredential(...)
// ═════

import { SafeCastLib } from '../libraries/SafeCastLib.sol';
import { IKYCRegistry } from './IKYCRegistry.sol';
import { IKYCRoleProvider } from './IKYCRoleProvider.sol';
import { IKYCRoleProviderFactory } from './IKYCRoleProviderFactory.sol';

// ┌─ KYCRoleProvider ──────────────────────────────────────────────────────────
/// @notice immutable, ownerless KYC policy provider shared across authorized Wildcat hooks.
///
/// @dev checks `requiredAttributes` (present and unexpired) and `forbiddenAttributes` (absent,
///      ignoring expiry) against `registry`, and gates credentials on
///      `factory.isHooksAuthorized(msg.sender)`.
contract KYCRoleProvider is IKYCRoleProvider {
  using SafeCastLib for uint256;

  bool public constant override isPullProvider = true;

  IKYCRegistry public immutable override registry;
  IKYCRoleProviderFactory public immutable override factory;

  string public override name;

  bytes32[] internal _requiredAttributes;
  bytes32[] internal _forbiddenAttributes;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param registry_            shared `KYCRegistry` holding cached lender attributes.
  /// @param factory_             entitlement factory gating authorized calling hooks instances.
  /// @param name_                human-readable policy label.
  /// @param requiredAttributes_  attributes that must all be present and unexpired.
  /// @param forbiddenAttributes_ attributes that must all be absent regardless of expiry.
  constructor(
    IKYCRegistry registry_,
    IKYCRoleProviderFactory factory_,
    string memory name_,
    bytes32[] memory requiredAttributes_,
    bytes32[] memory forbiddenAttributes_
  ) {
    if (address(registry_) == address(0)) revert InvalidRegistry();
    if (address(factory_) == address(0)) revert InvalidFactory();
    if (requiredAttributes_.length == 0) revert EmptyRequiredAttributes();

    registry = registry_;
    factory = factory_;
    name = name_;
    _requiredAttributes = requiredAttributes_;
    _forbiddenAttributes = forbiddenAttributes_;
  }

  // ░░▒▒▓▓██ [ POLICY ] ───────────────────────────────────────────────────────

  // ┌─ requiredAttributes ─────
  function requiredAttributes() external view override returns (bytes32[] memory) {
    return _requiredAttributes;
  }

  // ┌─ forbiddenAttributes ─────
  function forbiddenAttributes() external view override returns (bytes32[] memory) {
    return _forbiddenAttributes;
  }

  // ┌─ meetsPolicy ─────
  /// @notice check whether `account` currently satisfies this policy, independent of hooks auth.
  function meetsPolicy(address account) public view override returns (bool) {
    return registry.meetsAttributes(account, _requiredAttributes, _forbiddenAttributes);
  }

  // ░░▒▒▓▓██ [ CREDENTIALS ] ──────────────────────────────────────────────────

  // ┌─ getCredential ─────
  /// @notice return the current block timestamp for an eligible wallet on an authorized hooks instance.
  ///
  /// @dev unauthorized callers and over-cap hooks get zero. reverts instead of wrapping if
  ///      `block.timestamp` passes `type(uint32).max`.
  function getCredential(address account) public view override returns (uint32) {
    if (!factory.isHooksAuthorized(msg.sender)) return 0;
    return meetsPolicy(account) ? block.timestamp.toUint32() : 0;
  }

  // ┌─ validateCredential ─────
  /// @dev same result as `getCredential(account)` for any payload, empty or not.
  function validateCredential(address account, bytes calldata) external view override returns (uint32) {
    return getCredential(account);
  }
}

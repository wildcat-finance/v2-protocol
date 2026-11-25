// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IKYCRoleProvider
//  \ ^ /   Immutable, attribute-backed KYC role provider interface.
//    V
//
//  CONFIGURATION
//  registry()
//  factory()
//  name()
//  requiredAttributes()
//  forbiddenAttributes()
//
//  POLICY
//  meetsPolicy(...)
// ═════

import '../access/IRoleProvider.sol';
import './IKYCRegistry.sol';
import './IKYCRoleProviderFactory.sol';

// ┌─ IKYCRoleProvider ─────────────────────────────────────────────────────────
/// @notice read-only, ownerless policy provider backed by `IKYCRegistry` and gated by
///         `IKYCRoleProviderFactory`.
///
/// @dev `getCredential` and `validateCredential` require `msg.sender` to be an authorized hooks
///      instance on `factory`. `meetsPolicy` exposes the ungated predicate for offchain previews.
interface IKYCRoleProvider is IRoleProvider {
  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev registry address cannot be zero.
  error InvalidRegistry();

  /// @dev factory address cannot be zero.
  error InvalidFactory();

  /// @dev every policy must require at least one attribute.
  error EmptyRequiredAttributes();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ registry ─────
  /// @notice return the attribute registry queried by this policy.
  function registry() external view returns (IKYCRegistry);

  // ┌─ factory ─────
  /// @notice return the entitlement factory checked before issuing credentials.
  function factory() external view returns (IKYCRoleProviderFactory);

  // ┌─ name ─────
  /// @notice return the human-readable label for this policy.
  function name() external view returns (string memory);

  // ┌─ requiredAttributes ─────
  /// @notice return the attribute keys that must all be present and unexpired.
  function requiredAttributes() external view returns (bytes32[] memory);

  // ┌─ forbiddenAttributes ─────
  /// @notice return the attribute keys that must all be absent, regardless of expiry.
  function forbiddenAttributes() external view returns (bytes32[] memory);

  // ░░▒▒▓▓██ [ POLICY ] ───────────────────────────────────────────────────────

  // ┌─ meetsPolicy ─────
  /// @notice evaluate whether `account` satisfies this policy's required and forbidden attributes.
  function meetsPolicy(address account) external view returns (bool);
}

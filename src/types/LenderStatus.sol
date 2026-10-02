// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LenderStatus
// ║  ██▀▀     ▀▀██   Cached lender credentials, expiry checks, and refresh state.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CREDENTIAL UPDATES
// ║  setCredential(...)
// ║  unsetCredential(...)
// ║
// ║  CREDENTIAL STATUS
// ║  hasCredential(...)
// ║  credentialNotExpired(...)
// ║  credentialExpired(...)
// ╚═════

import './RoleProvider.sol';

/// @notice cached access state for one lender.
///
/// @param isBlockedFromDeposits hooks-administrator block independent of provider credentials.
/// @param lastProvider          latest credential provider; retained when the credential is cleared.
/// @param canRefresh            whether the stored credential came from a pull provider and may be refreshed.
/// @param lastApprovalTimestamp timestamp when the stored credential was granted.
struct LenderStatus {
  bool isBlockedFromDeposits;
  address lastProvider;
  bool canRefresh;
  uint32 lastApprovalTimestamp;
}

using LibLenderStatus for LenderStatus global;

// ┌─ LibLenderStatus ──────────────────────────────────────────────────────────
library LibLenderStatus {
  // ░░▒▒▓▓██ [ CREDENTIAL UPDATES ] ───────────────────────────────────────────

  // ┌─ setCredential ─────
  /// @dev replace credential metadata; only a pull provider enables refresh.
  function setCredential(LenderStatus memory status, RoleProvider provider, uint256 timestamp) internal pure {
    status.lastApprovalTimestamp = uint32(timestamp);
    status.lastProvider = provider.providerAddress();
    status.canRefresh = provider.isPullProvider();
  }

  // ┌─ unsetCredential ─────
  /// @dev clear the cached credential without changing the lender's deposit block.
  function unsetCredential(LenderStatus memory status) internal pure {
    status.canRefresh = false;
    status.lastApprovalTimestamp = 0;
    status.lastProvider = address(0);
  }

  // ░░▒▒▓▓██ [ CREDENTIAL STATUS ] ────────────────────────────────────────────

  // ┌─ hasCredential ─────
  /// @dev return whether a credential grant timestamp is stored. it says nothing about expiry.
  function hasCredential(LenderStatus memory status) internal pure returns (bool) {
    return status.lastApprovalTimestamp > 0;
  }

  // ┌─ credentialNotExpired ─────
  /// @dev return whether the stored credential has not expired under `provider`'s current TTL.
  ///
  ///      pair this with hasCredential. a TTL greater than the current timestamp returns true
  ///      even when no credential exists.
  function credentialNotExpired(LenderStatus memory status, RoleProvider provider) internal view returns (bool) {
    return provider.calculateExpiry(status.lastApprovalTimestamp) >= block.timestamp;
  }

  // ┌─ credentialExpired ─────
  /// @dev return whether the stored credential has expired under `provider`'s current TTL.
  ///
  ///      pair this with hasCredential. a TTL greater than the current timestamp returns false
  ///      even when no credential exists.
  function credentialExpired(LenderStatus memory status, RoleProvider provider) internal view returns (bool) {
    return provider.calculateExpiry(status.lastApprovalTimestamp) < block.timestamp;
  }
}

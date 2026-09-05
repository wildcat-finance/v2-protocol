// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
import './RoleProvider.sol';

/**
 * @notice cached access state for one lender.
 * @param isBlockedFromDeposits hooks-administrator block independent of provider credentials.
 * @param lastProvider latest credential provider; retained when the credential is cleared.
 * @param canRefresh whether the stored credential came from a pull provider and may be refreshed.
 * @param lastApprovalTimestamp timestamp when the stored credential was granted.
 */
struct LenderStatus {
  bool isBlockedFromDeposits;
  address lastProvider;
  bool canRefresh;
  uint32 lastApprovalTimestamp;
}

using LibLenderStatus for LenderStatus global;

library LibLenderStatus {
  /**
   * @dev returns whether the stored credential has expired under `provider`'s current TTL.
   *
   *      Note: Does not check if the lender has a credential - if the
   *      provider's TTL is greater than the current block timestamp,
   *      this function will always return false. Should always be used
   *      in conjunction with `hasCredential`.
   */
  function credentialExpired(
    LenderStatus memory status,
    RoleProvider provider
  ) internal view returns (bool) {
    return provider.calculateExpiry(status.lastApprovalTimestamp) < block.timestamp;
  }

  /// @dev returns whether a credential grant timestamp is stored. it says nothing about expiry.
  function hasCredential(LenderStatus memory status) internal pure returns (bool) {
    return status.lastApprovalTimestamp > 0;
  }

  /**
   * @dev returns whether the stored credential has not expired under `provider`'s current TTL.
   *
   *      Note: Does not check if the lender has a credential - if the
   *      provider's TTL is greater than the current block timestamp,
   *      this function will always return true. Should always be used
   *      in conjunction with `hasCredential`.
   */
  function credentialNotExpired(
    LenderStatus memory status,
    RoleProvider provider
  ) internal view returns (bool) {
    return provider.calculateExpiry(status.lastApprovalTimestamp) >= block.timestamp;
  }

  /// @dev replaces cached credential metadata and only enables refresh for a pull provider.
  function setCredential(
    LenderStatus memory status,
    RoleProvider provider,
    uint256 timestamp
  ) internal pure {
    // user is approved, update status with the new approval timestamp and provider
    status.lastApprovalTimestamp = uint32(timestamp);
    status.lastProvider = provider.providerAddress();
    status.canRefresh = provider.isPullProvider();
  }

  /// @dev clears the cached credential without changing the lender's deposit block.
  function unsetCredential(LenderStatus memory status) internal pure {
    status.canRefresh = false;
    status.lastApprovalTimestamp = 0;
    status.lastProvider = address(0);
  }
}

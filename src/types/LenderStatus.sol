// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;
import './RoleProvider.sol';

/**
 * @todo - generate stack version of library
 * @param isBlockedFromDeposits Whether the lender is blocked from depositing
 * @param hasEverDeposited Whether the lender has ever deposited to the market
 * @param lastProvider The address of the last provider to grant the lender a credential
 * @param canRefresh Whether the last provider can refresh the lender's credential
 * @param lastApprovalTimestamp The timestamp at which the lender's credential was granted
 */
struct LenderStatus {
  bool isBlockedFromDeposits;
  bool hasEverDeposited;
  address lastProvider;
  bool canRefresh;
  uint32 lastApprovalTimestamp;
}

using LibLenderStatus for LenderStatus global;

library LibLenderStatus {
  function hasExpiredCredential(
    LenderStatus memory status,
    RoleProvider provider
  ) internal view returns (bool) {
    return provider.calculateExpiry(status.lastApprovalTimestamp) < block.timestamp;
  }

  function hasCredential(LenderStatus memory status) internal pure returns (bool) {
    return status.lastApprovalTimestamp > 0;
  }

  function hasActiveCredential(
    LenderStatus memory status,
    RoleProvider provider
  ) internal view returns (bool) {
    return provider.calculateExpiry(status.lastApprovalTimestamp) >= block.timestamp;
  }

  function setCredential(
    LenderStatus memory status,
    RoleProvider provider,
    uint256 timestamp
  ) internal pure {
    // User is approved, update status with new expiry and last provider
    status.lastApprovalTimestamp = uint32(timestamp);
    status.lastProvider = provider.providerAddress();
    status.canRefresh = provider.isPullProvider();
  }

  function unsetCredential(LenderStatus memory status) internal pure {
    status.canRefresh = false;
    status.lastApprovalTimestamp = 0;
    status.lastProvider = address(0);
  }
}

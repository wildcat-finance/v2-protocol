// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;
import './RoleProvider.sol';

/**
 * @todo - generate stack version of library
 * @param isBlocked Whether the lender is blocked from the market
 * @param hasEverDeposited Whether the lender has ever deposited to the market
 * @param lastProvider The address of the last provider to grant the lender a credential
 * @param canRefresh Whether the last provider can refresh the lender's credential
 * @param expiry The timestamp at which the lender's credential expires
 */
struct LenderStatus {
  bool isBlocked;
  bool hasEverDeposited;
  address lastProvider;
  bool canRefresh;
  uint32 expiry;
}

using LibLenderStatus for LenderStatus global;

library LibLenderStatus {
  function isExpired(LenderStatus memory status) internal view returns (bool) {
    return status.expiry < block.timestamp;
  }

  function isActive(LenderStatus memory status) internal view returns (bool) {
    return status.expiry >= block.timestamp;
  }

  function setCredential(
    LenderStatus memory status,
    RoleProvider provider,
    uint256 timestamp
  ) internal pure {
    // User is approved, update status with new expiry and last provider
    status.expiry = uint32(provider.calculateExpiry(timestamp));
    status.lastProvider = provider.providerAddress();
    status.canRefresh = provider.isPullProvider();
  }

  function unsetCredential(LenderStatus memory status) internal pure {
    status.canRefresh = false;
    status.expiry = 0;
    status.lastProvider = address(0);
  }
}

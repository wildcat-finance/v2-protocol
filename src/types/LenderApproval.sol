// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

struct LenderApproval {
  uint32 expiry;
  address lastRoleProvider;
  bool canPullLastProvider;
}

using LenderApprovalLib for LenderApproval global;

library LenderApprovalLib {
  function hasUnexpiredRole(LenderApproval memory status) internal view returns (bool) {
    return status.expiry > block.timestamp;
  }
}

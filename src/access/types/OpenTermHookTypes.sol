// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

/// @dev per-market access settings owned by one reusable hooks instance.
struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

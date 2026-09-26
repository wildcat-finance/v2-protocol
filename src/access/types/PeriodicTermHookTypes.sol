// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

/// @dev per-market schedule and access settings, packed into 31 bytes so the hot callbacks need one
///      storage slot. `minimumDeposit` is `uint96`; the external setter keeps its older `uint128`
///      ABI and checks the downcast.
struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  bool depositHookEnabled;
  uint96 minimumDeposit;
  uint32 firstWithdrawalWindowStart;
  uint32 periodDuration;
  uint32 withdrawalWindowDuration;
  bool transfersDisabled;
  bool isClosed;
}

/// @notice compatibility view of an APR reduction proposal.
struct PendingAprChange {
  uint16 annualInterestBips;
  uint32 proposalTimestamp;
}

/// @dev one-slot proposal state. response-window bounds are fixed at proposal time. this stays
///      separate from `PendingAprChange` to preserve the first template version's external tuple.
struct PendingAprChangeStorage {
  uint16 annualInterestBips;
  uint32 proposalTimestamp;
  uint32 responseWindowStart;
  uint32 responseWindowEnd;
}

/// @dev narrow market query used to prove a proposal is a strict reduction when it is created.
interface IMarketApr {
  /// @notice returns the market's current base annual interest rate, in bips.
  function annualInterestBips() external view returns (uint256);
}

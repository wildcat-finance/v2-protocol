// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import './MarketState.sol';
import './FIFOQueue.sol';

using MathUtils for uint256;
using WithdrawalLib for WithdrawalBatch global;

/// @notice aggregate accounting for requests sharing one expiry.
/// @dev tokens keep earning interest until payment reserves assets and burns scaled supply.
///      Cumulative counters can exceed live uint104 supply as paid shares are replaced.
///      The scaled counters share one slot; normalized payments occupy a second.
/// @param scaledTotalAmount cumulative scaled amount requested for the batch.
/// @param scaledAmountBurned scaled amount already paid and removed from live supply.
/// @param normalizedAmountPaid underlying assets reserved for the paid portion.
struct WithdrawalBatch {
  uint128 scaledTotalAmount;
  uint128 scaledAmountBurned;
  uint128 normalizedAmountPaid;
  // Ray numerator retained between payments; always less than RAY.
  uint128 paymentRemainder;
}

/// @notice one account's ownership and executed amount for a withdrawal batch.
/// @dev both cumulative fields share one slot; ownership can exceed a live uint104 balance.
/// @param scaledAmount account's fixed pro-rata share of the batch.
/// @param normalizedAmountWithdrawn amount already transferred or sent to sanctions escrow.
struct AccountWithdrawalStatus {
  uint128 scaledAmount;
  uint128 normalizedAmountWithdrawn;
}

/// @notice withdrawal storage shared by current, unpaid, and paid batches.
/// @param unpaidBatches FIFO expiries for underfunded batches.
/// @param batches aggregate batch data keyed by expiry.
/// @param accountStatuses account claims keyed by expiry then account.
struct WithdrawalData {
  FIFOQueue unpaidBatches;
  mapping(uint32 => WithdrawalBatch) batches;
  mapping(uint256 => mapping(address => AccountWithdrawalStatus)) accountStatuses;
}

library WithdrawalLib {
  /// @dev only call once this batch cannot accept more requests. No whole token is owed
  ///      by its final sub-RAY remainder; release it from the market-wide liability.
  function releaseRemainder(WithdrawalBatch memory batch, MarketState memory state) internal pure {
    if (batch.scaledTotalAmount == batch.scaledAmountBurned) {
      state.withdrawalRemainder -= batch.paymentRemainder;
      batch.paymentRemainder = 0;
    }
  }

  /// @dev returns the scaled part of `batch` that still needs payment.
  function scaledOwedAmount(WithdrawalBatch memory batch) internal pure returns (uint128) {
    return batch.scaledTotalAmount - batch.scaledAmountBurned;
  }

  /**
   * @dev Get the amount of assets which are not already reserved
   *      for prior withdrawal batches. This must only be used on
   *      the latest withdrawal batch to expire.
   */
  function availableLiquidityForPendingBatch(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 totalAssets
  ) internal pure returns (uint256) {
    // Subtract normalized value of pending scaled withdrawals, processed
    // withdrawals and protocol fees.
    uint256 priorScaledAmountPending = (state.scaledPendingWithdrawals - batch.scaledOwedAmount());
    uint256 unavailableAssets = state.normalizedUnclaimedWithdrawals +
      state.normalizeWithRemainder(
        priorScaledAmountPending,
        state.withdrawalRemainder - batch.paymentRemainder
      ) +
      state.accruedProtocolFees;
    return totalAssets.satSub(unavailableAssets);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../WildcatArchController.sol';
import '../market/WildcatMarket.sol';
import '../types/HooksConfig.sol';
import '../access/MarketConstraintHooks.sol';
import './HooksConfigData.sol';
import './HooksInstanceData.sol';
import './HooksTemplateData.sol';
import './LenderAccountData.sol';
import './TokenData.sol';

using WithdrawalBatchDataLib for WithdrawalBatchData global;
using WithdrawalBatchDataLib for WithdrawalBatchLenderStatus global;
using WithdrawalBatchDataLib for WithdrawalBatchDataWithLenderStatus global;

/// @notice lens classification for a withdrawal batch.
/// @dev `Expired` means the recorded current batch passed its timestamp but has not been processed
///      into the paid or unpaid state yet.
enum BatchStatus {
  Pending,
  Expired,
  Unpaid,
  Complete
}

/// @notice aggregate accounting and lens status for one withdrawal expiry.
struct WithdrawalBatchData {
  uint32 expiry;
  BatchStatus status;
  uint256 scaledTotalAmount;
  uint256 scaledAmountBurned;
  uint256 normalizedAmountPaid;
  uint256 normalizedTotalAmount;
}

/// @notice one lender's ownership and claim state in a withdrawal batch.
struct WithdrawalBatchLenderStatus {
  address lender;
  uint256 scaledAmount;
  uint256 normalizedAmountWithdrawn;
  uint256 normalizedAmountOwed;
  uint256 availableWithdrawalAmount;
}

/// @notice aggregate withdrawal data paired with one lender's status.
struct WithdrawalBatchDataWithLenderStatus {
  WithdrawalBatchData batch;
  WithdrawalBatchLenderStatus lenderStatus;
}

/// @notice fillers for withdrawal batches and lender claims.
library WithdrawalBatchDataLib {
  /// @notice fills aggregate batch state for `expiry`.
  /// @dev an unknown expiry is represented by the market's empty batch and classifies as complete.
  function fill(
    WithdrawalBatchData memory data,
    WildcatMarket market,
    uint32 expiry
  ) internal view {
    WithdrawalBatch memory batch = market.getWithdrawalBatch(expiry);
    data.expiry = expiry;
    data.scaledTotalAmount = batch.scaledTotalAmount;
    data.scaledAmountBurned = batch.scaledAmountBurned;
    data.normalizedAmountPaid = batch.normalizedAmountPaid;
    bool isPendingBatch = expiry != 0 && expiry == market.previousState().pendingWithdrawalExpiry;
    if (isPendingBatch) {
      data.status = expiry >= block.timestamp ? BatchStatus.Pending : BatchStatus.Expired;
    } else {
      data.status = data.scaledAmountBurned == data.scaledTotalAmount
        ? BatchStatus.Complete
        : BatchStatus.Unpaid;
    }
    if (data.scaledAmountBurned != data.scaledTotalAmount) {
      uint256 scaledAmountOwed = data.scaledTotalAmount - data.scaledAmountBurned;
      uint256 normalizedAmountOwed = MathUtils.rayMul(scaledAmountOwed, market.scaleFactor());
      data.normalizedTotalAmount = data.normalizedAmountPaid + normalizedAmountOwed;
    } else {
      data.normalizedTotalAmount = data.normalizedAmountPaid;
    }
  }

  /// @notice fills the lender's pro-rata paid and unpaid amounts for `batch`.
  function fill(
    WithdrawalBatchLenderStatus memory data,
    WildcatMarket market,
    WithdrawalBatchData memory batch,
    address lender
  ) internal view {
    data.lender = lender;
    // Unknown expiries return an empty batch, so there is no lender share to calculate.
    if (batch.scaledTotalAmount == 0) return;
    AccountWithdrawalStatus memory status = market.getAccountWithdrawalStatus(lender, batch.expiry);
    data.scaledAmount = status.scaledAmount;
    data.normalizedAmountWithdrawn = status.normalizedAmountWithdrawn;
    data.normalizedAmountOwed =
      MathUtils.mulDiv(batch.normalizedTotalAmount, data.scaledAmount, batch.scaledTotalAmount) -
      data.normalizedAmountWithdrawn;
    data.availableWithdrawalAmount =
      MathUtils.mulDiv(batch.normalizedAmountPaid, data.scaledAmount, batch.scaledTotalAmount) -
      data.normalizedAmountWithdrawn;
  }

  function fill(
    WithdrawalBatchDataWithLenderStatus memory data,
    WildcatMarket market,
    uint32 expiry,
    address lender
  ) internal view {
    data.batch.fill(market, expiry);
    data.lenderStatus.fill(market, data.batch, lender);
  }
}

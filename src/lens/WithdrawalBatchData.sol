// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import './MarketAccountingReader.sol';

import '../WildcatArchController.sol';
import '../market/WildcatMarket.sol';
import '../types/HooksConfig.sol';
import '../access/MarketConstraintHooks.sol';
import './HooksConfigData.sol';
import './HooksInstanceData.sol';
import './HooksTemplateData.sol';
import './LenderAccountData.sol';
import './TokenData.sol';
import { FixedPointMathLib } from 'solady/utils/FixedPointMathLib.sol';

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
  function fill(WithdrawalBatchData memory data, WildcatMarket market, uint32 expiry) internal view {
    WithdrawalBatch memory batch = MarketAccountingReader.withdrawalBatch(market, expiry);
    data.expiry = expiry;
    data.scaledTotalAmount = batch.scaledTotalAmount;
    data.scaledAmountBurned = batch.scaledAmountBurned;
    data.normalizedAmountPaid = batch.normalizedAmountPaid;
    // funded closure releases the current batch before expiry, including before the next write.
    bool isPendingBatch = expiry != 0 && expiry == MarketAccountingReader.previousState(market).pendingWithdrawalExpiry
      && !market.isClosed();
    if (isPendingBatch) {
      data.status = expiry >= block.timestamp ? BatchStatus.Pending : BatchStatus.Expired;
    } else {
      data.status = data.scaledAmountBurned == data.scaledTotalAmount ? BatchStatus.Complete : BatchStatus.Unpaid;
    }
    if (data.scaledAmountBurned != data.scaledTotalAmount) {
      uint256 scaledAmountOwed = data.scaledTotalAmount - data.scaledAmountBurned;
      uint256 normalizedAmountOwed = (scaledAmountOwed * market.scaleFactor() + batch.paymentRemainder + HALF_RAY) / RAY;
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
  )
    internal
    view
  {
    data.lender = lender;
    // Unknown expiries return an empty batch, so there is no lender share to calculate.
    if (batch.scaledTotalAmount == 0) return;
    AccountWithdrawalStatus memory status = market.getAccountWithdrawalStatus(lender, batch.expiry);
    data.scaledAmount = status.scaledAmount;
    data.normalizedAmountWithdrawn = status.normalizedAmountWithdrawn;
    // Paid volume is uint128, but adding interest on the remaining live shares
    // can take the quoted total above uint128. Preserve its full-width product
    // with cumulative ownership before dividing; the final claim still fits.
    data.normalizedAmountOwed = FixedPointMathLib.fullMulDiv(
      batch.normalizedTotalAmount, data.scaledAmount, batch.scaledTotalAmount
    ) - data.normalizedAmountWithdrawn;
    // reserved assets in a pending batch aren't collectible yet. normalizedAmountOwed still
    // includes them, so callers can distinguish their queued claim from an executable withdrawal.
    if (batch.status != BatchStatus.Pending) {
      data.availableWithdrawalAmount = MathUtils.mulDiv(
        batch.normalizedAmountPaid, data.scaledAmount, batch.scaledTotalAmount
      ) - data.normalizedAmountWithdrawn;
    }
  }

  function fill(
    WithdrawalBatchDataWithLenderStatus memory data,
    WildcatMarket market,
    uint32 expiry,
    address lender
  )
    internal
    view
  {
    data.batch.fill(market, expiry);
    data.lenderStatus.fill(market, data.batch, lender);
  }
}

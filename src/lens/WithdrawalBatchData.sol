// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

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

enum BatchStatus {
  Pending,
  Expired,
  Unpaid,
  Complete
}

struct WithdrawalBatchData {
  uint32 expiry;
  BatchStatus status;
  uint256 scaledTotalAmount;
  uint256 scaledAmountBurned;
  uint256 normalizedAmountPaid;
  uint256 normalizedTotalAmount;
}

struct WithdrawalBatchLenderStatus {
  address lender;
  uint256 scaledAmount;
  uint256 normalizedAmountWithdrawn;
  uint256 normalizedAmountOwed;
  uint256 availableWithdrawalAmount;
}

struct WithdrawalBatchDataWithLenderStatus {
  WithdrawalBatchData batch;
  WithdrawalBatchLenderStatus lenderStatus;
}

library WithdrawalBatchDataLib {
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
    if (expiry >= block.timestamp) {
      data.status = BatchStatus.Pending;
    } else if (expiry > market.previousState().lastInterestAccruedTimestamp) {
      data.status = BatchStatus.Expired;
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

  function fill(
    WithdrawalBatchLenderStatus memory data,
    WildcatMarket market,
    WithdrawalBatchData memory batch,
    address lender
  ) internal view {
    data.lender = lender;
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

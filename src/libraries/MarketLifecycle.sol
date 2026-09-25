// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import './Withdrawal.sol';

/// @dev keep this outside MarketState; that struct is copied directly into hook calldata.
struct MarketLifecycle {
  uint32 defaultedAt;
  uint40 penaltyCutoff;
}

struct LifecycleAccrual {
  uint32 from;
  uint32 to;
  uint112 scaleFactor;
  uint256 baseInterestRay;
  uint256 delinquencyFeeRay;
  uint256 protocolFee;
}

/// @dev one current batch and at most four accrual intervals: repayment, expiry, deadline, now.
///      old unpaid batches stay in the FIFO and are processed through bounded calls.
struct LifecycleTransition {
  MarketState state;
  MarketLifecycle lifecycle;
  WithdrawalBatch batch;
  uint32 batchExpiry;
  bool batchExpired;
  uint8 expiryAfterAccrual;
  uint8 accrualCount;
  LifecycleAccrual[4] accruals;
  uint32 closedAt;
  bool repaymentActivated;
}

library MarketLifecycleLib {
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  uint256 internal constant DefaultDelay = 90 days;

  /// @dev a cure at `penaltyCutoff` still counts. don't record default until a later timestamp.
  ///      timeDelinquent keeps its existing decay; this clock resets on an observed healthy state.
  function accrueDefaultRun(
    MarketLifecycle memory lifecycle,
    MarketState memory state,
    uint256 timestamp,
    uint256 gracePeriod
  ) internal pure {
    if (lifecycle.defaultedAt != 0) return;
    if (!state.isDelinquent || state.isClosed) {
      lifecycle.penaltyCutoff = 0;
      return;
    }
    if (lifecycle.penaltyCutoff == 0) {
      uint256 graceRemaining = gracePeriod.satSub(state.timeDelinquent);
      lifecycle.penaltyCutoff = uint40(
        uint256(state.lastInterestAccruedTimestamp) + graceRemaining + DefaultDelay
      );
    }
    if (timestamp > lifecycle.penaltyCutoff) {
      lifecycle.defaultedAt = uint256(lifecycle.penaltyCutoff).toUint32();
    }
  }

  /// @dev reaching repayment can end unused grace, but never restarts an existing penalty run.
  function activateRepayment(
    MarketLifecycle memory lifecycle,
    MarketState memory state,
    uint256 assets,
    uint256 date
  ) internal pure {
    state.reserveRatioBips = 10_000;
    state.isDelinquent = state.liquidityRequired() > assets;
    if (state.isDelinquent) {
      uint40 cutoff = uint40(date + DefaultDelay);
      if (lifecycle.penaltyCutoff == 0 || lifecycle.penaltyCutoff > cutoff) {
        lifecycle.penaltyCutoff = cutoff;
      }
    } else {
      lifecycle.penaltyCutoff = 0;
    }
  }

  /// @dev full backing stays in the market while batch allocation finishes. no future accrual.
  function closeFundedState(MarketState memory state) internal pure {
    state.isClosed = true;
    state.annualInterestBips = 0;
    state.reserveRatioBips = 10_000;
    state.timeDelinquent = 0;
    state.isDelinquent = false;
  }
}

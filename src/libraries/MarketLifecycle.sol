// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketLifecycle
//  \ ^ /   Repayment activation, default timing, and funded closure.
//    V
//
//  REPAYMENT
//  activateRepayment(...)
//
//  DEFAULT TIMING
//  accrueGraceTrackerDefault(...)
//
//  CLOSURE
//  closeFundedState(...)
// ═════

import './Withdrawal.sol';
import './BoolUtils.sol';

/// @dev keep this outside MarketState; that struct is copied directly into hook calldata.
struct MarketLifecycle {
  uint32 defaultedAt;
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
  // these counters only live in memory. uint8 still takes a word and adds cleanup masks.
  // the four-record array bounds accrualCount; expiryAfterAccrual copies that count.
  uint256 expiryAfterAccrual;
  uint256 accrualCount;
  LifecycleAccrual[4] accruals;
  uint32 closedAt;
  bool repaymentActivated;
}

// ┌─ MarketLifecycleLib ───────────────────────────────────────────────────────
library MarketLifecycleLib {
  using BoolUtils for bool;
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  uint256 internal constant DefaultDelay = 90 days;

  // ░░▒▒▓▓██ [ REPAYMENT ] ────────────────────────────────────────────────────

  // ┌─ activateRepayment ─────
  /// @dev reaching repayment raises required reserves without changing the grace tracker.
  function activateRepayment(MarketState memory state, uint256 assets) internal pure {
    state.reserveRatioBips = 10_000;
    state.isDelinquent = state.liquidityRequired() > assets;
  }

  // ░░▒▒▓▓██ [ DEFAULT TIMING ] ───────────────────────────────────────────────

  // ┌─ accrueGraceTrackerDefault ─────
  /// @dev use the tracker before this interval's accrual. it grows only while delinquent;
  ///      healthy intervals decay it in FeeMath. equality remains curable, so record default
  ///      only after the tracker exceeds configured grace plus 90 days.
  function accrueGraceTrackerDefault(
    MarketLifecycle memory lifecycle,
    MarketState memory state,
    uint256 timestamp,
    uint256 gracePeriod
  )
    internal
    pure
  {
    if ((lifecycle.defaultedAt != 0).or(!state.isDelinquent).or(state.isClosed)) return;
    uint256 remaining = (gracePeriod + DefaultDelay).satSub(state.timeDelinquent);
    uint256 cutoff = uint256(state.lastInterestAccruedTimestamp) + remaining;
    if (timestamp > cutoff) {
      lifecycle.defaultedAt = cutoff.toUint32();
    }
  }

  // ░░▒▒▓▓██ [ CLOSURE ] ──────────────────────────────────────────────────────

  // ┌─ closeFundedState ─────
  /// @dev full backing stays in the market while batch allocation finishes. no future accrual.
  function closeFundedState(MarketState memory state) internal pure {
    state.isClosed = true;
    state.annualInterestBips = 0;
    state.reserveRatioBips = 10_000;
    state.timeDelinquent = 0;
    state.isDelinquent = false;
  }
}

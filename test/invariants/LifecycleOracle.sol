// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils, RAY, HALF_RAY } from 'src/libraries/MathUtils.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';

/// @dev test model, not a call into MarketLifecycleLib. sort the observed boundaries, then
///      accrue and judge each one against the last written cash balance. live cash is only
///      available at the current timestamp. donations don't get to travel backwards in time.
library LifecycleOracle {
  using MathUtils for uint256;

  struct Terms {
    uint256 date;
    uint256 period;
    uint256 grace;
    uint256 penaltyBips;
    uint256 commitmentBips;
    bool revolving;
  }

  struct Observation {
    MarketState state;
    WithdrawalBatch batch;
    uint256 cash;
    uint256 cutoff;
    uint256 defaultedAt;
    uint256 drawn;
  }

  struct Preview {
    MarketState state;
    WithdrawalBatch batch;
    uint256 cutoff;
    uint256 defaultedAt;
    uint256 closedAt;
    uint256 fees;
    bool dateReached;
  }

  function preview(
    Observation memory old,
    Terms memory terms,
    uint256 timestamp,
    uint256 liveCash
  )
    internal
    pure
    returns (Preview memory p)
  {
    p.state = old.state;
    p.batch = old.batch;
    p.cutoff = old.cutoff;
    p.defaultedAt = old.defaultedAt;
    uint256 from = p.state.lastInterestAccruedTimestamp;
    uint256 expiry = p.state.pendingWithdrawalExpiry;
    uint256 deadline = terms.date + terms.period;
    bool crossesDate = terms.date > from && terms.date <= timestamp;
    bool crossesDeadline = terms.date != 0 && deadline >= from && deadline < timestamp;
    bool expires = expiry != 0 && expiry < timestamp;

    uint256[4] memory boundaries = [
      crossesDate ? terms.date : timestamp,
      crossesDeadline ? deadline : timestamp,
      expires ? expiry : timestamp,
      timestamp
    ];
    for (uint256 i = 1; i < 4; ++i) {
      uint256 value = boundaries[i];
      uint256 j = i;
      while (j != 0 && boundaries[j - 1] > value) {
        boundaries[j] = boundaries[j - 1];
        --j;
      }
      boundaries[j] = value;
    }

    for (uint256 i; i < 4; ++i) {
      uint256 at = boundaries[i];
      if (i != 0 && at == boundaries[i - 1]) continue;
      _accrue(p, terms, old.drawn, at);
      if (crossesDate && at == terms.date && !p.state.isClosed) {
        p.dateReached = true;
        p.state.reserveRatioBips = 10_000;
        p.state.isDelinquent = p.state.liquidityRequired() > old.cash;
        if (!p.state.isDelinquent) p.cutoff = 0;
        else if (p.cutoff == 0 || p.cutoff > at + 90 days) p.cutoff = at + 90 days;
        if (old.cash >= p.state.totalDebts()) _close(p, old.cash, at);
      }
      if (crossesDeadline && at == deadline && !p.state.isClosed) {
        if (p.defaultedAt == 0 && old.cash < p.state.totalDebts()) p.defaultedAt = deadline;
      }
      if (expires && at == expiry && p.state.pendingWithdrawalExpiry != 0) {
        _payBatch(p, old.cash);
        _releaseFraction(p);
        p.state.pendingWithdrawalExpiry = 0;
        p.state.isDelinquent = p.state.liquidityRequired() > old.cash;
      }
      if (p.closedAt != 0) break;
    }
    p.state.lastInterestAccruedTimestamp = uint32(timestamp);
    if (p.state.pendingWithdrawalExpiry != 0) _payBatch(p, liveCash);
    if (terms.date != 0 && timestamp >= terms.date && !p.state.isClosed) {
      if (liveCash >= p.state.totalDebts()) _close(p, liveCash, timestamp);
    }
  }

  function _accrue(Preview memory p, Terms memory t, uint256 drawn, uint256 at) private pure {
    MarketState memory s = p.state;
    uint256 from = s.lastInterestAccruedTimestamp;
    uint256 elapsed = at - from;
    bool repayment = t.date != 0 && from >= t.date;
    if (p.defaultedAt == 0) {
      if (s.isClosed || !s.isDelinquent) {
        p.cutoff = 0;
      } else {
        if (p.cutoff == 0) {
          uint256 graceLeft = repayment ? 0 : t.grace.satSub(s.timeDelinquent);
          p.cutoff = from + graceLeft + 90 days;
        }
        if (at > p.cutoff) p.defaultedAt = p.cutoff;
      }
    }
    if (elapsed == 0) return;

    uint256 base = MathUtils.calculateLinearInterestFromBips(s.annualInterestBips, elapsed);
    if (t.revolving) {
      uint256 supply = s.totalSupply();
      if (s.isClosed || supply == 0) {
        base = 0;
      } else {
        base = MathUtils.calculateLinearInterestFromBips(t.commitmentBips, elapsed)
          + MathUtils.mulDiv(base, MathUtils.min(drawn, supply), supply);
      }
    }
    uint256 fee =
      uint256(s.scaledTotalSupply).rayMul(uint256(s.scaleFactor).rayMul(uint256(s.protocolFeeBips).bipMul(base)));
    s.accruedProtocolFees += uint128(fee);
    p.fees += fee;
    uint256 penalized;
    if (s.isDelinquent) {
      penalized = repayment ? elapsed : elapsed.satSub(t.grace.satSub(s.timeDelinquent));
      s.timeDelinquent += uint32(elapsed);
    } else {
      penalized = MathUtils.min(elapsed, uint256(s.timeDelinquent).satSub(t.grace));
      s.timeDelinquent = uint32(uint256(s.timeDelinquent).satSub(elapsed));
    }
    uint256 penalty = MathUtils.calculateLinearInterestFromBips(t.penaltyBips, penalized);
    s.scaleFactor += uint112(uint256(s.scaleFactor).rayMul(base + penalty));
    s.lastInterestAccruedTimestamp = uint32(at);
  }

  function _payBatch(Preview memory p, uint256 cash) private pure {
    MarketState memory s = p.state;
    WithdrawalBatch memory b = p.batch;
    uint256 owed = b.scaledTotalAmount - b.scaledAmountBurned;
    uint256 prior = s.scaledPendingWithdrawals - owed;
    uint256 protected = (prior * s.scaleFactor + s.withdrawalRemainder - b.paymentRemainder + HALF_RAY) / RAY;
    uint256 available = cash.satSub(s.normalizedUnclaimedWithdrawals + protected + s.accruedProtocolFees);
    // Solve the affordability inequality directly, independently of the production
    // helper's floor-price capacity and one-share correction.
    uint256 burn = owed;
    if ((burn * s.scaleFactor + b.paymentRemainder) / RAY > available) {
      burn = ((available + 1) * RAY - 1 - b.paymentRemainder) / s.scaleFactor;
    }
    uint256 numerator = burn * s.scaleFactor + b.paymentRemainder;
    uint256 paid = numerator / RAY;
    s.withdrawalRemainder = uint128(uint256(s.withdrawalRemainder) - b.paymentRemainder + (numerator % RAY));
    b.paymentRemainder = uint128(numerator % RAY);
    b.scaledAmountBurned += uint128(burn);
    b.normalizedAmountPaid += uint128(paid);
    s.scaledPendingWithdrawals -= uint104(burn);
    s.scaledTotalSupply -= uint104(burn);
    s.normalizedUnclaimedWithdrawals += uint128(paid);
  }

  function _releaseFraction(Preview memory p) private pure {
    if (p.batch.scaledAmountBurned == p.batch.scaledTotalAmount) {
      p.state.withdrawalRemainder -= p.batch.paymentRemainder;
      p.batch.paymentRemainder = 0;
    }
  }

  function _close(Preview memory p, uint256 cash, uint256 at) private pure {
    if (p.state.pendingWithdrawalExpiry != 0) {
      _payBatch(p, cash);
      _releaseFraction(p);
    }
    p.state.pendingWithdrawalExpiry = 0;
    p.state.isClosed = true;
    p.state.isDelinquent = false;
    p.state.timeDelinquent = 0;
    p.state.annualInterestBips = 0;
    p.state.reserveRatioBips = 10_000;
    p.cutoff = 0;
    p.closedAt = at;
  }
}

/// @dev keep this oracle behind a staticcall so solc doesn't inline the whole model into
///      every inherited action. this is a test-only boundary, with no protocol dependency.
contract LifecycleReference {
  function preview(
    LifecycleOracle.Observation memory old,
    LifecycleOracle.Terms memory terms,
    uint256 timestamp,
    uint256 liveCash
  )
    external
    pure
    returns (LifecycleOracle.Preview memory)
  {
    return LifecycleOracle.preview(old, terms, timestamp, liveCash);
  }
}

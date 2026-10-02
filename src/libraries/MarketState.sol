// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketState
// ║  ██▀▀     ▀▀██   Share conversion, market liabilities, and available liquidity.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SUPPLY AND CAPACITY
// ║  totalSupply(...)
// ║  maximumDeposit(...)
// ║
// ║  SHARE CONVERSION
// ║  normalizeAmount(...)
// ║  normalizeWithRemainder(...)
// ║  scaleAmountDown(...)
// ║  maxScaledSettleableAmount(...)
// ║
// ║  LIABILITIES AND LIQUIDITY
// ║  totalDebts(...)
// ║  liquidityRequired(...)
// ║  borrowableAssets(...)
// ║  withdrawableProtocolFees(...)
// ║
// ║  WITHDRAWAL STATUS
// ║  hasPendingExpiredBatch(...)
// ╚═════

import './MathUtils.sol';
import './SafeCastLib.sol';
import './FeeMath.sol';

using MarketStateLib for MarketState global;
using MarketStateLib for Account global;
using FeeMath for MarketState global;

/// @notice cached market accounting state.
///
/// @dev functions pass this struct through hooks by value, then write the final value explicitly.
///
/// @param isClosed                       whether deposits, borrows, repayments, and term changes are disabled.
/// @param maxTotalSupply                 normalized supply cap for new deposits.
/// @param accruedProtocolFees            protocol fees owed in underlying-asset units.
/// @param normalizedUnclaimedWithdrawals assets reserved for paid claims not yet executed.
/// @param scaledTotalSupply              total live scaled supply, including unpaid withdrawal requests.
/// @param scaledPendingWithdrawals       scaled supply assigned to current and unpaid batches.
/// @param pendingWithdrawalExpiry        expiry of the current batch, or zero when none exists.
/// @param isDelinquent                   status used for the next accrual interval.
/// @param timeDelinquent                 rolling timer that rises while delinquent and decays while healthy.
/// @param protocolFeeBips                protocol share of base interest, charged on top, in bips.
/// @param annualInterestBips             base annual lender rate, in bips.
/// @param reserveRatioBips               reserve requirement on supply outside withdrawal batches, in bips.
/// @param scaleFactor                    ray-scaled ratio from scaled shares to normalized market tokens.
/// @param lastInterestAccruedTimestamp   end of the last applied accrual interval.
struct MarketState {
  bool isClosed;
  uint128 maxTotalSupply;
  uint128 accruedProtocolFees;
  uint128 normalizedUnclaimedWithdrawals;
  uint104 scaledTotalSupply;
  uint104 scaledPendingWithdrawals;
  uint32 pendingWithdrawalExpiry;
  bool isDelinquent;
  uint32 timeDelinquent;
  uint16 protocolFeeBips;
  uint16 annualInterestBips;
  uint16 reserveRatioBips;
  // accepted uint112 lifetime limit: about 7.7 years at 100% APR plus 100% delinquency
  // with maximally frequent updates. above 55 years at 28% cumulative, and above 100
  // years at typical 10-15% cumulative rates. see Known Issues.
  uint112 scaleFactor;
  uint32 lastInterestAccruedTimestamp;
  // sum of live batch payment remainders. doesn't earn interest.
  uint128 withdrawalRemainder;
}

/// @notice one lender's direct scaled market-token balance.
///
/// @param scaledBalance share-like balance before applying the market scale factor.
struct Account {
  uint104 scaledBalance;
}

// ┌─ MarketStateLib ───────────────────────────────────────────────────────────
library MarketStateLib {
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  // ░░▒▒▓▓██ [ SUPPLY AND CAPACITY ] ──────────────────────────────────────────

  // ┌─ totalSupply ─────
  /// @dev return normalized market supply.
  function totalSupply(MarketState memory state) internal pure returns (uint256) {
    return state.normalizeAmount(state.scaledTotalSupply);
  }

  // ┌─ maximumDeposit ─────
  /// @dev return remaining normalized deposit capacity, floored at zero.
  function maximumDeposit(MarketState memory state) internal pure returns (uint256) {
    return uint256(state.maxTotalSupply).satSub(state.totalSupply());
  }

  // ░░▒▒▓▓██ [ SHARE CONVERSION ] ─────────────────────────────────────────────

  // v2.5 rounding is deliberately asymmetric: normalized to scaled rounds down;
  // the acting party takes the loss. scaled to normalized labels rounds half-up.
  // don't restore the removed half-up scaleAmount path: rounding credits up brings
  // back the pre-release mismatch bugs. use MathUtils.rayDiv explicitly where
  // half-up division is actually needed.
  // ┌─ normalizeAmount ─────
  /// @dev normalize scaled tokens at the current factor, rounding half-up.
  function normalizeAmount(MarketState memory state, uint256 amount) internal pure returns (uint256) {
    return amount.rayMul(state.scaleFactor);
  }

  // ┌─ normalizeWithRemainder ─────
  /// @dev combine live shares and non-interest-bearing fractional withdrawal debt before
  ///      rounding. callers bound shares by uint104 and the remainder sum by uint128.
  function normalizeWithRemainder(
    MarketState memory state,
    uint256 scaledAmount,
    uint256 remainder
  )
    internal
    pure
    returns (uint256)
  {
    unchecked {
      return (scaledAmount * state.scaleFactor + remainder + HALF_RAY) / RAY;
    }
  }

  // ┌─ scaleAmountDown ─────
  /// @dev convert normalized tokens to scaled shares at the current factor, rounding down.
  function scaleAmountDown(MarketState memory state, uint256 amount) internal pure returns (uint256) {
    return (amount * RAY) / state.scaleFactor;
  }

  // ┌─ maxScaledSettleableAmount ─────
  /// @dev largest uint104 share amount `k` affordable at the batch's floor price:
  ///      floor(k * scaleFactor / RAY) <= normalizedAmount.
  ///
  ///      scaleAmountDown can miss the final affordable share. that strands debt after closure,
  ///      when repayment is disabled. settling it at the floor price still never spends more
  ///      than `normalizedAmount`.
  function maxScaledSettleableAmount(
    MarketState memory state,
    uint256 normalizedAmount
  )
    internal
    pure
    returns (uint256)
  {
    // withdrawal amounts only get uint104. cap here before multiplying liquidity by RAY;
    // direct token transfers can make `normalizedAmount` arbitrarily large.
    uint256 maxScaledAmount = type(uint104).max;
    uint256 normalizedMaxScaledAmount = MathUtils.mulDiv(maxScaledAmount, state.scaleFactor, RAY);
    if (normalizedAmount >= normalizedMaxScaledAmount) return maxScaledAmount;
    return MathUtils.mulDivUp(normalizedAmount + 1, RAY, state.scaleFactor) - 1;
  }

  // ░░▒▒▓▓██ [ LIABILITIES AND LIQUIDITY ] ────────────────────────────────────

  // ┌─ totalDebts ─────
  /// @dev return lender supply, paid-but-unclaimed withdrawals, and accrued protocol fees.
  function totalDebts(MarketState memory state) internal pure returns (uint256) {
    // normalized uint104 supply is below 128 bits, and both other debts are uint128.
    unchecked {
      return state.normalizeWithRemainder(state.scaledTotalSupply, state.withdrawalRemainder)
        + state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees;
    }
  }

  // ┌─ liquidityRequired ─────
  /// @dev reserve all of the following:
  ///      - 100% of all pending (unpaid) withdrawals
  ///      - 100% of all unclaimed (paid) withdrawals
  ///      - reserve ratio times the outstanding debt (supply - pending withdrawals)
  ///      - accrued protocol fees
  function liquidityRequired(MarketState memory state) internal pure returns (uint256 _liquidityRequired) {
    uint256 normalizedPendingWithdrawals =
      state.normalizeWithRemainder(state.scaledPendingWithdrawals, state.withdrawalRemainder);
    uint256 normalizedOutstandingSupply =
      state.normalizeWithRemainder(state.scaledTotalSupply, state.withdrawalRemainder) - normalizedPendingWithdrawals;
    // this partition handles 0% and 100% exactly. normalized supply is below 128 bits;
    // multiplying by a uint16 ratio and adding both uint128 liabilities still fits uint256.
    unchecked {
      return normalizedPendingWithdrawals + normalizedOutstandingSupply.bipMul(state.reserveRatioBips)
        + state.accruedProtocolFees + state.normalizedUnclaimedWithdrawals;
    }
  }

  // ┌─ borrowableAssets ─────
  /// @dev only assets above the full collateral requirement are borrowable. retain 100% of
  ///      unpaid withdrawals and paid-but-unclaimed assets, the reserve-ratio share of other
  ///      outstanding supply, and accrued protocol fees.
  function borrowableAssets(MarketState memory state, uint256 totalAssets) internal pure returns (uint256) {
    return totalAssets.satSub(state.liquidityRequired());
  }

  // ┌─ withdrawableProtocolFees ─────
  /// @dev quote protocol fees only from assets left after paid-but-unclaimed withdrawals.
  ///      those claims are the only debts with higher priority here.
  function withdrawableProtocolFees(MarketState memory state, uint256 totalAssets) internal pure returns (uint128) {
    uint256 totalAvailableAssets = totalAssets.satSub(state.normalizedUnclaimedWithdrawals);
    return uint128(MathUtils.min(totalAvailableAssets, state.accruedProtocolFees));
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL STATUS ] ────────────────────────────────────────────

  // ┌─ hasPendingExpiredBatch ─────
  /// @dev return true only when a current batch exists and its expiry is strictly in the past.
  function hasPendingExpiredBatch(MarketState memory state) internal view returns (bool result) {
    uint256 expiry = state.pendingWithdrawalExpiry;
    assembly {
      // equivalent to expiry > 0 && expiry < block.timestamp
      result := and(gt(expiry, 0), gt(timestamp(), expiry))
    }
  }
}

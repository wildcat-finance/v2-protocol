// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // Withdrawal.t
//  \ ^ /   Available liquidity for the pending withdrawal batch.
//    V
//
//  BATCH FUNDING
//  test_availableLiquidityForPendingBatch(...)
// ═════

import 'src/libraries/Withdrawal.sol';
import './wrappers/WithdrawalLibExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// coverage workaround for WithdrawalLib: the external wrapper uses library-qualified calls
// (XLib.x(value)), so the mapper sees the library identifier instead of value.x().
// ┌─ WithdrawalTest ───────────────────────────────────────────────────────────
contract WithdrawalTest is TestKernel {
  using WithdrawalLibExternal for WithdrawalBatch;

  // ░░▒▒▓▓██ [ BATCH FUNDING ] ────────────────────────────────────────────────

  // ┌─ test_availableLiquidityForPendingBatch ─────
  function test_availableLiquidityForPendingBatch(
    uint128 totalAssets,
    uint104 scaledTotalPendingWithdrawals,
    uint104 scaledBatchAmount,
    uint128 scaledAmountBurned,
    uint128 normalizedUnclaimedWithdrawals,
    uint96 scaleFactor,
    uint128 accruedProtocolFees
  )
    external
    pure
  {
    scaledTotalPendingWithdrawals = uint104(bound(scaledTotalPendingWithdrawals, 1, type(uint104).max));
    scaledBatchAmount = uint104(bound(scaledBatchAmount, 1, scaledTotalPendingWithdrawals));
    scaledAmountBurned = uint128(bound(scaledAmountBurned, 0, type(uint128).max - scaledBatchAmount));
    MarketState memory state;
    state.normalizedUnclaimedWithdrawals = normalizedUnclaimedWithdrawals;
    state.accruedProtocolFees = accruedProtocolFees;
    state.scaleFactor = scaleFactor;
    state.scaledPendingWithdrawals = scaledTotalPendingWithdrawals;
    WithdrawalBatch memory batch;
    batch.scaledTotalAmount = scaledAmountBurned + scaledBatchAmount;
    batch.scaledAmountBurned = scaledAmountBurned;
    uint256 totalReserved = uint256(normalizedUnclaimedWithdrawals) + uint256(accruedProtocolFees)
      + state.normalizeAmount(scaledTotalPendingWithdrawals - scaledBatchAmount);
    uint256 expected = totalAssets > totalReserved ? totalAssets - totalReserved : 0;
    assertEq(batch.$availableLiquidityForPendingBatch(state, totalAssets), expected);
  }
}

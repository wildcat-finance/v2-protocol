// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WithdrawalPaymentHarness
// ║  ██▀▀     ▀▀██   Withdrawal payment, remainder, and liquidity test adapters.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  WITHDRAWAL FUNDING
// ║  pendingLiquidity(...)
// ║  applyPayment(...)
// ║  release(...)
// ╚═════

import { WildcatMarketBase } from 'src/market/WildcatMarketBase.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';

// ┌─ WithdrawalPaymentHarness ─────────────────────────────────────────────────
contract WithdrawalPaymentHarness is WildcatMarketBase {
  // ░░▒▒▓▓██ [ WITHDRAWAL FUNDING ] ───────────────────────────────────────────

  // ┌─ pendingLiquidity ─────
  function pendingLiquidity(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 assets
  )
    external
    pure
    returns (uint256)
  {
    return batch.availableLiquidityForPendingBatch(state, assets);
  }

  // ┌─ applyPayment ─────
  function applyPayment(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 available
  )
    external
    pure
    returns (WithdrawalBatch memory, MarketState memory, uint104 burned, uint128 paid)
  {
    (burned, paid) = _applyWithdrawalBatchPaymentView(batch, state, available);
    return (batch, state, burned, paid);
  }

  // ┌─ release ─────
  function release(
    WithdrawalBatch memory batch,
    MarketState memory state
  )
    external
    pure
    returns (WithdrawalBatch memory, MarketState memory)
  {
    batch.releaseRemainder(state);
    return (batch, state);
  }
}

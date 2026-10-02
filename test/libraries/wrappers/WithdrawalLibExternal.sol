pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WithdrawalLibExternal
// ║  ██▀▀     ▀▀██   External adapters for withdrawal debt and batch liquidity.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  BATCH FUNDING
// ║  $scaledOwedAmount(...)
// ║  $availableLiquidityForPendingBatch(...)
// ╚═════

import { WithdrawalBatch, WithdrawalLib, MarketState } from 'src/libraries/Withdrawal.sol';

// ┌─ WithdrawalLibExternal ────────────────────────────────────────────────────
library WithdrawalLibExternal {
  // ░░▒▒▓▓██ [ BATCH FUNDING ] ────────────────────────────────────────────────

  // ┌─ $scaledOwedAmount ─────
  function $scaledOwedAmount(WithdrawalBatch memory batch) external pure returns (uint128) {
    return WithdrawalLib.scaledOwedAmount(batch);
  }

  // ┌─ $availableLiquidityForPendingBatch ─────
  /// @dev quote assets not reserved for earlier batches. use only for the latest batch to expire.
  function $availableLiquidityForPendingBatch(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 totalAssets
  )
    external
    pure
    returns (uint256)
  {
    return WithdrawalLib.availableLiquidityForPendingBatch(batch, state, totalAssets);
  }
}

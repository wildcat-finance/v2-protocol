// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WrapperQueueAccountMock
//  \ ^ /   Combined wrapper redemption and withdrawal queueing.
//    V
//
//  REDEEM AND QUEUE
//  redeemAndQueue(...)
// ═════

import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';

// ┌─ WrapperQueueAccountMock ──────────────────────────────────────────────────
contract WrapperQueueAccountMock {
  // ░░▒▒▓▓██ [ REDEEM AND QUEUE ] ─────────────────────────────────────────────

  // ┌─ redeemAndQueue ─────
  function redeemAndQueue(
    Wildcat4626Wrapper wrapper,
    WildcatMarket market,
    uint256 shares,
    uint256 scaledAmount
  )
    external
    returns (uint256 assets, uint32 expiry)
  {
    assets = wrapper.redeem(shares, address(this), address(this));
    expiry = market.queueWithdrawalScaled(scaledAmount);
  }
}

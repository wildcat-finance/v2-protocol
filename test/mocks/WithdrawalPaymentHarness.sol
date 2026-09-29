// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { WildcatMarketBase } from 'src/market/WildcatMarketBase.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';

contract WithdrawalPaymentHarness is WildcatMarketBase {
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
}

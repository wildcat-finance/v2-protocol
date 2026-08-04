// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './MathUtils.sol';
import './MarketState.sol';

using MathUtils for uint256;
using MarketStateLib for MarketState;

/**
 * @title RevolvingDrawnMath
 * @dev Closed-form drawn-amount transitions for revolving markets.
 *
 *      `WildcatMarketRevolving` applies these transitions inline. Hooks that
 *      observe or gate draws must predict the same values from inside the
 *      `onBorrow` / `onRepay` callbacks, which run *before* the market updates
 *      its own drawn amount — so both sides must agree exactly.
 *
 *      Keeping the arithmetic here means one definition rather than two.
 *      NOTE: `WildcatMarketRevolving` does not yet call into this library
 *      (doing so changes deployed market bytecode); until it does, any change
 *      to its inline formulas must be mirrored here. See README.
 */
library RevolvingDrawnMath {
  /**
   * @dev Drawn amount after a borrow of `amount`.
   * @param currentDrawn Drawn amount before the borrow.
   * @param currentTotalAssets Market asset balance *before* assets leave, i.e.
   *        the value `totalAssets()` returns during the `onBorrow` callback.
   * @param state Intermediate market state as passed to the hook.
   */
  function drawnAfterBorrow(
    uint256 currentDrawn,
    uint256 currentTotalAssets,
    MarketState memory state,
    uint256 amount
  ) internal pure returns (uint256) {
    uint256 assetsAfterBorrow = currentTotalAssets.satSub(amount);
    uint256 outstandingDebt = state.totalDebts().satSub(assetsAfterBorrow);
    return MathUtils.min(currentDrawn + amount, outstandingDebt);
  }

  /**
   * @dev Drawn amount after a repayment.
   * @param currentTotalAssets Market asset balance *including* the repaid
   *        amount, i.e. the value `totalAssets()` returns during `onRepay`.
   */
  function drawnAfterRepay(
    uint256 currentDrawn,
    uint256 currentTotalAssets,
    MarketState memory state
  ) internal pure returns (uint256) {
    uint256 outstandingDebt = state.totalDebts().satSub(currentTotalAssets);
    return MathUtils.min(currentDrawn, outstandingDebt);
  }
}

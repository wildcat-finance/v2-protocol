// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../../libraries/MarketState.sol';
import '../../libraries/RevolvingDrawnMath.sol';

/// @dev Minimal market surface needed by covenant mixins. Wildcat markets
///      expose all of these; `drawnAmount` exists only on revolving markets.
interface ICovenantMarket {
  function borrower() external view returns (address);

  function totalAssets() external view returns (uint256);

  function drawnAmount() external view returns (uint256);

  function delinquencyGracePeriod() external view returns (uint256);

  function currentState() external view returns (MarketState memory);
}

/// @dev Arch-controller surface needed to verify that an address is a real market.
interface ICovenantMarketRegistry {
  function isRegisteredMarket(address market) external view returns (bool);
}

/**
 * @title CovenantBase
 * @dev Shared plumbing for covenant mixins.
 *
 *      Covenant mixins are deliberately *not* derived from `IHooks`. They hold
 *      their own storage, expose their own views, and provide `internal`
 *      entry points that a concrete hooks template calls from its `onBorrow`,
 *      `onRepay` and `_onCreateMarket` implementations. Keeping them off the
 *      `IHooks` inheritance path avoids a diamond with `BaseAccessControls`
 *      and `MarketConstraintHooks`, and means a template pays no bytecode or
 *      storage cost for covenants it does not inherit.
 *
 *      A concrete template must implement `_covenantBorrower()` and, if it
 *      inherits any covenant that inspects other markets,
 *      `_covenantArchController()`.
 */
abstract contract CovenantBase {
  /// @dev Drawn amount the calling market will hold after the borrow now in
  ///      flight. Valid only inside `onBorrow`, where the market has not yet
  ///      updated its drawn amount or transferred assets.
  function _drawnAfterBorrow(
    MarketState calldata state,
    uint256 amount
  ) internal view returns (uint256) {
    return
      RevolvingDrawnMath.drawnAfterBorrow(
        ICovenantMarket(msg.sender).drawnAmount(),
        ICovenantMarket(msg.sender).totalAssets(),
        state,
        amount
      );
  }

  /// @dev Drawn amount the calling market will hold after the repayment now in
  ///      flight. Valid only inside `onRepay`, where assets have arrived but
  ///      the market has not yet updated its drawn amount.
  function _drawnAfterRepay(MarketState calldata state) internal view returns (uint256) {
    return
      RevolvingDrawnMath.drawnAfterRepay(
        ICovenantMarket(msg.sender).drawnAmount(),
        ICovenantMarket(msg.sender).totalAssets(),
        state
      );
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../../libraries/MarketState.sol';
import '../../libraries/DrawnMath.sol';

/// @dev Minimal market surface needed by covenant mixins. Wildcat markets
///      expose all of these; `drawnAmount` exists only on revolving markets.
interface ICovenantMarket {
  function borrower() external view returns (address);

  function totalAssets() external view returns (uint256);

  function drawnAmount() external view returns (uint256);

  function totalDebts() external view returns (uint256);

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
  /// @dev Drawn amount of `market`, resilient to market kind: revolving
  ///      markets report it natively, and for standard markets the
  ///      equivalent quantity is outstanding debt not covered by assets
  ///      still in the market, `totalDebts - totalAssets`, floored at zero.
  ///      The prediction maths below converges to the same answer for both,
  ///      so every covenant works unchanged on either kind.
  /// @dev Mid-hook variant: the market holds its reentrancy lock inside
  ///      `onBorrow`/`onRepay` and a standard market's `totalDebts()` is a
  ///      guarded view, so the fallback reads debts from the state already
  ///      in calldata instead of calling back in.
  function _covenantDrawnBefore(MarketState calldata state) internal view returns (uint256) {
    (bool ok, bytes memory ret) = msg.sender.staticcall(
      abi.encodeWithSignature('drawnAmount()')
    );
    if (ok && ret.length >= 32) return abi.decode(ret, (uint256));
    uint256 debts = state.totalDebts();
    uint256 assets = ICovenantMarket(msg.sender).totalAssets();
    return debts > assets ? debts - assets : 0;
  }

  function _covenantDrawnOf(address market) internal view returns (uint256) {
    (bool ok, bytes memory ret) = market.staticcall(
      abi.encodeWithSignature('drawnAmount()')
    );
    if (ok && ret.length >= 32) return abi.decode(ret, (uint256));
    uint256 debts = ICovenantMarket(market).totalDebts();
    uint256 assets = ICovenantMarket(market).totalAssets();
    return debts > assets ? debts - assets : 0;
  }

  function _drawnAfterBorrow(
    MarketState calldata state,
    uint256 amount
  ) internal view returns (uint256) {
    return
      DrawnMath.drawnAfterBorrow(
        _covenantDrawnBefore(state),
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
      DrawnMath.drawnAfterRepay(
        _covenantDrawnBefore(state),
        ICovenantMarket(msg.sender).totalAssets(),
        state
      );
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './lib/CleanDownLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title CleanDownCovenant
 * @dev Near-universal TradFi revolver covenant: the facility has to return to
 *      a de minimis drawn level for `duration` consecutive seconds at least
 *      once every `interval` seconds, evidencing use as a revolver rather
 *      than disguised term debt. The threshold is the larger of a tenth of a
 *      token and one window's expected carry; `CleanDownLib` carries the
 *      full rationale.
 *
 *      Enforcement is a drawstop rather than a default. Once overdue, draws
 *      that would leave the market drawn revert, and drawing resumes as soon
 *      as a fresh qualifying streak completes. Nothing is accelerated, no
 *      third party adjudicates, and no keeper is required: a matured streak is
 *      credited inside the transaction that consumes it.
 *
 *      Three deliberate behaviours:
 *      - Idle time from market creation counts, so a market that has never
 *        drawn does not arrive at its first deadline already in breach.
 *      - Reclaiming an over-repayment is not credit. A draw that leaves the
 *        drawn amount at zero neither trips the covenant nor breaks a streak.
 *      - Partial repayments do not start a streak; only reaching the
 *        threshold does.
 *
 *      This mixin owns the storage and the external surface; the bodies live
 *      in `CleanDownLib`, an external library reached by `DELEGATECALL`.
 *      Inheriting `ICovenantEvents` keeps the events and errors in the
 *      template's ABI even though they are raised from the library.
 */
abstract contract CleanDownCovenant is CovenantBase, ICovenantEvents {
  mapping(address => CleanDownState) internal _cleanDown;

  function _initCleanDownCovenant(
    address market,
    address asset,
    uint32 duration,
    uint32 interval
  ) internal {
    CleanDownLib.init(_cleanDown, market, asset, duration, interval);
  }

  function _cleanThresholdFromState(
    MarketState calldata state
  ) private view returns (uint256) {
    return
      CleanDownLib.cleanThreshold(
        _cleanDown[msg.sender],
        state.totalSupply(),
        state.annualInterestBips,
        state.protocolFeeBips
      );
  }

  /// @dev Called from `onBorrow`.
  function _cleanDownOnBorrow(MarketState calldata state, uint256 drawnAfter) internal {
    CleanDownLib.onBorrow(_cleanDown, msg.sender, drawnAfter, _cleanThresholdFromState(state));
  }

  /// @dev Called from `onRepay`.
  function _cleanDownOnRepay(MarketState calldata state, uint256 drawnAfter) internal {
    CleanDownLib.onRepay(_cleanDown, msg.sender, drawnAfter, _cleanThresholdFromState(state));
  }

  /// @notice The live clean threshold for `market`: drawn at or below this
  ///         counts as clean. Larger of a tenth of a token and one window's
  ///         expected interest-plus-fee carry on current supply.
  function cleanDownThreshold(address market) external view returns (uint256) {
    ICovenantMarket m = ICovenantMarket(market);
    MarketState memory st = m.currentState();
    return
      CleanDownLib.cleanThreshold(
        _cleanDown[market],
        st.totalSupply(),
        st.annualInterestBips,
        st.protocolFeeBips
      );
  }

  function getCleanDownState(address market) external view returns (CleanDownState memory) {
    return _cleanDown[market];
  }

  /**
   * @notice Clean-down standing for a market, applying any matured streak
   *         virtually, so it reports what the next hook call would credit.
   */
  function getCleanDownStatus(
    address market
  ) external view returns (bool enabled, bool overdue, uint256 dueBy, uint256 zeroSince) {
    return CleanDownLib.status(_cleanDown, market);
  }
}

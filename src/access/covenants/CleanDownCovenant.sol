// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './lib/CleanDownLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title CleanDownCovenant
 * @dev Near-universal TradFi revolver covenant: the facility has to return to
 *      zero drawn for `duration` consecutive seconds at least once every
 *      `interval` seconds, evidencing use as a revolver rather than disguised
 *      term debt.
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
 *      - Partial repayments do not start a streak; only reaching zero does.
 *
 *      This mixin owns the storage and the external surface; the bodies live
 *      in `CleanDownLib`, an external library reached by `DELEGATECALL`.
 *      Inheriting `ICovenantEvents` keeps the events and errors in the
 *      template's ABI even though they are raised from the library.
 */
abstract contract CleanDownCovenant is CovenantBase, ICovenantEvents {
  mapping(address => CleanDownState) internal _cleanDown;

  function _initCleanDownCovenant(address market, uint32 duration, uint32 interval) internal {
    CleanDownLib.init(_cleanDown, market, duration, interval);
  }

  /// @dev Called from `onBorrow`.
  function _cleanDownOnBorrow(uint256 drawnAfter) internal {
    CleanDownLib.onBorrow(_cleanDown, msg.sender, drawnAfter);
  }

  /// @dev Called from `onRepay`.
  function _cleanDownOnRepay(uint256 drawnAfter) internal {
    CleanDownLib.onRepay(_cleanDown, msg.sender, drawnAfter);
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

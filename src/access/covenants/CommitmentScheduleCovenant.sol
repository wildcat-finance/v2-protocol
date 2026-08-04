// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './lib/CommitmentScheduleLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title CommitmentScheduleCovenant
 * @dev Amortising-revolver covenant: a piecewise-constant ceiling on the drawn
 *      amount that declines on a pre-agreed schedule. The terminal case, a
 *      final ceiling of zero, is availability-period expiry: after that date
 *      the facility can be repaid and exited but not drawn.
 *
 *      Enforcement is a drawstop on the DRAWN amount and nothing else. Breach
 *      is curable by repaying below the schedule, repayment and withdrawals
 *      are never gated, and draws that do not increase the drawn amount
 *      (reclaiming an over-repayment) pass untouched.
 *
 *      The commitment itself, and with it the commitment-fee base, is out of
 *      scope on purpose. Whether `maxTotalSupply` should step down alongside
 *      the drawn ceiling is a market design question with lender-side
 *      consequences; a covenant deciding it unilaterally would be forcing
 *      capital out. Configure the market's supply behaviour separately.
 *
 *      This mixin owns the storage and the external surface; the bodies live
 *      in `CommitmentScheduleLib`, an external library reached by
 *      `DELEGATECALL`. Inheriting `ICovenantEvents` keeps events and errors in
 *      the template ABI even though they are raised from the library.
 */
abstract contract CommitmentScheduleCovenant is CovenantBase, ICovenantEvents {
  mapping(address => CommitmentSchedule) internal _schedules;

  /// @dev Schedule words arrive as two equal-length arrays. Empty arrays
  ///      disable the covenant.
  function _initCommitmentScheduleCovenant(
    address market,
    uint40[] memory steps,
    uint128[] memory ceilings
  ) internal {
    CommitmentScheduleLib.init(_schedules, market, steps, ceilings);
  }

  /// @dev Called from `onBorrow` with the predicted drawn transition.
  function _commitmentScheduleOnBorrow(uint256 drawnBefore, uint256 drawnAfter) internal view {
    CommitmentScheduleLib.checkOnBorrow(_schedules, msg.sender, drawnBefore, drawnAfter);
  }

  function getCommitmentSchedule(
    address market
  ) external view returns (uint40[] memory steps, uint128[] memory ceilings) {
    CommitmentSchedule storage s = _schedules[market];
    return (s.steps, s.ceilings);
  }

  /// @notice The drawn ceiling currently in force for `market`.
  ///         `type(uint256).max` when unconstrained.
  function currentDrawnCeiling(address market) external view returns (uint256) {
    return CommitmentScheduleLib.ceilingAt(_schedules, market, block.timestamp);
  }
}

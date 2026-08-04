// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantEvents.sol';

/// @dev Piecewise-constant declining ceiling on the drawn amount.
///      `steps` timestamps must be strictly increasing; `ceilings` must be
///      strictly decreasing. Before the first step the ceiling is unlimited.
///      A final ceiling of zero is availability-period expiry.
struct CommitmentSchedule {
  uint40[] steps;
  uint128[] ceilings;
}

/**
 * @title CommitmentScheduleLib
 * @dev Body of the commitment-reduction covenant, as an external library
 *      reached by `DELEGATECALL`. Storage arrives as pointers and is read and
 *      written in place.
 *
 *      Enforcement is on the DRAWN amount, deliberately. A drawn ceiling makes
 *      breach curable: repay below the schedule and drawing resumes. Reducing
 *      supply instead would force lender capital out and turn a covenant into
 *      a market-design decision. Whether the commitment (and so the fee base)
 *      steps down alongside the drawn ceiling stays a market parameter, not a
 *      covenant concern.
 */
library CommitmentScheduleLib {
  uint256 internal constant MAX_SCHEDULE_STEPS = 24;

  function init(
    mapping(address => CommitmentSchedule) storage schedules,
    address market,
    uint40[] memory steps,
    uint128[] memory ceilings
  ) public {
    uint256 n = steps.length;
    if (n == 0) return; // covenant disabled
    if (n != ceilings.length || n > MAX_SCHEDULE_STEPS) {
      revert ICovenantEvents.InvalidCommitmentSchedule();
    }
    for (uint256 i; i < n; i++) {
      if (steps[i] <= block.timestamp && i == 0) {
        // a schedule that starts in the past is almost certainly a mistake
        revert ICovenantEvents.InvalidCommitmentSchedule();
      }
      if (i > 0) {
        if (steps[i] <= steps[i - 1]) revert ICovenantEvents.InvalidCommitmentSchedule();
        if (ceilings[i] >= ceilings[i - 1]) revert ICovenantEvents.InvalidCommitmentSchedule();
      }
    }
    CommitmentSchedule storage s = schedules[market];
    s.steps = steps;
    s.ceilings = ceilings;
    emit ICovenantEvents.CommitmentScheduleSet(market, steps, ceilings);
  }

  /// @dev The ceiling in force at `timestamp`. `type(uint256).max` before the
  ///      first step or when the covenant is disabled.
  function ceilingAt(
    mapping(address => CommitmentSchedule) storage schedules,
    address market,
    uint256 timestamp
  ) public view returns (uint256 ceiling) {
    CommitmentSchedule storage s = schedules[market];
    uint256 n = s.steps.length;
    ceiling = type(uint256).max;
    for (uint256 i; i < n; i++) {
      if (timestamp >= s.steps[i]) ceiling = s.ceilings[i];
      else break;
    }
  }

  /// @dev Reverts if a borrow leaving `drawnAfter` outstanding would exceed
  ///      the ceiling in force. Draws that reduce or hold the drawn amount
  ///      (reclaiming an over-repayment) are never gated.
  function checkOnBorrow(
    mapping(address => CommitmentSchedule) storage schedules,
    address market,
    uint256 drawnBefore,
    uint256 drawnAfter
  ) public view {
    if (drawnAfter <= drawnBefore) return;
    uint256 ceiling = ceilingAt(schedules, market, block.timestamp);
    if (drawnAfter > ceiling) {
      revert ICovenantEvents.DrawnCeilingExceeded(drawnAfter, ceiling);
    }
  }
}

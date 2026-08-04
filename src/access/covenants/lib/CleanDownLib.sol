// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantEvents.sol';

struct CleanDownState {
  uint32 duration;
  uint32 interval;
  uint40 zeroSince;
  uint40 lastCleanDown;
}

/**
 * @title CleanDownLib
 * @dev Body of the clean-down covenant, as an external library. `public`
 *      functions are reached by `DELEGATECALL`, so this code lives at its own
 *      address and does not count against the inheriting template's EIP-170
 *      limit. State arrives as a storage pointer and is mutated in place.
 */
library CleanDownLib {
  function init(
    mapping(address => CleanDownState) storage cd,
    address market,
    uint32 duration,
    uint32 interval
  ) public {
    if (duration > 0) {
      if (interval <= duration) revert ICovenantEvents.InvalidCleanDownConfiguration();
    } else if (interval > 0) {
      revert ICovenantEvents.InvalidCleanDownConfiguration();
    }
    cd[market] = CleanDownState({
      duration: duration,
      interval: interval,
      zeroSince: uint40(block.timestamp),
      lastCleanDown: uint40(block.timestamp)
    });
  }

  /// @dev Credits a streak that has run for at least `duration`.
  function creditMatured(
    mapping(address => CleanDownState) storage cd,
    address market
  ) public returns (bool credited) {
    CleanDownState storage s = cd[market];
    if (s.zeroSince != 0 && block.timestamp - s.zeroSince >= s.duration) {
      s.lastCleanDown = uint40(block.timestamp);
      emit ICovenantEvents.CleanDownCredited(market, block.timestamp);
      return true;
    }
  }

  function onBorrow(
    mapping(address => CleanDownState) storage cd,
    address market,
    uint256 drawnAfter
  ) public {
    CleanDownState storage s = cd[market];
    if (s.duration == 0) return;
    creditMatured(cd, market);
    if (drawnAfter > 0) {
      uint256 dueBy = uint256(s.lastCleanDown) + s.interval;
      if (block.timestamp > dueBy) revert ICovenantEvents.CleanDownOverdue(dueBy);
      if (s.zeroSince != 0) s.zeroSince = 0;
    }
  }

  function onRepay(
    mapping(address => CleanDownState) storage cd,
    address market,
    uint256 drawnAfter
  ) public {
    CleanDownState storage s = cd[market];
    if (s.duration == 0) return;
    creditMatured(cd, market);
    if (s.zeroSince == 0 && drawnAfter == 0) {
      s.zeroSince = uint40(block.timestamp);
      emit ICovenantEvents.CleanDownStreakStarted(market, block.timestamp);
    }
  }

  /// @dev Standing, applying any matured streak virtually.
  function status(
    mapping(address => CleanDownState) storage cd,
    address market
  ) public view returns (bool enabled, bool overdue, uint256 dueBy, uint256 zeroSince) {
    CleanDownState storage s = cd[market];
    enabled = s.duration > 0;
    if (!enabled) return (false, false, 0, 0);
    uint256 last = s.lastCleanDown;
    if (s.zeroSince != 0 && block.timestamp - s.zeroSince >= s.duration) last = block.timestamp;
    dueBy = last + s.interval;
    overdue = block.timestamp > dueBy;
    zeroSince = s.zeroSince;
  }
}

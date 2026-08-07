// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantEvents.sol';

struct CleanDownState {
  uint32 duration;
  uint32 interval;
  uint40 zeroSince;
  uint40 lastCleanDown;
  uint128 thresholdFloor;
}

/**
 * @title CleanDownLib
 * @dev Body of the clean-down covenant, as an external library. `public`
 *      functions are reached by `DELEGATECALL`, so this code lives at its own
 *      address and does not count against the inheriting template's EIP-170
 *      limit. State arrives as a storage pointer and is mutated in place.
 *
 *      "Clean" means drawn at or below a de minimis threshold rather than
 *      exactly zero, because exact zero is not a stable target on a live
 *      market: interest and protocol fees accrue continuously, so a facility
 *      repaid to the wei is a wei short one block later, and a covenant that
 *      fails on fee drift rather than credit behaviour is measuring the wrong
 *      thing. The threshold has two parts, and the covenant takes the larger:
 *      a floor of one tenth of a token in the market asset's own decimals,
 *      and one clean-down window's expected carry, the interest plus protocol
 *      fee that outstanding supply accrues over `duration`. The floor
 *      absorbs rounding on small markets; the carry term scales with exactly
 *      the thing that causes the drift. Both are economically de minimis
 *      against any real facility, and the threshold is derived rather than
 *      configured, so it is not a lever anyone can set generously.
 */
library CleanDownLib {
  function init(
    mapping(address => CleanDownState) storage cd,
    address market,
    address asset,
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
      lastCleanDown: uint40(block.timestamp),
      thresholdFloor: _tenthOfAToken(asset)
    });
  }

  /// @dev One tenth of a token in the asset's own decimals; assets that
  ///      don't report decimals are treated as 18-decimal.
  function _tenthOfAToken(address asset) private view returns (uint128) {
    uint8 decimals = 18;
    (bool ok, bytes memory ret) = asset.staticcall(abi.encodeWithSignature('decimals()'));
    if (ok && ret.length >= 32) decimals = abi.decode(ret, (uint8));
    return uint128(10 ** uint256(decimals) / 10);
  }

  /// @dev The live clean threshold: the larger of the stored floor and one
  ///      window's expected carry on `supply` at the fee-inclusive rate.
  function cleanThreshold(
    CleanDownState storage s,
    uint256 supply,
    uint256 annualInterestBips,
    uint256 protocolFeeBips
  ) public view returns (uint256) {
    uint256 carry = (supply * annualInterestBips * (10_000 + protocolFeeBips) * s.duration) /
      (10_000 * 10_000 * 365 days);
    uint256 floor_ = s.thresholdFloor;
    return carry > floor_ ? carry : floor_;
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
    uint256 drawnAfter,
    uint256 threshold
  ) public {
    CleanDownState storage s = cd[market];
    if (s.duration == 0) return;
    creditMatured(cd, market);
    if (drawnAfter > threshold) {
      uint256 dueBy = uint256(s.lastCleanDown) + s.interval;
      if (block.timestamp > dueBy) revert ICovenantEvents.CleanDownOverdue(dueBy);
      if (s.zeroSince != 0) s.zeroSince = 0;
    }
  }

  function onRepay(
    mapping(address => CleanDownState) storage cd,
    address market,
    uint256 drawnAfter,
    uint256 threshold
  ) public {
    CleanDownState storage s = cd[market];
    if (s.duration == 0) return;
    creditMatured(cd, market);
    if (s.zeroSince == 0 && drawnAfter <= threshold) {
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

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantEvents.sol';

struct TimelockConfig {
  uint128 threshold; // unannounced drawn-increase headroom per window
  uint32 delay; // announce-to-executable, seconds; 0 disables
  uint32 grace; // executable window length
}

struct TimelockState {
  uint40 baselineTime;
  uint128 drawnBaseline;
  uint64 nextNonce;
  uint64 nextConsumable;
}

struct Announcement {
  uint128 amount;
  uint40 executableAt;
  uint40 expiresAt;
}

/**
 * @title DrawTimelockLib
 * @dev Body of the draw timelock covenant, as an external library reached by
 *      `DELEGATECALL`.
 *
 *      The covenant converts lender discomfort into exit opportunity: draws
 *      above a headroom threshold must be announced at least `delay` seconds
 *      in advance, and `delay` is required at market creation to be no shorter
 *      than the market's withdrawal batch duration, so any lender who dislikes
 *      an announced draw can be fully out before it executes.
 *
 *      The headroom is CUMULATIVE per rolling window, not per draw. A per-draw
 *      threshold is splittable: twenty sub-threshold draws in one block
 *      extract the same amount a single announced draw would have delayed. So
 *      the covenant tracks a drawn baseline that rolls forward once per
 *      `delay` period, and gates any draw taking the drawn amount more than
 *      `threshold` above that baseline. Within any window of length `delay`,
 *      unannounced net new drawing cannot exceed `threshold`.
 *
 *      Announcements are keyed (market, nonce) and consumed in nonce order,
 *      skipping expired ones. Each has a tight execution window
 *      [executableAt, executableAt + grace]: without expiry, a borrower could
 *      pre-position ripe announcements indefinitely and the delay would
 *      protect nobody. Pending announcements are capped so consumption stays
 *      bounded on the borrow path.
 */
library DrawTimelockLib {
  uint256 internal constant MAX_PENDING_ANNOUNCEMENTS = 16;

  function init(
    mapping(address => TimelockConfig) storage configs,
    mapping(address => TimelockState) storage states,
    address market,
    uint128 threshold,
    uint32 delay_,
    uint32 grace,
    uint32 withdrawalBatchDuration
  ) public {
    if (delay_ == 0) return; // covenant disabled
    if (delay_ < withdrawalBatchDuration || grace == 0 || threshold == 0) {
      revert ICovenantEvents.InvalidTimelockConfiguration();
    }
    configs[market] = TimelockConfig({ threshold: threshold, delay: delay_, grace: grace });
    states[market] = TimelockState({
      baselineTime: uint40(block.timestamp),
      drawnBaseline: 0,
      nextNonce: 0,
      nextConsumable: 0
    });
  }

  function announce(
    mapping(address => TimelockConfig) storage configs,
    mapping(address => TimelockState) storage states,
    mapping(address => mapping(uint256 => Announcement)) storage announcements,
    address market,
    uint128 amount
  ) public returns (uint256 nonce) {
    TimelockConfig storage cfg = configs[market];
    if (cfg.delay == 0) revert ICovenantEvents.InvalidTimelockConfiguration();
    TimelockState storage st = states[market];
    if (st.nextNonce - st.nextConsumable >= MAX_PENDING_ANNOUNCEMENTS) {
      // walk the pointer over anything expired before refusing
      _skipExpired(states, announcements, market);
      if (st.nextNonce - st.nextConsumable >= MAX_PENDING_ANNOUNCEMENTS) {
        revert ICovenantEvents.InvalidTimelockConfiguration();
      }
    }
    nonce = st.nextNonce++;
    uint40 executableAt = uint40(block.timestamp + cfg.delay);
    uint40 expiresAt = executableAt + cfg.grace;
    announcements[market][nonce] = Announcement({
      amount: amount,
      executableAt: executableAt,
      expiresAt: expiresAt
    });
    emit ICovenantEvents.DrawAnnounced(market, nonce, amount, executableAt, expiresAt);
  }

  /// @dev Gate for `onBorrow`. Draws that keep the drawn amount within
  ///      baseline + threshold pass; anything above needs a ripe, unexpired
  ///      announcement covering the full draw amount, which is consumed.
  function checkOnBorrow(
    mapping(address => TimelockConfig) storage configs,
    mapping(address => TimelockState) storage states,
    mapping(address => mapping(uint256 => Announcement)) storage announcements,
    address market,
    uint256 drawnBefore,
    uint256 drawnAfter
  ) public {
    TimelockConfig storage cfg = configs[market];
    if (cfg.delay == 0) return;
    if (drawnAfter <= drawnBefore) return; // over-repayment reclaim, never gated

    TimelockState storage st = states[market];
    // roll the unannounced-headroom window forward
    if (block.timestamp >= uint256(st.baselineTime) + cfg.delay) {
      st.baselineTime = uint40(block.timestamp);
      st.drawnBaseline = uint128(drawnBefore);
    }
    if (drawnAfter <= uint256(st.drawnBaseline) + cfg.threshold) return;

    uint256 drawAmount = drawnAfter - drawnBefore;
    uint64 i = st.nextConsumable;
    uint64 end = st.nextNonce;
    while (i < end) {
      Announcement storage a = announcements[market][i];
      if (block.timestamp > a.expiresAt) {
        delete announcements[market][i];
        i++;
        continue;
      }
      if (block.timestamp < a.executableAt) {
        st.nextConsumable = i;
        revert ICovenantEvents.AnnouncementNotRipe(a.executableAt);
      }
      if (a.amount < drawAmount) {
        // ripe but too small: an announced draw covers one draw up to its
        // amount, and partial cover would let unannounced volume ride along
        st.nextConsumable = i;
        revert ICovenantEvents.DrawRequiresAnnouncement(cfg.threshold);
      }
      delete announcements[market][i];
      st.nextConsumable = i + 1;
      // lenders had notice of this draw; open a fresh window at the new level
      st.baselineTime = uint40(block.timestamp);
      st.drawnBaseline = uint128(drawnAfter);
      emit ICovenantEvents.AnnouncedDrawConsumed(market, i);
      return;
    }
    st.nextConsumable = i;
    revert ICovenantEvents.DrawRequiresAnnouncement(cfg.threshold);
  }

  function _skipExpired(
    mapping(address => TimelockState) storage states,
    mapping(address => mapping(uint256 => Announcement)) storage announcements,
    address market
  ) internal {
    TimelockState storage st = states[market];
    uint64 i = st.nextConsumable;
    uint64 end = st.nextNonce;
    while (i < end && block.timestamp > announcements[market][i].expiresAt) {
      delete announcements[market][i];
      i++;
    }
    st.nextConsumable = i;
  }

  function pendingAnnouncement(
    mapping(address => mapping(uint256 => Announcement)) storage announcements,
    address market,
    uint256 nonce
  ) public view returns (Announcement memory) {
    return announcements[market][nonce];
  }
}

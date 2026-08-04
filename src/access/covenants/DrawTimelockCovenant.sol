// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './lib/DrawTimelockLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title DrawTimelockCovenant
 * @dev Material-adverse-change substitute for open-term markets. Draws above a
 *      cumulative headroom threshold must be announced `delay` seconds ahead,
 *      with `delay` at least the market's withdrawal batch duration, so a
 *      lender who dislikes an announced draw can be fully out before the money
 *      moves. No approver exists, so nothing is compellable: the draw proceeds
 *      against whatever capital voluntarily stayed.
 *
 *      Open-term hosts only. On a periodic market a fixed delay in seconds no
 *      longer implies exit opportunity, and on a fixed-term market a timelock
 *      giving notice to lenders who cannot exit protects nobody. The delay
 *      floor is checked against `withdrawalBatchDuration` at market creation.
 *
 *      Announcing is borrower-only: announcements consume shared headroom
 *      state, and each emitted `DrawAnnounced` is a signal lenders act on.
 *
 *      This mixin owns storage and surface; bodies live in `DrawTimelockLib`
 *      via `DELEGATECALL`. Inheriting `ICovenantEvents` keeps events and
 *      errors in the template ABI.
 */
abstract contract DrawTimelockCovenant is CovenantBase, ICovenantEvents {
  /// @dev Host requirement: the borrower this instance is bound to.
  function _timelockBorrower() internal view virtual returns (address);

  /// @dev Host requirement: the earliest timestamp by which a lender who
  ///      learns of an announcement at `from` is guaranteed to be able to
  ///      complete an exit. Open-term hosts return `from`, since a delay of
  ///      at least the batch duration already covers it. Hosts with scheduled
  ///      exit (periodic windows) return the end of the first full window
  ///      after `from` plus the batch duration, so even a lender who needs
  ///      the whole window to react is out before the draw can execute.
  function _timelockExitFloor(
    address market,
    uint256 from,
    uint32 batchDuration
  ) internal view virtual returns (uint256);

  mapping(address => TimelockConfig) internal _timelockConfig;
  mapping(address => TimelockState) internal _timelockState;
  mapping(address => mapping(uint256 => Announcement)) internal _announcements;

  function _initDrawTimelockCovenant(
    address market,
    uint128 threshold,
    uint32 delay_,
    uint32 grace,
    uint32 withdrawalBatchDuration
  ) internal {
    DrawTimelockLib.init(
      _timelockConfig,
      _timelockState,
      market,
      threshold,
      delay_,
      grace,
      withdrawalBatchDuration
    );
  }

  /// @notice Announce a draw of up to `amount` on `market`. Executable after
  ///         the market's delay, for the length of its grace window.
  function announceDraw(address market, uint128 amount) external returns (uint256 nonce) {
    if (msg.sender != _timelockBorrower()) revert CallerNotCovenantBorrower();
    uint256 exitFloor = _timelockExitFloor(
      market,
      block.timestamp,
      _timelockConfig[market].batchDuration
    );
    return
      DrawTimelockLib.announce(
        _timelockConfig,
        _timelockState,
        _announcements,
        market,
        amount,
        exitFloor
      );
  }

  /// @dev Called from `onBorrow` with the predicted drawn transition. The
  ///      baseline exit floor keeps the unannounced-headroom window honest on
  ///      scheduled-exit hosts; see `checkOnBorrow` in the library.
  function _drawTimelockOnBorrow(uint256 drawnBefore, uint256 drawnAfter) internal {
    uint256 baselineExitFloor = _timelockExitFloor(
      msg.sender,
      _timelockState[msg.sender].baselineTime,
      _timelockConfig[msg.sender].batchDuration
    );
    DrawTimelockLib.checkOnBorrow(
      _timelockConfig,
      _timelockState,
      _announcements,
      msg.sender,
      drawnBefore,
      drawnAfter,
      baselineExitFloor
    );
  }

  function getTimelockConfig(address market) external view returns (TimelockConfig memory) {
    return _timelockConfig[market];
  }

  function getAnnouncement(
    address market,
    uint256 nonce
  ) external view returns (Announcement memory) {
    return DrawTimelockLib.pendingAnnouncement(_announcements, market, nonce);
  }
}

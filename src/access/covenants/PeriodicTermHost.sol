// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../../libraries/MarketState.sol';

/**
 * @title PeriodicTermHost
 * @dev Host-behaviour mixin: withdrawals can only be queued inside recurring
 *      scheduled windows. The window arithmetic is a line-for-line mirror of
 *      `PeriodicTermHooks`, and has to stay one: the draw timelock's exit
 *      guarantee is computed from this schedule, so a drifted copy would let
 *      draws execute before objecting lenders could leave.
 *
 *      Like `FixedTermHost`, this is host behaviour rather than a covenant:
 *      no library, errors and events declared here so the shared
 *      `ICovenantEvents` file (and with it every covenant library's CREATE2
 *      address) stays untouched.
 *
 *      The APR-reduction proposal machinery of `PeriodicTermHooks` is not
 *      carried over. It's an owner surface unrelated to withdrawal gating,
 *      and covenant hosts ship with as few of those as possible.
 */
abstract contract PeriodicTermHost {
  event PeriodicTermSet(
    address indexed market,
    uint32 firstWithdrawalWindowStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration
  );
  error InvalidPeriodicTerm();
  error WithdrawOutsideWindow();

  uint32 public constant MinimumPeriodDuration = 6 minutes;
  uint32 public constant MaximumPeriodDuration = 365 days;
  uint32 public constant MinimumWithdrawalWindowDuration = 1 minutes;
  uint32 public constant MaximumInitialWithdrawalWindowDelay = MaximumPeriodDuration;

  struct PeriodicTerm {
    uint32 firstWithdrawalWindowStart;
    uint32 periodDuration;
    uint32 withdrawalWindowDuration;
  }

  mapping(address => PeriodicTerm) internal _periodicTerm;

  function _initPeriodicTermHost(
    address market,
    uint32 firstWithdrawalWindowStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration
  ) internal {
    if (
      periodDuration < MinimumPeriodDuration ||
      periodDuration > MaximumPeriodDuration ||
      withdrawalWindowDuration < MinimumWithdrawalWindowDuration ||
      withdrawalWindowDuration >= periodDuration ||
      firstWithdrawalWindowStart < block.timestamp ||
      (firstWithdrawalWindowStart - block.timestamp) > MaximumInitialWithdrawalWindowDelay
    ) {
      revert InvalidPeriodicTerm();
    }
    _periodicTerm[market] = PeriodicTerm({
      firstWithdrawalWindowStart: firstWithdrawalWindowStart,
      periodDuration: periodDuration,
      withdrawalWindowDuration: withdrawalWindowDuration
    });
    emit PeriodicTermSet(
      market,
      firstWithdrawalWindowStart,
      periodDuration,
      withdrawalWindowDuration
    );
  }

  /// @dev Mirror of `PeriodicTermHooks._isWithdrawalWindowOpen`.
  function _isWindowOpen(address market, uint256 timestamp) internal view returns (bool) {
    PeriodicTerm storage t = _periodicTerm[market];
    if (timestamp < t.firstWithdrawalWindowStart) return false;
    uint256 timeInPeriod = (timestamp - t.firstWithdrawalWindowStart) % t.periodDuration;
    return timeInPeriod < t.withdrawalWindowDuration;
  }

  /// @dev Mirror of `PeriodicTermHooks._getNextWithdrawalWindowStart`.
  function _nextWindowStartAfter(
    address market,
    uint256 timestamp
  ) internal view returns (uint256 windowStart) {
    PeriodicTerm storage t = _periodicTerm[market];
    if (timestamp < t.firstWithdrawalWindowStart) {
      return t.firstWithdrawalWindowStart;
    }
    uint256 periodsElapsed = (timestamp - t.firstWithdrawalWindowStart) / t.periodDuration;
    return t.firstWithdrawalWindowStart + ((periodsElapsed + 1) * t.periodDuration);
  }

  /// @dev Wire into `_beforeQueueWithdrawal`. Closed markets always pass.
  function _periodicBeforeQueueWithdrawal(
    address market,
    MarketState calldata state
  ) internal view {
    if (!state.isClosed && !_isWindowOpen(market, block.timestamp)) {
      revert WithdrawOutsideWindow();
    }
  }

  function isWithdrawalWindowOpen(address market) external view returns (bool) {
    return _isWindowOpen(market, block.timestamp);
  }

  function nextWithdrawalWindowStart(
    address market,
    uint256 from
  ) external view returns (uint256) {
    return _nextWindowStartAfter(market, from);
  }

  function getPeriodicTerm(address market) external view returns (PeriodicTerm memory) {
    return _periodicTerm[market];
  }
}

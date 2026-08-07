// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './WatchedMarketsBase.sol';
import './lib/CrossMarketGateLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title CrossMarketDelinquencyCovenant
 * @dev On-chain analogue of a cross-default clause: draws revert while the
 *      borrower is delinquent on any of their other wildcat markets.
 *
 *      This mixin owns the storage and the external surface. The bodies live
 *      in `CrossMarketGateLib`, an external library reached by `DELEGATECALL`,
 *      so they do not count against the inheriting template's EIP-170 limit.
 *      Storage is passed as pointers and mutated in place, so behaviour is
 *      identical to an inlined implementation.
 *
 *      Events and errors are declared in `ICovenantEvents` and shared with the
 *      library, so moving a body across the boundary does not change the
 *      template's ABI.
 *
 *      The watch-list is permissionless: anyone may add a market registered
 *      with the archcontroller that reports this instance's borrower, and
 *      anyone may prune a closed market. It is capped because the gate
 *      iterates it on the borrow path.
 *
 *      `penaltyOnly` is the softer and generally more appropriate setting:
 *      strict delinquency will drawstop on transient reserve dips that cure
 *      themselves within the grace period.
 */
abstract contract CrossMarketDelinquencyCovenant is CovenantBase, WatchedMarketsBase {
  mapping(address => CrossMarketGateConfig) internal _gateConfig;

  function _initCrossMarketCovenant(address market, bool enabled, bool penaltyOnly) internal {
    if (penaltyOnly && !enabled) revert ICovenantEvents.InvalidGateConfiguration();
    _gateConfig[market] = CrossMarketGateConfig({ enabled: enabled, penaltyOnly: penaltyOnly });
    CrossMarketGateLib.watch(_watchedMarkets, isWatchedMarket, market);
  }

  /// @dev Called from `onBorrow`. The calling market is checked through the
  ///      `intermediateState` handed to the hook, never `currentState()`,
  ///      which is reentrancy-guarded while the borrow path holds the lock.
  function _crossMarketOnBorrow(MarketState calldata selfState) internal view {
    CrossMarketGateLib.checkOnBorrow(
      _watchedMarkets,
      _gateConfig[msg.sender],
      selfState,
      msg.sender
    );
  }

  function getCrossMarketGateConfig(
    address market
  ) external view returns (CrossMarketGateConfig memory) {
    return _gateConfig[market];
  }

  /// @notice Preview: the first watched market that would block a draw on
  ///         `market`, or the zero address. External preview only, since it
  ///         queries `currentState()` on every watched market.
  function firstBlockingMarket(address market) external view returns (address) {
    return CrossMarketGateLib.firstBlocking(_watchedMarkets, _gateConfig[market]);
  }
}

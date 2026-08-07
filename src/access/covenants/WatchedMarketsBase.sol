// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './lib/CrossMarketGateLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title WatchedMarketsBase
 * @dev Shared watch-list infrastructure for cross-market covenants. The
 *      delinquency gate and the aggregate exposure cap both iterate the same
 *      list of the borrower's other markets, so the list lives here and the
 *      covenants inherit it. A template inheriting both gets exactly one copy
 *      of the storage and one external surface, courtesy of Solidity's
 *      linearisation.
 *
 *      The list is permissionless in both directions: anyone may add a market
 *      that is registered with the archcontroller and reports this
 *      instance's borrower, and anyone may prune a closed market. It is
 *      capped at `MAX_WATCHED_MARKETS` because covenants iterate it on the
 *      borrow path.
 *
 *      The add and prune bodies stay in `CrossMarketGateLib`, deliberately.
 *      Moving them would change that library's bytecode and with it the
 *      CREATE2 address the shipped gate is linked against, for zero
 *      behavioural gain.
 */
abstract contract WatchedMarketsBase is ICovenantEvents {
  /// @dev Host requirements, shared by every cross-market covenant. A
  ///      concrete template must supply the borrower it is bound to and an
  ///      archcontroller to verify market addresses against.
  function _covenantBorrower() internal view virtual returns (address);

  function _covenantArchController() internal view virtual returns (address);

  address[] internal _watchedMarkets;
  mapping(address => bool) public isWatchedMarket;

  /// @notice Permissionlessly add one of the borrower's markets to the watch-list.
  function watchMarket(address market) external {
    CrossMarketGateLib.watchExternal(
      _watchedMarkets,
      isWatchedMarket,
      market,
      _covenantArchController(),
      _covenantBorrower()
    );
  }

  /// @notice Permissionlessly remove a closed market from the watch-list.
  function unwatchClosedMarket(address market) external {
    CrossMarketGateLib.unwatchClosed(_watchedMarkets, isWatchedMarket, market);
  }

  function getWatchedMarkets() external view returns (address[] memory) {
    return _watchedMarkets;
  }
}

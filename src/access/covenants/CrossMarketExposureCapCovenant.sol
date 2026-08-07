// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './WatchedMarketsBase.sol';
import './lib/CrossMarketCapLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title CrossMarketExposureCapCovenant
 * @dev The incurrence-test analogue: a ceiling on the borrower's aggregate
 *      debt across their watched wildcat markets, checked whenever this
 *      market's drawn amount would increase.
 *
 *      Shares `WatchedMarketsBase` with the delinquency gate, so a template
 *      inheriting both carries one watch-list, one add/prune surface, and one
 *      set of host requirements.
 *
 *      Honesty constraint, stated where integrators will read it: the
 *      aggregate is a floor on true exposure, understated by every unwatched
 *      market, and it counts wildcat debt only. It limits concentration
 *      within the protocol; it does not limit leverage. Anyone can tighten
 *      it permissionlessly by watching another of the borrower's markets.
 */
abstract contract CrossMarketExposureCapCovenant is CovenantBase, WatchedMarketsBase {
  mapping(address => uint256) internal _exposureCap;

  /// @dev A cap of zero disables the covenant.
  function _initExposureCapCovenant(address market, uint256 cap) internal {
    _exposureCap[market] = cap;
    if (cap != 0) emit AggregateExposureCapSet(market, cap);
  }

  /// @dev Called from `onBorrow` with the predicted drawn transition.
  function _exposureCapOnBorrow(uint256 drawnBefore, uint256 drawnAfter) internal view {
    CrossMarketCapLib.checkOnBorrow(
      _watchedMarkets,
      _exposureCap[msg.sender],
      msg.sender,
      drawnBefore,
      drawnAfter
    );
  }

  function getExposureCap(address market) external view returns (uint256) {
    return _exposureCap[market];
  }

  /// @notice The aggregate as the covenant currently sees it, `market` at its
  ///         live drawn level. External preview only.
  function currentAggregateExposure(address market) external view returns (uint256) {
    return CrossMarketCapLib.currentAggregate(_watchedMarkets, market);
  }
}

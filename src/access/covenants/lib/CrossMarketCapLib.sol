// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantEvents.sol';

/**
 * @title CrossMarketCapLib
 * @dev Body of the aggregate exposure cap, as an external library reached by
 *      `DELEGATECALL`. Sums the borrower's current debt across the shared
 *      watch-list plus the calling market's predicted post-draw amount, and
 *      reverts if the total would exceed the cap.
 *
 *      The debt metric is uniform in meaning rather than in method: what the
 *      borrower has out. Revolving markets report it natively as
 *      `drawnAmount()`, and for standard markets it is outstanding debt not
 *      covered by assets still in the market, `totalDebts - totalAssets`
 *      floored at zero. Committed-but-undrawn capacity and deposits the
 *      borrower never touched are not exposure and are not counted.
 *
 *      The number this covenant enforces is a floor on the borrower's true
 *      exposure, never a ceiling: any market missing from the watch-list is
 *      simply not counted, and nothing on-chain enumerates a borrower's
 *      markets exhaustively. Describe it as limiting concentration within the
 *      protocol. Anyone can tighten it by watching another market.
 */
library CrossMarketCapLib {
  bytes4 internal constant DRAWN_AMOUNT_SELECTOR = bytes4(keccak256('drawnAmount()'));
  bytes4 internal constant TOTAL_DEBTS_SELECTOR = bytes4(keccak256('totalDebts()'));
  bytes4 internal constant TOTAL_ASSETS_SELECTOR = bytes4(keccak256('totalAssets()'));

  /// @dev Current exposure of one market: drawn where reported natively,
  ///      otherwise debt not covered by assets still in the market. A market
  ///      that reverts throughout counts as zero rather than blocking every
  ///      draw on the facility.
  function debtOf(address market) public view returns (uint256) {
    (bool ok, bytes memory ret) = market.staticcall(
      abi.encodeWithSelector(DRAWN_AMOUNT_SELECTOR)
    );
    if (ok && ret.length >= 32) return abi.decode(ret, (uint256));
    (ok, ret) = market.staticcall(abi.encodeWithSelector(TOTAL_DEBTS_SELECTOR));
    if (!ok || ret.length < 32) return 0;
    uint256 debts = abi.decode(ret, (uint256));
    (ok, ret) = market.staticcall(abi.encodeWithSelector(TOTAL_ASSETS_SELECTOR));
    if (!ok || ret.length < 32) return 0;
    uint256 assets = abi.decode(ret, (uint256));
    return debts > assets ? debts - assets : 0;
  }

  function checkOnBorrow(
    address[] storage watchedMarkets,
    uint256 cap,
    address self,
    uint256 drawnBefore,
    uint256 drawnAfter
  ) public view {
    if (cap == 0) return; // covenant disabled
    if (drawnAfter <= drawnBefore) return; // over-repayment reclaim, never gated
    uint256 aggregate = drawnAfter;
    uint256 n = watchedMarkets.length;
    for (uint256 i; i < n; i++) {
      address m = watchedMarkets[i];
      if (m == self) continue; // self is counted at its predicted level
      aggregate += debtOf(m);
    }
    if (aggregate > cap) {
      revert ICovenantEvents.AggregateExposureExceeded(aggregate, cap);
    }
  }

  /// @dev External preview of the aggregate as the covenant currently sees
  ///      it, with the calling market at its live drawn level.
  function currentAggregate(
    address[] storage watchedMarkets,
    address self
  ) public view returns (uint256 aggregate) {
    aggregate = debtOf(self);
    uint256 n = watchedMarkets.length;
    for (uint256 i; i < n; i++) {
      address m = watchedMarkets[i];
      if (m == self) continue;
      aggregate += debtOf(m);
    }
  }
}

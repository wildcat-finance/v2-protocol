// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../CovenantBase.sol';
import './CovenantEvents.sol';

struct CrossMarketGateConfig {
  bool enabled;
  bool penaltyOnly;
}

/**
 * @title CrossMarketGateLib
 * @dev Body of the cross-market delinquency covenant, as an external library.
 *
 *      `public` library functions are reached by `DELEGATECALL`, so this code
 *      lives at its own address and does not count against the inheriting
 *      template's EIP-170 limit. Storage is the template's: mappings and arrays
 *      arrive as storage pointers and are read and written in place.
 *
 *      Templates are compiled against a fixed CREATE2 address, so the deploy
 *      stays single-phase. Addresses and salts live in `CovenantLibraries.sol`;
 *      `foundry.toml` needs the matching `libraries` entry.
 */
library CrossMarketGateLib {
  uint256 internal constant MAX_WATCHED_MARKETS = 30;

  function watch(
    address[] storage watched,
    mapping(address => bool) storage isWatched,
    address market
  ) public {
    if (isWatched[market]) revert ICovenantEvents.MarketAlreadyWatched();
    if (watched.length >= MAX_WATCHED_MARKETS) revert ICovenantEvents.WatchListFull();
    isWatched[market] = true;
    watched.push(market);
    emit ICovenantEvents.MarketWatched(market);
  }

  function watchExternal(
    address[] storage watched,
    mapping(address => bool) storage isWatched,
    address market,
    address archController,
    address borrower
  ) public {
    if (
      !ICovenantMarketRegistry(archController).isRegisteredMarket(market) ||
      ICovenantMarket(market).borrower() != borrower
    ) {
      revert ICovenantEvents.NotBorrowerMarket();
    }
    watch(watched, isWatched, market);
  }

  function unwatchClosed(
    address[] storage watched,
    mapping(address => bool) storage isWatched,
    address market
  ) public {
    if (!isWatched[market]) revert ICovenantEvents.MarketNotWatched();
    if (!ICovenantMarket(market).currentState().isClosed) {
      revert ICovenantEvents.MarketNotClosed();
    }
    isWatched[market] = false;
    uint256 length = watched.length;
    for (uint256 i; i < length; i++) {
      if (watched[i] == market) {
        watched[i] = watched[length - 1];
        watched.pop();
        break;
      }
    }
    emit ICovenantEvents.MarketUnwatched(market);
  }

  /**
   * @dev Reverts if the borrower is delinquent on the calling market or any
   *      watched market. The caller passes its own state rather than letting
   *      this read `currentState()`, which is reentrancy-guarded while the
   *      borrow path holds the lock.
   */
  function checkOnBorrow(
    address[] storage watched,
    CrossMarketGateConfig memory config,
    MarketState memory selfState,
    address self
  ) public view {
    if (!config.enabled) return;
    if (isDelinquentForGate(selfState, self, config.penaltyOnly)) {
      revert ICovenantEvents.BorrowerDelinquentOnMarket(self);
    }
    uint256 length = watched.length;
    for (uint256 i; i < length; i++) {
      address market = watched[i];
      if (market == self) continue;
      MarketState memory state = ICovenantMarket(market).currentState();
      if (state.isClosed) continue;
      if (isDelinquentForGate(state, market, config.penaltyOnly)) {
        revert ICovenantEvents.BorrowerDelinquentOnMarket(market);
      }
    }
  }

  function firstBlocking(
    address[] storage watched,
    CrossMarketGateConfig memory config
  ) public view returns (address) {
    if (!config.enabled) return address(0);
    uint256 length = watched.length;
    for (uint256 i; i < length; i++) {
      address m = watched[i];
      MarketState memory state = ICovenantMarket(m).currentState();
      if (state.isClosed) continue;
      if (isDelinquentForGate(state, m, config.penaltyOnly)) return m;
    }
    return address(0);
  }

  function isDelinquentForGate(
    MarketState memory state,
    address market,
    bool penaltyOnly
  ) public view returns (bool) {
    if (penaltyOnly) {
      return state.timeDelinquent > ICovenantMarket(market).delinquencyGracePeriod();
    }
    return state.isDelinquent || state.timeDelinquent > 0;
  }
}

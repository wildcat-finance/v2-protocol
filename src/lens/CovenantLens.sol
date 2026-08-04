// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Compiles clean. No dedicated test suite yet: a lens test needs a fixture,
// and this contract is read-only, holds no state and is referenced by no
// contract in scope, so it cannot affect market behaviour.

import '../types/HooksConfig.sol';
import '../access/IHooks.sol';
import '../market/WildcatMarket.sol';
import '../libraries/MarketState.sol';
import '../libraries/RevolvingDrawnMath.sol';
import { RevolvingCovenantHooks } from '../access/RevolvingCovenantHooks.sol';
import { CleanDownState } from '../access/covenants/CleanDownCovenant.sol';
import { CrossMarketGateConfig } from '../access/covenants/CrossMarketDelinquencyCovenant.sol';

using MarketStateLib for MarketState;

enum CovenantHooksKind {
  NotCovenant,
  RevolvingCovenant,
  RevolvingCleanDown
}

enum DrawBlockReason {
  None,
  MarketClosed,
  InsufficientLiquidity,
  CleanDownOverdue,
  CrossMarketDelinquency
}

struct CleanDownLensData {
  bool enabled;
  uint32 duration;
  uint32 interval;
  bool overdue;
  uint256 dueBy;
  uint256 zeroSince;
  uint256 secondsUntilDue; // 0 when overdue or disabled
  uint256 secondsUntilStreakMatures; // 0 when drawn, matured, or disabled
}

struct CrossMarketGateLensData {
  bool supported; // false on templates without the gate compiled in
  bool enabled;
  bool penaltyOnly;
  address firstBlockingMarket;
  address[] watchedMarkets;
}

struct MarketCovenantData {
  address market;
  address hooksInstance;
  CovenantHooksKind kind;
  uint256 drawnAmount;
  uint256 borrowableAssets;
  CleanDownLensData cleanDown;
  CrossMarketGateLensData gate;
  bool drawBlocked;
  DrawBlockReason blockReason;
  address blockingMarket; // populated only for CrossMarketDelinquency
}

/**
 * @title CovenantLens
 * @dev Read-only surface for covenant-bearing revolving markets. Deliberately
 *      separate from `MarketLens`: folding covenant fields into
 *      `MarketHooksData` or appending to `HooksInstanceKind` would change an
 *      ABI that existing consumers depend on.
 *
 *      Every query degrades gracefully on non-covenant markets, returning
 *      `NotCovenant` rather than reverting, so a caller can pass any market.
 */
contract CovenantLens {
  function kindForVersion(string memory version) public pure returns (CovenantHooksKind) {
    bytes32 h = keccak256(bytes(version));
    if (h == keccak256('RevolvingCovenantHooks')) return CovenantHooksKind.RevolvingCovenant;
    if (h == keccak256('RevolvingCleanDownHooks')) return CovenantHooksKind.RevolvingCleanDown;
    return CovenantHooksKind.NotCovenant;
  }

  function getMarketCovenantData(
    address marketAddress
  ) public view returns (MarketCovenantData memory data) {
    data.market = marketAddress;
    WildcatMarket market = WildcatMarket(marketAddress);
    data.hooksInstance = market.hooks().hooksAddress();
    if (data.hooksInstance == address(0)) return data;

    data.kind = kindForVersion(IHooks(data.hooksInstance).version());
    if (data.kind == CovenantHooksKind.NotCovenant) return data;

    MarketState memory state = market.currentState();
    data.borrowableAssets = market.borrowableAssets();
    data.drawnAmount = _drawnAmount(marketAddress);

    _fillCleanDown(data, marketAddress);
    if (data.kind == CovenantHooksKind.RevolvingCovenant) {
      _fillGate(data, marketAddress);
    }

    // Standing block state, evaluated as if a marginal draw were attempted.
    if (state.isClosed) {
      data.drawBlocked = true;
      data.blockReason = DrawBlockReason.MarketClosed;
    } else if (data.cleanDown.overdue) {
      data.drawBlocked = true;
      data.blockReason = DrawBlockReason.CleanDownOverdue;
    } else if (data.gate.firstBlockingMarket != address(0)) {
      data.drawBlocked = true;
      data.blockReason = DrawBlockReason.CrossMarketDelinquency;
      data.blockingMarket = data.gate.firstBlockingMarket;
    }
  }

  function getMarketsCovenantData(
    address[] calldata markets
  ) external view returns (MarketCovenantData[] memory data) {
    data = new MarketCovenantData[](markets.length);
    for (uint256 i; i < markets.length; i++) data[i] = getMarketCovenantData(markets[i]);
  }

  /**
   * @notice Would a draw of `amount` succeed right now, and if not, why.
   * @dev Mirrors the covenant enforcement order in
   *      `RevolvingCovenantHooks.onBorrow`, including the exemption for draws
   *      that leave the drawn amount at zero: reclaiming an over-repayment is
   *      not credit and is not gated.
   */
  function previewDraw(
    address marketAddress,
    uint256 amount
  ) external view returns (bool allowed, DrawBlockReason reason, address blockingMarket) {
    MarketCovenantData memory data = getMarketCovenantData(marketAddress);
    WildcatMarket market = WildcatMarket(marketAddress);
    MarketState memory state = market.currentState();

    if (state.isClosed) return (false, DrawBlockReason.MarketClosed, address(0));
    if (amount > data.borrowableAssets) {
      return (false, DrawBlockReason.InsufficientLiquidity, address(0));
    }
    if (data.kind == CovenantHooksKind.NotCovenant) {
      return (true, DrawBlockReason.None, address(0));
    }

    uint256 drawnAfter = RevolvingDrawnMath.drawnAfterBorrow(
      data.drawnAmount,
      market.totalAssets(),
      state,
      amount
    );
    if (drawnAfter == 0) return (true, DrawBlockReason.None, address(0));

    if (data.cleanDown.overdue) return (false, DrawBlockReason.CleanDownOverdue, address(0));
    if (data.gate.firstBlockingMarket != address(0)) {
      return (false, DrawBlockReason.CrossMarketDelinquency, data.gate.firstBlockingMarket);
    }
    return (true, DrawBlockReason.None, address(0));
  }

  // ========================================================================== //

  function _drawnAmount(address market) internal view returns (uint256 drawn) {
    (bool ok, bytes memory ret) = market.staticcall(abi.encodeWithSignature('drawnAmount()'));
    if (ok && ret.length >= 32) drawn = abi.decode(ret, (uint256));
  }

  function _fillCleanDown(MarketCovenantData memory data, address market) internal view {
    RevolvingCovenantHooks hooks = RevolvingCovenantHooks(data.hooksInstance);
    (bool enabled, bool overdue, uint256 dueBy, uint256 zeroSince) = hooks.getCleanDownStatus(
      market
    );
    CleanDownState memory raw = hooks.getCleanDownState(market);

    data.cleanDown.enabled = enabled;
    data.cleanDown.duration = raw.duration;
    data.cleanDown.interval = raw.interval;
    data.cleanDown.overdue = overdue;
    data.cleanDown.dueBy = dueBy;
    data.cleanDown.zeroSince = zeroSince;
    if (enabled && !overdue && dueBy > block.timestamp) {
      data.cleanDown.secondsUntilDue = dueBy - block.timestamp;
    }
    if (enabled && zeroSince != 0) {
      uint256 elapsed = block.timestamp - zeroSince;
      if (elapsed < raw.duration) {
        data.cleanDown.secondsUntilStreakMatures = raw.duration - elapsed;
      }
    }
  }

  function _fillGate(MarketCovenantData memory data, address market) internal view {
    RevolvingCovenantHooks hooks = RevolvingCovenantHooks(data.hooksInstance);
    CrossMarketGateConfig memory config = hooks.getCrossMarketGateConfig(market);
    data.gate.supported = true;
    data.gate.enabled = config.enabled;
    data.gate.penaltyOnly = config.penaltyOnly;
    data.gate.watchedMarkets = hooks.getWatchedMarkets();
    if (config.enabled) data.gate.firstBlockingMarket = hooks.firstBlockingMarket(market);
  }
}

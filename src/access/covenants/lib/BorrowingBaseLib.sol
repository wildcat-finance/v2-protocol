// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantEvents.sol';
import { LibERC20 } from '../../../libraries/LibERC20.sol';

struct CollateralConfig {
  address[] tokens;
  uint16[] advanceRatesBips;
}

/**
 * @title BorrowingBaseLib
 * @dev Body of the borrowing base covenant, as an external library reached by
 *      `DELEGATECALL`.
 *
 *      This is the static-haircut variant, and the honest scope of the
 *      endogenous version: collateral tokens are valued at face in the
 *      market's own asset terms, discounted by a per-token advance rate fixed
 *      at market creation. The advance rate is the haircut, exactly as it is
 *      in an asset-based facility; what this version does not do is
 *      re-mark the collateral, so price risk between the tokens and the
 *      asset sits with lenders, priced by the rates they accepted at entry.
 *      Suitable where the tokens track the asset closely. Anything needing a
 *      live price feed is an attested covenant wearing an oracle, and belongs
 *      in that half of the map.
 *
 *      Custody is an internal ledger on the hooks instance: deposits move
 *      tokens in via `transferFrom` and credit the market's ledger, and only
 *      ledger balances count toward the base, so tokens sent directly to the
 *      instance are ignored rather than silently inflating one market's
 *      collateral on an instance several markets share.
 */
library BorrowingBaseLib {
  uint256 internal constant MAX_COLLATERAL_TOKENS = 8;
  uint256 internal constant BIPS = 10_000;

  using LibERC20 for address;

  function init(
    mapping(address => CollateralConfig) storage configs,
    address market,
    address[] memory tokens,
    uint16[] memory advanceRatesBips
  ) public {
    uint256 n = tokens.length;
    if (n == 0) return; // covenant disabled
    if (n != advanceRatesBips.length || n > MAX_COLLATERAL_TOKENS) {
      revert ICovenantEvents.InvalidCollateralConfiguration();
    }
    for (uint256 i; i < n; i++) {
      if (tokens[i] == address(0)) revert ICovenantEvents.InvalidCollateralConfiguration();
      uint16 rate = advanceRatesBips[i];
      if (rate == 0 || rate > BIPS) revert ICovenantEvents.InvalidCollateralConfiguration();
      for (uint256 j; j < i; j++) {
        if (tokens[j] == tokens[i]) revert ICovenantEvents.InvalidCollateralConfiguration();
      }
    }
    CollateralConfig storage c = configs[market];
    c.tokens = tokens;
    c.advanceRatesBips = advanceRatesBips;
    emit ICovenantEvents.CollateralConfigSet(market, tokens, advanceRatesBips);
  }

  function deposit(
    mapping(address => CollateralConfig) storage configs,
    mapping(address => mapping(address => uint256)) storage ledger,
    address market,
    address token,
    uint256 amount
  ) public {
    if (!_isConfiguredToken(configs[market], token)) {
      revert ICovenantEvents.InvalidCollateralConfiguration();
    }
    token.safeTransferFrom(msg.sender, address(this), amount);
    ledger[market][token] += amount;
    emit ICovenantEvents.CollateralDeposited(market, token, msg.sender, amount);
  }

  /// @dev Withdrawal is checked against the base AFTER the withdrawal, at the
  ///      market's live drawn level. Closed markets skip the check: closure
  ///      settles the facility, and stranding collateral past it protects
  ///      nobody.
  function withdraw(
    mapping(address => CollateralConfig) storage configs,
    mapping(address => mapping(address => uint256)) storage ledger,
    address market,
    address token,
    uint256 amount,
    address to,
    uint256 currentDrawn,
    bool marketClosed
  ) public {
    uint256 held = ledger[market][token];
    if (amount > held) revert ICovenantEvents.WithdrawExceedsCollateral();
    ledger[market][token] = held - amount;
    if (!marketClosed) {
      uint256 baseAfter = borrowingBase(configs, ledger, market);
      if (currentDrawn > baseAfter) {
        revert ICovenantEvents.WithdrawalBreachesBase(baseAfter, currentDrawn);
      }
    }
    token.safeTransfer(to, amount);
    emit ICovenantEvents.CollateralWithdrawn(market, token, to, amount);
  }

  function borrowingBase(
    mapping(address => CollateralConfig) storage configs,
    mapping(address => mapping(address => uint256)) storage ledger,
    address market
  ) public view returns (uint256 base) {
    CollateralConfig storage c = configs[market];
    uint256 n = c.tokens.length;
    for (uint256 i; i < n; i++) {
      base += (ledger[market][c.tokens[i]] * c.advanceRatesBips[i]) / BIPS;
    }
  }

  function checkOnBorrow(
    mapping(address => CollateralConfig) storage configs,
    mapping(address => mapping(address => uint256)) storage ledger,
    address market,
    uint256 drawnBefore,
    uint256 drawnAfter
  ) public view {
    if (configs[market].tokens.length == 0) return; // covenant disabled
    if (drawnAfter <= drawnBefore) return; // over-repayment reclaim, never gated
    uint256 base = borrowingBase(configs, ledger, market);
    if (drawnAfter > base) {
      revert ICovenantEvents.BorrowingBaseExceeded(drawnAfter, base);
    }
  }

  function _isConfiguredToken(
    CollateralConfig storage c,
    address token
  ) private view returns (bool) {
    uint256 n = c.tokens.length;
    for (uint256 i; i < n; i++) {
      if (c.tokens[i] == token) return true;
    }
    return false;
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './CovenantBase.sol';
import './lib/BorrowingBaseLib.sol';
import './lib/CovenantEvents.sol';

/**
 * @title BorrowingBaseCovenant
 * @dev Availability capped at eligible collateral times an advance rate:
 *      draws that would take the drawn amount above the borrowing base
 *      revert, and collateral can only be withdrawn down to what keeps the
 *      base at or above the current drawn amount.
 *
 *      Static-haircut variant, on purpose; the library header carries the
 *      full scoping. Per-token advance rates are fixed at market creation
 *      and are the lender-accepted haircuts. No oracle, no re-marking,
 *      nobody to compel.
 *
 *      Anyone may deposit collateral for a market (a donation only raises
 *      the base, which only helps lenders); withdrawal is borrower-only and
 *      base-checked. The ledger is per-market, so several markets on one
 *      hooks instance cannot see each other's collateral.
 */
abstract contract BorrowingBaseCovenant is CovenantBase, ICovenantEvents {
  /// @dev Host requirement: the borrower this instance is bound to.
  function _borrowingBaseBorrower() internal view virtual returns (address);

  mapping(address => CollateralConfig) internal _collateralConfig;
  mapping(address => mapping(address => uint256)) internal _collateralLedger;

  function _initBorrowingBaseCovenant(
    address market,
    address[] memory tokens,
    uint16[] memory advanceRatesBips
  ) internal {
    BorrowingBaseLib.init(_collateralConfig, market, tokens, advanceRatesBips);
  }

  /// @notice Post collateral for `market`. Open to anyone; only configured
  ///         tokens are accepted, and only ledger balances count.
  function depositCollateral(address market, address token, uint256 amount) external {
    BorrowingBaseLib.deposit(_collateralConfig, _collateralLedger, market, token, amount);
  }

  /// @notice Withdraw collateral, borrower only, down to what keeps the base
  ///         covering the drawn amount. Closed markets skip the base check.
  function withdrawCollateral(
    address market,
    address token,
    uint256 amount,
    address to
  ) external {
    if (msg.sender != _borrowingBaseBorrower()) revert CallerNotCovenantBorrower();
    // Not the borrow path: the market holds no reentrancy lock here, so
    // `currentState()` is safe to read for the closure flag.
    ICovenantMarket m = ICovenantMarket(market);
    BorrowingBaseLib.withdraw(
      _collateralConfig,
      _collateralLedger,
      market,
      token,
      amount,
      to,
      _covenantDrawnOf(market),
      m.currentState().isClosed
    );
  }

  /// @dev Called from `onBorrow` with the predicted drawn transition.
  function _borrowingBaseOnBorrow(uint256 drawnBefore, uint256 drawnAfter) internal view {
    BorrowingBaseLib.checkOnBorrow(
      _collateralConfig,
      _collateralLedger,
      msg.sender,
      drawnBefore,
      drawnAfter
    );
  }

  function getCollateralConfig(
    address market
  ) external view returns (address[] memory tokens, uint16[] memory advanceRatesBips) {
    CollateralConfig storage c = _collateralConfig[market];
    return (c.tokens, c.advanceRatesBips);
  }

  function collateralBalance(address market, address token) external view returns (uint256) {
    return _collateralLedger[market][token];
  }

  /// @notice The base as currently posted: sum of ledger balances times
  ///         advance rates.
  function borrowingBase(address market) external view returns (uint256) {
    return BorrowingBaseLib.borrowingBase(_collateralConfig, _collateralLedger, market);
  }
}

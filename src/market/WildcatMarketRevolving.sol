// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WildcatMarketRevolving
//  \ ^ /   Drawn-principal accounting and revolving interest accrual.
//    V
//
//  SETUP
//  constructor()
//
//  PRINCIPAL ACCOUNTING
//  _onBorrow(...)
//  _onRepay(...)
//  _onRepayAndGetTotalAssets(...)
//  _onCloseMarket()
//  _setDrawnAmount(...)
//  drawnAmount()
//
//  INTEREST
//  _calculateBaseInterest(...)
//  commitmentFeeBips()
// ═════

import '../interfaces/IWildcatMarketRevolving.sol';
import './WildcatMarket.sol';

// ┌─ WildcatMarketRevolving ───────────────────────────────────────────────────
/// @title WildcatMarketRevolving
///
/// @notice revolving credit market with commitment interest on full supply and base APR only on
///         the drawn portion.
///
/// @dev explicit repayments reconcile drawn principal. raw token transfers only add liquidity.
contract WildcatMarketRevolving is WildcatMarket, IWildcatMarketRevolving {
  using BoolUtils for bool;
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  uint16 internal immutable _commitmentFeeBips;

  uint256 internal _drawnAmount;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() {
    uint16 commitmentFeeBips_;
    assembly {
      // the deploying factory keeps this fee in transient data until construction finishes.
      // `caller()` is that factory. start at 0x1c to skip the selector word's 28 zero bytes;
      // the four-byte input is `getRevolvingMarketCommitmentFeeBips()` with no arguments.
      mstore(0, 0x0e304343) // getRevolvingMarketCommitmentFeeBips()

      // forward the remaining gas and copy the first return word to scratch memory at 0x00.
      if iszero(staticcall(gas(), caller(), 0x1c, 0x04, 0, 0x20)) {
        // keep the factory's error, not an empty constructor revert.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }

      // uint16 still needs a full 32-byte ABI word. reject short returns and dirty upper bits;
      // shifting by 16 must leave zero, not a value that Solidity would silently truncate.
      if or(lt(returndatasize(), 0x20), shr(16, mload(0))) {
        revert(0, 0)
      }
      commitmentFeeBips_ := mload(0)
    }
    _commitmentFeeBips = commitmentFeeBips_;
  }

  // ░░▒▒▓▓██ [ PRINCIPAL ACCOUNTING ] ─────────────────────────────────────────

  // ┌─ _onBorrow ─────
  /// @dev increase drawn principal only where post-borrow debt exceeds the existing draw.
  ///      recovering previously supplied liquidity isn't a new draw and can't reduce principal.
  ///      `totalAssets()` still includes the amount about to leave.
  function _onBorrow(MarketState memory state, uint256 amount) internal virtual override {
    uint256 assetsAfterBorrow = totalAssets().satSub(amount);
    uint256 outstandingDebt = state.totalDebts().satSub(assetsAfterBorrow);
    uint256 newDrawnAmount = _drawnAmount;
    if (outstandingDebt > newDrawnAmount) {
      uint256 remainingDebt = outstandingDebt - newDrawnAmount;
      newDrawnAmount += MathUtils.min(amount, remainingDebt);
    }
    _setDrawnAmount(newDrawnAmount);
  }

  // ┌─ _onRepay ─────
  /// @dev reconcile drawn principal after the repayment reaches the market.
  function _onRepay(MarketState memory state, uint256 amount) internal virtual override {
    _onRepayAndGetTotalAssets(state, amount);
  }

  // ┌─ _onRepayAndGetTotalAssets ─────
  function _onRepayAndGetTotalAssets(
    MarketState memory state,
    uint256 amount
  )
    internal
    virtual
    override
    returns (uint256 currentTotalAssets)
  {
    currentTotalAssets = totalAssets();

    // only this explicit repayment reduces principal. existing assets may include donations;
    // those add liquidity, not principal repayment.
    uint256 assetsBeforeRepayment = currentTotalAssets.satSub(amount);
    uint256 outstandingDebtBeforeRepayment = state.totalDebts().satSub(assetsBeforeRepayment);
    uint256 nonPrincipalDebt = outstandingDebtBeforeRepayment.satSub(_drawnAmount);
    uint256 principalRepayment = amount.satSub(nonPrincipalDebt);
    _setDrawnAmount(_drawnAmount.satSub(principalRepayment));
  }

  // ┌─ _onCloseMarket ─────
  /// @dev closure settles the facility, so no drawn principal remains.
  function _onCloseMarket() internal virtual override {
    _setDrawnAmount(_runtimeConstant(uint256(0)));
  }

  // ┌─ _setDrawnAmount ─────
  /// @dev store and emit only when drawn principal changes.
  function _setDrawnAmount(uint256 newDrawnAmount) internal {
    uint256 previousDrawnAmount = _drawnAmount;
    if (previousDrawnAmount != newDrawnAmount) {
      _drawnAmount = newDrawnAmount;
      emit_DrawnAmountUpdated(previousDrawnAmount, newDrawnAmount);
    }
  }

  // ┌─ drawnAmount ─────
  /// @inheritdoc IWildcatMarketRevolving
  function drawnAmount() external view override returns (uint256) {
    assembly {
      // `_drawnAmount.slot` holds a full uint256. return that ABI word without masking or shifting.
      mstore(0, sload(_drawnAmount.slot))
      return(0, 0x20)
    }
  }

  // ░░▒▒▓▓██ [ INTEREST ] ─────────────────────────────────────────────────────

  // ┌─ _calculateBaseInterest ─────
  /// @dev revolving base rate:
  ///
  ///      commitmentFee + annualInterest * min(drawnAmount, totalSupply) / totalSupply
  ///
  ///      unlike the standard market, skip accrual when closed or supply is zero.
  ///      otherwise the commitment fee would accrue with no lenders to receive it.
  function _calculateBaseInterest(
    MarketState memory state,
    uint256 timestamp
  )
    internal
    view
    override
    returns (uint256 baseInterestRay)
  {
    uint256 timeDelta;
    unchecked {
      // accrual timestamps only move forward.
      timeDelta = timestamp - state.lastInterestAccruedTimestamp;

      // uint104 supply times the finite timestamp delta fits uint256. this is only a zero check.
      if ((timeDelta * uint256(state.scaledTotalSupply) == 0).or(state.isClosed)) {
        return 0;
      }
    }

    baseInterestRay = MathUtils.calculateLinearInterestFromBips(_commitmentFeeBips, timeDelta);

    uint256 drawn = _drawnAmount;
    uint256 annualInterestBips = state.annualInterestBips;
    unchecked {
      // `annualInterestBips` is uint16 and drawn principal is bounded by
      // market debt, so this product is only used as a compact nonzero check.
      if (annualInterestBips * drawn == 0) return baseInterestRay;

      uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(annualInterestBips, timeDelta);
      uint256 totalSupply = state.totalSupply();
      uint256 drawnClamped = MathUtils.min(drawn, totalSupply);

      // both rates fit uint16; linear accrual over the finite timestamp horizon stays below uint256.
      baseInterestRay += MathUtils.mulDiv(annualInterestRay, drawnClamped, totalSupply);
    }
  }

  // ┌─ commitmentFeeBips ─────
  /// @inheritdoc IWildcatMarketRevolving
  function commitmentFeeBips() external view override returns (uint256 value) {
    value = _commitmentFeeBips;
    assembly {
      mstore(0, value)
      return(0, 0x20)
    }
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import '../interfaces/IWildcatMarketRevolving.sol';
import './WildcatMarket.sol';

/**
 * @title WildcatMarketRevolving
 * @dev Market for revolving credit facilities. Tracks the amount the borrower
 *      has drawn and accrues the commitment fee on the full supply plus the
 *      market APR on the drawn portion only.
 */
contract WildcatMarketRevolving is WildcatMarket, IWildcatMarketRevolving {
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  uint16 internal immutable _commitmentFeeBips;

  uint256 internal _drawnAmount;

  constructor() {
    uint16 commitmentFeeBips_;
    assembly {
      // Read the commitment fee from the factory's transient deployment data.
      mstore(0, 0x0e304343) // getRevolvingMarketCommitmentFeeBips()
      if iszero(staticcall(gas(), caller(), 0x1c, 0x04, 0, 0x20)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      if or(lt(returndatasize(), 0x20), shr(16, mload(0))) {
        revert(0, 0)
      }
      commitmentFeeBips_ := mload(0)
    }
    _commitmentFeeBips = commitmentFeeBips_;
  }

  function commitmentFeeBips() external view override returns (uint256 value) {
    value = _commitmentFeeBips;
    assembly {
      mstore(0, value)
      return(0, 0x20)
    }
  }

  function drawnAmount() external view override returns (uint256) {
    assembly {
      mstore(0, sload(_drawnAmount.slot))
      return(0, 0x20)
    }
  }

  /**
   * @dev Cap the drawn amount at the market's outstanding debt so that
   *      borrowing against assets the borrower provided themselves (e.g.
   *      an earlier over-repayment) does not accrue lender interest.
   *      `totalAssets()` has not yet been reduced by the borrowed amount.
   */
  function _onBorrow(MarketState memory state, uint256 amount) internal virtual override {
    uint256 assetsAfterBorrow = totalAssets().satSub(amount);
    uint256 outstandingDebt = state.totalDebts().satSub(assetsAfterBorrow);
    unchecked {
      // Both values are bounded by market debt, which is well below uint256.
      _setDrawnAmount(MathUtils.min(_drawnAmount + amount, outstandingDebt));
    }
  }

  function _onRepay(MarketState memory state, uint256 amount) internal virtual override {
    _onRepayAndGetTotalAssets(state, amount);
  }

  function _onRepayAndGetTotalAssets(
    MarketState memory state,
    uint256 amount
  ) internal virtual override returns (uint256 currentTotalAssets) {
    amount;
    currentTotalAssets = totalAssets();
    // Repayments reduce the drawn amount to at most the remaining outstanding
    // debt. `currentTotalAssets` includes the repaid amount.
    uint256 outstandingDebt = state.totalDebts().satSub(currentTotalAssets);
    _setDrawnAmount(MathUtils.min(_drawnAmount, outstandingDebt));
  }

  function _onCloseMarket() internal virtual override {
    _setDrawnAmount(_runtimeConstant(uint256(0)));
  }

  function _setDrawnAmount(uint256 newDrawnAmount) internal {
    uint256 previousDrawnAmount = _drawnAmount;
    if (previousDrawnAmount != newDrawnAmount) {
      _drawnAmount = newDrawnAmount;
      emit_DrawnAmountUpdated(previousDrawnAmount, newDrawnAmount);
    }
  }

  /**
   * @dev Base interest rate for a revolving market:
   *
   *      commitmentFee + annualInterest * min(drawnAmount, totalSupply) / totalSupply
   *
   *      Unlike the standard market, no interest accrues while the market is
   *      closed or has no supply, as the commitment fee would otherwise
   *      accrue with no lenders to owe it to.
   */
  function _calculateRevolvingBaseInterest(
    MarketState memory state,
    uint256 timestamp
  ) internal view returns (uint256 baseInterestRay) {
    uint256 timeDelta;
    unchecked {
      // Accrual timestamps only move forward.
      timeDelta = timestamp - state.lastInterestAccruedTimestamp;
      // `scaledTotalSupply` is uint104, so the product cannot overflow within
      // the market's finite timestamp horizon. It is only a compact zero check.
      if (timeDelta * uint256(state.scaledTotalSupply) == 0 || state.isClosed) {
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

      uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(
        annualInterestBips,
        timeDelta
      );
      uint256 totalSupply = state.totalSupply();
      uint256 drawnClamped = MathUtils.min(drawn, totalSupply);
      // Both rates are bounded uint16 values, so their linear interest cannot
      // approach uint256 over the market's finite timestamp horizon.
      baseInterestRay += MathUtils.mulDiv(annualInterestRay, drawnClamped, totalSupply);
    }
  }

  /// @dev Identical to `FeeMath.updateScaleFactorAndFees` except that the
  ///      base interest rate uses the revolving calculation above.
  function _updateScaleFactorAndFees(
    MarketState memory state,
    uint256 timestamp
  )
    internal
    view
    virtual
    override
    returns (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee)
  {
    baseInterestRay = _calculateRevolvingBaseInterest(state, timestamp);

    if (state.protocolFeeBips > 0) {
      protocolFee = state.applyProtocolFee(baseInterestRay);
    }

    if (delinquencyFeeBips > 0) {
      delinquencyFeeRay = state.updateDelinquency(
        timestamp,
        delinquencyFeeBips,
        delinquencyGracePeriod
      );
    }

    uint256 prevScaleFactor = state.scaleFactor;
    uint256 scaleFactorDelta = prevScaleFactor.rayMul(baseInterestRay + delinquencyFeeRay);

    // The checked cast deliberately reverts at the accepted finite uint112
    // scale-factor horizon rather than truncating. See MarketState and Known Issues.
    state.scaleFactor = (prevScaleFactor + scaleFactorDelta).toUint112();
    state.lastInterestAccruedTimestamp = uint32(timestamp);
  }
}

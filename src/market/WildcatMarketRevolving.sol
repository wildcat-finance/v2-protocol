// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import '../IHooksFactoryRevolving.sol';
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

  uint128 internal _drawnAmount;

  constructor() {
    // Read the commitment fee from the factory's transient deployment data.
    _commitmentFeeBips = IHooksFactoryRevolving(msg.sender).getRevolvingMarketCommitmentFeeBips();
  }

  function commitmentFeeBips() external view override returns (uint256) {
    return _commitmentFeeBips;
  }

  function drawnAmount() external view override returns (uint256) {
    return _drawnAmount;
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
    _drawnAmount = MathUtils.min(uint256(_drawnAmount) + amount, outstandingDebt).toUint128();
  }

  function _onRepay(MarketState memory state, uint256 amount) internal virtual override {
    amount;
    _updateDrawnAmountAfterRepay(state, totalAssets());
  }

  function _onRepayAndGetTotalAssets(
    MarketState memory state,
    uint256 amount
  ) internal virtual override returns (uint256 currentTotalAssets) {
    amount;
    currentTotalAssets = totalAssets();
    _updateDrawnAmountAfterRepay(state, currentTotalAssets);
  }

  /// @dev Repayments reduce the drawn amount to at most the remaining
  ///      outstanding debt. `currentTotalAssets` includes the repaid amount.
  function _updateDrawnAmountAfterRepay(
    MarketState memory state,
    uint256 currentTotalAssets
  ) internal {
    uint256 outstandingDebt = state.totalDebts().satSub(currentTotalAssets);
    _drawnAmount = MathUtils.min(uint256(_drawnAmount), outstandingDebt).toUint128();
  }

  function _onCloseMarket() internal virtual override {
    _drawnAmount = 0;
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
    uint256 timeDelta = timestamp - state.lastInterestAccruedTimestamp;
    if (timeDelta == 0 || state.scaledTotalSupply == 0 || state.isClosed) {
      return 0;
    }

    baseInterestRay = MathUtils.calculateLinearInterestFromBips(_commitmentFeeBips, timeDelta);

    uint256 drawn = _drawnAmount;
    if (state.annualInterestBips > 0 && drawn > 0) {
      uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(
        state.annualInterestBips,
        timeDelta
      );
      uint256 totalSupply = state.totalSupply();
      uint256 drawnClamped = MathUtils.min(drawn, totalSupply);
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

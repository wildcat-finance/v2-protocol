// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import '../IHooksFactoryRevolving.sol';
import '../interfaces/IWildcatMarketRevolving.sol';
import './WildcatMarket.sol';

contract WildcatMarketRevolving is WildcatMarket, IWildcatMarketRevolving {
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  uint16 internal immutable _commitmentFeeBips;

  uint128 internal _drawnAmount;

  constructor() {
    // NOTE(rcf-v2): Using a direct Solidity interface call for constructor-time
    // deployment metadata retrieval. This can be replaced with a Yul staticcall
    // in a follow-up optimization pass if necessary.
    _commitmentFeeBips = IHooksFactoryRevolving(msg.sender).getRevolvingMarketCommitmentFeeBips();
  }

  function commitmentFeeBips() external view override returns (uint256) {
    return _commitmentFeeBips;
  }

  function drawnAmount() external view override returns (uint256) {
    return _drawnAmount;
  }

  function _onBorrow(uint256 amount) internal virtual override {
    _drawnAmount = (_drawnAmount + amount).toUint128();
  }

  function _onRepay(MarketState memory state, uint256 amount) internal virtual override {
    amount;
    uint256 outstandingDebt = state.totalDebts().satSub(totalAssets());
    _drawnAmount = MathUtils.min(uint256(_drawnAmount), outstandingDebt).toUint128();
  }

  function _onCloseMarket() internal virtual override {
    _drawnAmount = 0;
  }

  function _calculateRevolvingBaseInterest(
    MarketState memory state,
    uint256 timestamp
  ) internal view returns (uint256 baseInterestRay) {
    uint256 timeDelta = timestamp - state.lastInterestAccruedTimestamp;
    if (timeDelta == 0 || state.scaledTotalSupply == 0) {
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

    state.scaleFactor = (prevScaleFactor + scaleFactorDelta).toUint112();
    state.lastInterestAccruedTimestamp = uint32(timestamp);
  }
}

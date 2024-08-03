// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './IHooks.sol';

struct TemporaryReserveRatio {
  uint16 originalAnnualInterestBips;
  uint16 originalReserveRatioBips;
  uint32 expiry;
}

abstract contract MarketConstraintHooks is IHooks {
  error DelinquencyGracePeriodOutOfBounds();
  error ReserveRatioBipsOutOfBounds();
  error DelinquencyFeeBipsOutOfBounds();
  error WithdrawalBatchDurationOutOfBounds();
  error AnnualInterestBipsOutOfBounds();

  uint32 internal constant MinimumDelinquencyGracePeriod = 0;
  uint32 internal constant MaximumDelinquencyGracePeriod = 90 days;

  uint16 internal constant MinimumReserveRatioBips = 0;
  uint16 internal constant MaximumReserveRatioBips = 10_000;

  uint16 internal constant MinimumDelinquencyFeeBips = 0;
  uint16 internal constant MaximumDelinquencyFeeBips = 10_000;

  uint32 internal constant MinimumWithdrawalBatchDuration = 0;
  uint32 internal constant MaximumWithdrawalBatchDuration = 365 days;

  uint16 internal constant MinimumAnnualInterestBips = 0;
  uint16 internal constant MaximumAnnualInterestBips = 10_000;

  function assertValueInRange(
    uint256 value,
    uint256 min,
    uint256 max,
    bytes4 errorSelector
  ) internal pure {
    assembly {
      if or(lt(value, min), gt(value, max)) {
        mstore(0, errorSelector)
        revert(0, 4)
      }
    }
  }

  /**
   * @dev Enforce constraints on market parameters, ensuring that
   *      `annualInterestBips`, `delinquencyFeeBips`, `withdrawalBatchDuration`,
   *      `reserveRatioBips` and `delinquencyGracePeriod` are within the
   *      allowed ranges and that `namePrefix` and `symbolPrefix` are not null.
   */
  function enforceParameterConstraints(
    uint16 annualInterestBips,
    uint16 delinquencyFeeBips,
    uint32 withdrawalBatchDuration,
    uint16 reserveRatioBips,
    uint32 delinquencyGracePeriod
  ) internal view virtual {
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );
    assertValueInRange(
      delinquencyFeeBips,
      MinimumDelinquencyFeeBips,
      MaximumDelinquencyFeeBips,
      DelinquencyFeeBipsOutOfBounds.selector
    );
    assertValueInRange(
      withdrawalBatchDuration,
      MinimumWithdrawalBatchDuration,
      MaximumWithdrawalBatchDuration,
      WithdrawalBatchDurationOutOfBounds.selector
    );
    assertValueInRange(
      reserveRatioBips,
      MinimumReserveRatioBips,
      MaximumReserveRatioBips,
      ReserveRatioBipsOutOfBounds.selector
    );
    assertValueInRange(
      delinquencyGracePeriod,
      MinimumDelinquencyGracePeriod,
      MaximumDelinquencyGracePeriod,
      DelinquencyGracePeriodOutOfBounds.selector
    );
  }

  /**
   * @dev Returns immutable constraints on market parameters that
   *      the controller variant will enforce.
   */
  function getParameterConstraints()
    external
    pure
    returns (MarketParameterConstraints memory constraints)
  {
    constraints.minimumDelinquencyGracePeriod = MinimumDelinquencyGracePeriod;
    constraints.maximumDelinquencyGracePeriod = MaximumDelinquencyGracePeriod;
    constraints.minimumReserveRatioBips = MinimumReserveRatioBips;
    constraints.maximumReserveRatioBips = MaximumReserveRatioBips;
    constraints.minimumDelinquencyFeeBips = MinimumDelinquencyFeeBips;
    constraints.maximumDelinquencyFeeBips = MaximumDelinquencyFeeBips;
    constraints.minimumWithdrawalBatchDuration = MinimumWithdrawalBatchDuration;
    constraints.maximumWithdrawalBatchDuration = MaximumWithdrawalBatchDuration;
    constraints.minimumAnnualInterestBips = MinimumAnnualInterestBips;
    constraints.maximumAnnualInterestBips = MaximumAnnualInterestBips;
  }

  function _onCreateMarket(
    address /* deployer */,
    DeployMarketInputs calldata parameters,
    bytes calldata /* extraData */
  ) internal virtual override {
    enforceParameterConstraints(
      parameters.annualInterestBips,
      parameters.delinquencyFeeBips,
      parameters.withdrawalBatchDuration,
      parameters.reserveRatioBips,
      parameters.delinquencyGracePeriod
    );
  }

  /**
   * @dev Returns the new temporary reserve ratio for a given interest rate
   *      change. This is calculated as no change if the rate change is LEQ
   *      a 25% decrease, otherwise double the relative difference between
   *      the old and new APR rates (in bips), bounded to a maximum of 100%.
   *      If this value is lower than the existing reserve ratio, the existing
   *      reserve ratio is returned instead.
   */
  function _calculateTemporaryReserveRatioBips(
    uint256 annualInterestBips,
    uint256 originalAnnualInterestBips,
    uint256 originalReserveRatioBips
  ) internal pure returns (uint16 temporaryReserveRatioBips) {
    // Calculate the relative reduction in the interest rate in bips,
    // bound to a maximum of 100%
    uint256 relativeDiff = MathUtils.mulDiv(
      10000,
      originalAnnualInterestBips - annualInterestBips,
      originalAnnualInterestBips
    );

    // If the reduction is 25% (2500 bips) or less, return the original reserve ratio
    if (relativeDiff <= 2500) {
      temporaryReserveRatioBips = uint16(originalReserveRatioBips);
    } else {
      // Calculate double the relative reduction in the interest rate in bips,
      // bound to a maximum of 100%
      uint256 boundRelativeDiff = MathUtils.min(10000, MathUtils.bipMul(2, relativeDiff));

      // If the bound relative diff is lower than the existing reserve ratio, return the latter.
      temporaryReserveRatioBips = uint16(
        MathUtils.max(boundRelativeDiff, originalReserveRatioBips)
      );
    }
  }

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata /* intermediateState */,
    bytes calldata /* extraData */
  )
    public
    virtual
    override
    returns (uint16 /* newAnnualInterestBips */, uint16 /* newReserveRatioBips */)
  {
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );
    assertValueInRange(
      reserveRatioBips,
      MinimumReserveRatioBips,
      MaximumReserveRatioBips,
      ReserveRatioBipsOutOfBounds.selector
    );
    return (annualInterestBips, reserveRatioBips);
  }
}

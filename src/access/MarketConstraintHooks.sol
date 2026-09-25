// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './IHooks.sol';
import '../libraries/BoolUtils.sol';

/// @dev original market terms retained while an APR reduction can require excess reserves.
struct TemporaryReserveRatio {
  uint16 originalAnnualInterestBips;
  uint16 originalReserveRatioBips;
  uint32 expiry;
}

/// @dev callback-safe market closure query for scheduled completion.
interface IMarketLifecycleView {
  function isClosed() external view returns (bool);
}

/// @notice shared market-parameter bounds and default APR-reduction reserve policy.
/// @dev OpenTerm and FixedTerm use the reduction policy; PeriodicTerm overrides reductions with its
///      proposal flow. ordinary updates ignore the borrower-supplied reserve ratio. reductions may
///      apply a temporary ratio derived from the original APR and reserve ratio; cancellation or a
///      later update that expires the period restores that original ratio.
abstract contract MarketConstraintHooks is IHooks {
  using BoolUtils for bool;

  /// @dev the delinquency grace period is outside this template's inclusive bounds.
  error DelinquencyGracePeriodOutOfBounds();
  /// @dev the reserve ratio is outside this template's inclusive bounds.
  error ReserveRatioBipsOutOfBounds();
  /// @dev the delinquency fee is outside this template's inclusive bounds.
  error DelinquencyFeeBipsOutOfBounds();
  /// @dev the withdrawal-batch duration is outside this template's inclusive bounds.
  error WithdrawalBatchDurationOutOfBounds();
  /// @dev the annual lender APR is outside this template's inclusive bounds.
  error AnnualInterestBipsOutOfBounds();
  error RepaymentPeriodOutOfBounds();
  error RepaymentDateOutOfBounds();

  // terms are immutable in the core. retain the date here for callback policy checks.
  mapping(address => uint32) internal _marketRepaymentDates;

  function _isMarketInRepayment(address market) internal view returns (bool) {
    uint256 date = _marketRepaymentDates[market];
    return date != 0 && block.timestamp >= date;
  }

  /// @notice emitted when an APR reduction starts a temporary excess-reserve period.
  event TemporaryExcessReserveRatioActivated(
    address indexed market,
    uint256 originalReserveRatioBips,
    uint256 temporaryReserveRatioBips,
    uint256 temporaryReserveRatioExpiry
  );

  /// @notice emitted when another APR update changes an active temporary ratio.
  event TemporaryExcessReserveRatioUpdated(
    address indexed market,
    uint256 originalReserveRatioBips,
    uint256 temporaryReserveRatioBips,
    uint256 temporaryReserveRatioExpiry
  );

  /// @notice emitted when a later APR update cancels the temporary ratio.
  event TemporaryExcessReserveRatioCanceled(address indexed market);

  /// @notice emitted when a later update restores an expired temporary ratio.
  event TemporaryExcessReserveRatioExpired(address indexed market);

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

  /// @notice stored APR-reduction baseline and expiry for each market.
  /// @dev time passing does not clear an expired entry; a qualifying later update does.
  mapping(address => TemporaryReserveRatio) public temporaryExcessReserveRatio;

  /// @dev reverts with `errorSelector` when `value` falls outside the inclusive range.
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

  /// @dev applies this template's inclusive parameter bounds during market creation.
  function enforceParameterConstraints(
    uint16 annualInterestBips,
    uint16 delinquencyFeeBips,
    uint32 withdrawalBatchDuration,
    uint16 reserveRatioBips,
    uint32 delinquencyGracePeriod
  ) internal view virtual {
    MarketParameterConstraints memory limits = _getParameterConstraints();
    assertValueInRange(
      annualInterestBips,
      limits.minimumAnnualInterestBips,
      limits.maximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );
    assertValueInRange(
      delinquencyFeeBips,
      limits.minimumDelinquencyFeeBips,
      limits.maximumDelinquencyFeeBips,
      DelinquencyFeeBipsOutOfBounds.selector
    );
    assertValueInRange(
      withdrawalBatchDuration,
      limits.minimumWithdrawalBatchDuration,
      limits.maximumWithdrawalBatchDuration,
      WithdrawalBatchDurationOutOfBounds.selector
    );
    assertValueInRange(
      reserveRatioBips,
      limits.minimumReserveRatioBips,
      limits.maximumReserveRatioBips,
      ReserveRatioBipsOutOfBounds.selector
    );
    assertValueInRange(
      delinquencyGracePeriod,
      limits.minimumDelinquencyGracePeriod,
      limits.maximumDelinquencyGracePeriod,
      DelinquencyGracePeriodOutOfBounds.selector
    );
  }

  /// @notice returns the parameter bounds enforced by this template during market creation.
  function getParameterConstraints()
    external
    view
    returns (MarketParameterConstraints memory constraints)
  {
    return _getParameterConstraints();
  }

  /// @dev override this once to change both discovery and enforcement for a registered template.
  function _getParameterConstraints()
    internal
    view
    virtual
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
    constraints.maximumRepaymentPeriod = 90 days;
    constraints.maximumRepaymentDateDelay = 730 days;
  }

  function _onCreateMarket(
    address /* administrator */,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata /* extraData */
  ) internal virtual override returns (HooksConfig) {
    enforceParameterConstraints(
      parameters.annualInterestBips,
      parameters.delinquencyFeeBips,
      parameters.withdrawalBatchDuration,
      parameters.reserveRatioBips,
      parameters.delinquencyGracePeriod
    );
    MarketParameterConstraints memory limits = _getParameterConstraints();
    if (parameters.repaymentPeriod > limits.maximumRepaymentPeriod)
      revert RepaymentPeriodOutOfBounds();
    if (parameters.repaymentDate != 0) {
      if (parameters.repaymentDate > block.timestamp + limits.maximumRepaymentDateDelay)
        revert RepaymentDateOutOfBounds();
      _marketRepaymentDates[marketAddress] = parameters.repaymentDate;
    }
  }

  /// @dev keeps the original reserve ratio for an APR reduction of 25% or less. above that, returns
  ///      the greater of the original ratio and twice the relative APR reduction, capped at 100%.
  function _calculateTemporaryReserveRatioBips(
    uint256 annualInterestBips,
    uint256 originalAnnualInterestBips,
    uint256 originalReserveRatioBips
  ) internal pure returns (uint16 temporaryReserveRatioBips) {
    uint256 reduction = originalAnnualInterestBips - annualInterestBips;

    // compare before converting to bips. if we floor first, a reduction just over
    // 25% looks like exactly 25% and skips the temporary reserve requirement.
    if (reduction * BIP <= originalAnnualInterestBips * 2500) {
      return uint16(originalReserveRatioBips);
    }

    // multiply before dividing so the temporary reserve ratio only rounds once.
    uint256 boundRelativeDiff = MathUtils.min(
      BIP,
      MathUtils.mulDiv(2 * BIP, reduction, originalAnnualInterestBips)
    );

    // don't let this calculation lower the reserve ratio that's already set.
    temporaryReserveRatioBips = uint16(MathUtils.max(boundRelativeDiff, originalReserveRatioBips));
  }

  /// @notice applies the shared APR-reduction reserve policy.
  /// @dev overriding `_applyDefaultAprUpdate` replaces this calculation while keeping the
  ///      surrounding term checks in `_applyAprUpdate`.
  ///      the first reduction anchors a two-week period to the market's current APR and reserve
  ///      ratio. further reductions restart it; a partial recovery keeps its expiry. returning to
  ///      the original APR cancels the period, while a non-decreasing update at expiry ends it.
  ///      the caller's proposed reserve ratio is deliberately ignored.
  /// @param annualInterestBips APR proposed by the borrower, in basis points.
  /// @param intermediateState current market state before the parameter update.
  /// @return newAnnualInterestBips APR the market should apply; always the proposed APR.
  /// @return newReserveRatioBips current, temporary, or restored original reserve ratio.
  function _applyDefaultAprUpdate(
    uint16 annualInterestBips,
    MarketState calldata intermediateState
  ) internal virtual returns (uint16 newAnnualInterestBips, uint16 newReserveRatioBips) {
    (newAnnualInterestBips, newReserveRatioBips) = (
      annualInterestBips,
      intermediateState.reserveRatioBips
    );
    address market = msg.sender;

    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );

    // get the existing temporary reserve ratio from storage, if any. `tmp` retains the original
    // APR and reserve ratio across later updates in the same period.
    TemporaryReserveRatio memory tmp = temporaryExcessReserveRatio[market];
    // don't restore a pre-repayment reserve ratio. the effective validator must see 100% too.
    if (_isMarketInRepayment(market)) {
      if (tmp.expiry != 0) {
        delete temporaryExcessReserveRatio[market];
        emit TemporaryExcessReserveRatioCanceled(market);
      }
      return (annualInterestBips, 10_000);
    }

    if (tmp.expiry > 0) {
      bool canExpire = (annualInterestBips >= intermediateState.annualInterestBips).and(
        block.timestamp >= tmp.expiry
      );
      bool canCancel = annualInterestBips >= tmp.originalAnnualInterestBips;
      if (canExpire.or(canCancel)) {
        // `canExpire` requires `tmp.expiry` to have passed and no further APR reduction.
        // `canCancel` requires restoring at least `tmp.originalAnnualInterestBips`.
        // either clears the period and restores `tmp.originalReserveRatioBips`;
        // emit TemporaryExcessReserveRatioExpired if both conditions apply.
        if (canExpire) {
          emit TemporaryExcessReserveRatioExpired(market);
        } else {
          emit TemporaryExcessReserveRatioCanceled(market);
        }
        delete temporaryExcessReserveRatio[market];
        return (newAnnualInterestBips, tmp.originalReserveRatioBips);
      }
    }

    // get the original APR/reserve values for the ongoing or newly created period.
    // `tmp.expiry == 0` starts from `intermediateState`; otherwise keep the stored originals.
    (uint16 originalAnnualInterestBips, uint16 originalReserveRatioBips) = tmp.expiry == 0
      ? (intermediateState.annualInterestBips, intermediateState.reserveRatioBips)
      : (tmp.originalAnnualInterestBips, tmp.originalReserveRatioBips);

    if (annualInterestBips < originalAnnualInterestBips) {
      // if `annualInterestBips` is below `originalAnnualInterestBips`, calculate the temporarily
      // increased reserve ratio from that original APR:
      // relativeReduction <= 0.25 ? originalReserveRatio :
      // max(originalReserveRatio, min(2 * relativeReduction, 100%))
      uint16 temporaryReserveRatioBips = _calculateTemporaryReserveRatioBips(
        annualInterestBips,
        originalAnnualInterestBips,
        originalReserveRatioBips
      );
      uint32 expiry = uint32(block.timestamp + 2 weeks);
      if (tmp.expiry == 0) {
        // no existing temporary reserve period. store `originalAnnualInterestBips` and
        // `originalReserveRatioBips` so later updates use the same starting values.
        emit TemporaryExcessReserveRatioActivated(
          market,
          originalReserveRatioBips,
          temporaryReserveRatioBips,
          expiry
        );
        tmp.originalAnnualInterestBips = originalAnnualInterestBips;
        tmp.originalReserveRatioBips = originalReserveRatioBips;
      } else {
        // if `annualInterestBips` is at least `intermediateState.annualInterestBips`, update the
        // reserve ratio but keep `tmp.expiry`. a further APR reduction restarts a two-week period.
        if (annualInterestBips >= intermediateState.annualInterestBips) {
          expiry = tmp.expiry;
        }
        emit TemporaryExcessReserveRatioUpdated(
          market,
          originalReserveRatioBips,
          temporaryReserveRatioBips,
          expiry
        );
      }
      tmp.expiry = expiry;
      temporaryExcessReserveRatio[market] = tmp;
      newReserveRatioBips = temporaryReserveRatioBips;
    }
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MarketConstraintHooks } from 'src/access/MarketConstraintHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketParameterConstraints } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils } from 'src/libraries/MathUtils.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract MarketConstraintHooksTest is TestKernel {
  address internal constant MarketA = address(0x4001);
  address internal constant MarketB = address(0x4002);
  address internal constant MarketC = address(0x4003);
  uint32 internal constant StartTimestamp = 1_724_284_800;

  OpenTermHooks internal hooks;

  function setUp() external {
    vm.warp(StartTimestamp);
    hooks = OpenTermHooks(
      _deployCode(
        'src/access/OpenTermHooks.sol:OpenTermHooks',
        abi.encode(address(this), bytes(''))
      )
    );
  }

  function _createMarket(address market, DeployMarketInputs memory inputs) internal {
    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks));
    hooks.onCreateMarket(address(this), market, inputs, '');
  }

  function _setApr(
    address market,
    uint16 requestedApr,
    uint16 requestedReserveRatio,
    uint16 currentApr,
    uint16 currentReserveRatio
  ) internal returns (uint16 updatedApr, uint16 updatedReserveRatio) {
    MarketState memory state;
    state.annualInterestBips = currentApr;
    state.reserveRatioBips = currentReserveRatio;
    vm.prank(market);
    return
      hooks.onSetAnnualInterestAndReserveRatioBips(requestedApr, requestedReserveRatio, state, '');
  }

  function _expectedTemporaryReserveRatio(
    uint16 newApr,
    uint16 originalApr,
    uint16 originalReserveRatio
  ) internal pure returns (uint16) {
    uint256 reduction = originalApr - newApr;
    if (reduction * 10_000 <= uint256(originalApr) * 2_500) return originalReserveRatio;
    uint256 relativeReduction = MathUtils.mulDiv(10_000, reduction, originalApr);
    return
      uint16(MathUtils.max(originalReserveRatio, MathUtils.min(10_000, relativeReduction * 2)));
  }

  function _assertTemporaryReserveRatio(
    address market,
    uint16 originalApr,
    uint16 originalReserveRatio,
    uint32 expiry
  ) internal view {
    (uint16 storedApr, uint16 storedReserveRatio, uint32 storedExpiry) = hooks
      .temporaryExcessReserveRatio(market);
    assertEq(storedApr, originalApr, 'original APR');
    assertEq(storedReserveRatio, originalReserveRatio, 'original reserve ratio');
    assertEq(storedExpiry, expiry, 'temporary expiry');
  }

  function _activateReduction(
    address market,
    uint16 newApr
  ) internal returns (uint32 expiry, uint16 temporaryReserveRatio) {
    temporaryReserveRatio = _expectedTemporaryReserveRatio(newApr, 1_000, 2_000);
    expiry = uint32(block.timestamp + 2 weeks);
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioActivated(
      market,
      2_000,
      temporaryReserveRatio,
      expiry
    );
    (uint16 updatedApr, uint16 updatedReserveRatio) = _setApr(market, newApr, 0, 1_000, 2_000);
    assertEq(updatedApr, newApr, 'activated APR');
    assertEq(updatedReserveRatio, temporaryReserveRatio, 'activated reserve ratio');
    _assertTemporaryReserveRatio(market, 1_000, 2_000, expiry);
  }

  function test_onCreateMarket_EnforcesAndAdvertisesEveryParameterConstraint() external {
    MarketParameterConstraints memory constraints = hooks.getParameterConstraints();
    assertEq(constraints.minimumAnnualInterestBips, 0, 'minimum APR');
    assertEq(constraints.maximumAnnualInterestBips, 10_000, 'maximum APR');
    assertEq(constraints.minimumDelinquencyFeeBips, 0, 'minimum delinquency fee');
    assertEq(constraints.maximumDelinquencyFeeBips, 10_000, 'maximum delinquency fee');
    assertEq(constraints.minimumWithdrawalBatchDuration, 0, 'minimum batch duration');
    assertEq(constraints.maximumWithdrawalBatchDuration, 365 days, 'maximum batch duration');
    assertEq(constraints.minimumReserveRatioBips, 0, 'minimum reserve ratio');
    assertEq(constraints.maximumReserveRatioBips, 10_000, 'maximum reserve ratio');
    assertEq(constraints.minimumDelinquencyGracePeriod, 0, 'minimum grace period');
    assertEq(constraints.maximumDelinquencyGracePeriod, 90 days, 'maximum grace period');

    DeployMarketInputs memory inputs;
    _createMarket(MarketA, inputs);
    inputs.annualInterestBips = 10_000;
    inputs.delinquencyFeeBips = 10_000;
    inputs.withdrawalBatchDuration = 365 days;
    inputs.reserveRatioBips = 10_000;
    inputs.delinquencyGracePeriod = 90 days;
    _createMarket(MarketB, inputs);

    inputs = DeployMarketInputs({
      asset: address(0),
      namePrefix: '',
      symbolPrefix: '',
      maxTotalSupply: 0,
      annualInterestBips: 10_001,
      delinquencyFeeBips: 0,
      withdrawalBatchDuration: 0,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 0,
      hooks: EmptyHooksConfig
    });
    vm.expectRevert(MarketConstraintHooks.AnnualInterestBipsOutOfBounds.selector);
    _createMarket(MarketC, inputs);

    inputs.annualInterestBips = 0;
    inputs.delinquencyFeeBips = 10_001;
    vm.expectRevert(MarketConstraintHooks.DelinquencyFeeBipsOutOfBounds.selector);
    _createMarket(MarketC, inputs);

    inputs.delinquencyFeeBips = 0;
    inputs.withdrawalBatchDuration = 365 days + 1;
    vm.expectRevert(MarketConstraintHooks.WithdrawalBatchDurationOutOfBounds.selector);
    _createMarket(MarketC, inputs);

    inputs.withdrawalBatchDuration = 0;
    inputs.reserveRatioBips = 10_001;
    vm.expectRevert(MarketConstraintHooks.ReserveRatioBipsOutOfBounds.selector);
    _createMarket(MarketC, inputs);

    inputs.reserveRatioBips = 0;
    inputs.delinquencyGracePeriod = 90 days + 1;
    vm.expectRevert(MarketConstraintHooks.DelinquencyGracePeriodOutOfBounds.selector);
    _createMarket(MarketC, inputs);

    MarketState memory state;
    state.annualInterestBips = 10_000;
    vm.prank(MarketC);
    vm.expectRevert(MarketConstraintHooks.AnnualInterestBipsOutOfBounds.selector);
    hooks.onSetAnnualInterestAndReserveRatioBips(10_001, 0, state, '');
  }

  function test_onSetApr_CalculatesTemporaryReserveRatio(
    uint16 originalApr,
    uint16 newApr,
    uint16 originalReserveRatio,
    uint16 requestedReserveRatio
  ) external {
    originalApr = uint16(bound(originalApr, 1, 10_000));
    newApr = uint16(bound(newApr, 0, originalApr));
    originalReserveRatio = uint16(bound(originalReserveRatio, 0, 10_000));

    if (newApr < originalApr) {
      uint16 expectedReserveRatio = _expectedTemporaryReserveRatio(
        newApr,
        originalApr,
        originalReserveRatio
      );
      uint32 expiry = uint32(block.timestamp + 2 weeks);
      vm.expectEmit(address(hooks));
      emit MarketConstraintHooks.TemporaryExcessReserveRatioActivated(
        MarketA,
        originalReserveRatio,
        expectedReserveRatio,
        expiry
      );
      (uint16 updatedApr, uint16 updatedReserveRatio) = _setApr(
        MarketA,
        newApr,
        requestedReserveRatio,
        originalApr,
        originalReserveRatio
      );
      assertEq(updatedApr, newApr, 'updated APR');
      assertEq(updatedReserveRatio, expectedReserveRatio, 'updated reserve ratio');
      _assertTemporaryReserveRatio(MarketA, originalApr, originalReserveRatio, expiry);
    } else {
      (uint16 updatedApr, uint16 updatedReserveRatio) = _setApr(
        MarketA,
        newApr,
        requestedReserveRatio,
        originalApr,
        originalReserveRatio
      );
      assertEq(updatedApr, newApr, 'unchanged APR');
      assertEq(updatedReserveRatio, originalReserveRatio, 'unchanged reserve ratio');
      _assertTemporaryReserveRatio(MarketA, 0, 0, 0);
    }
  }

  function test_onSetApr_PreservesQuarterBoundaryAndRoundsOnlyAfterComparison() external {
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioActivated(
      MarketA,
      2_000,
      2_000,
      StartTimestamp + 2 weeks
    );
    (, uint16 reserveRatioBips) = _setApr(MarketA, 750, 0, 1_000, 2_000);
    assertEq(reserveRatioBips, 2_000, 'quarter reduction');

    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioActivated(
      MarketB,
      0,
      5_000,
      StartTimestamp + 2 weeks
    );
    (, reserveRatioBips) = _setApr(MarketB, 5_625, 0, 7_501, 0);
    assertEq(reserveRatioBips, 5_000, 'slightly over quarter');
  }

  function test_onSetApr_UpdatesActiveReductionAndPreservesOrExtendsExpiry() external {
    (uint32 firstExpiry, ) = _activateReduction(MarketA, 700);
    vm.warp(StartTimestamp + 1 weeks);
    uint32 extendedExpiry = uint32(block.timestamp + 2 weeks);
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioUpdated(
      MarketA,
      2_000,
      8_000,
      extendedExpiry
    );
    (, uint16 reserveRatioBips) = _setApr(MarketA, 600, 0, 700, 6_000);
    assertEq(reserveRatioBips, 8_000, 'further reduction reserve ratio');
    _assertTemporaryReserveRatio(MarketA, 1_000, 2_000, extendedExpiry);

    vm.warp(StartTimestamp);
    _activateReduction(MarketB, 749);
    vm.warp(StartTimestamp + 1 weeks);
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioUpdated(
      MarketB,
      2_000,
      2_000,
      firstExpiry
    );
    (, reserveRatioBips) = _setApr(MarketB, 850, 0, 749, 5_020);
    assertEq(reserveRatioBips, 2_000, 'partial recovery reserve ratio');
    _assertTemporaryReserveRatio(MarketB, 1_000, 2_000, firstExpiry);
  }

  function test_onSetApr_CancelsOrExpiresAndRestoresOriginalReserveRatio() external {
    _activateReduction(MarketA, 700);
    vm.warp(StartTimestamp + 1 weeks);
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioCanceled(MarketA);
    (uint16 updatedApr, uint16 updatedReserveRatio) = _setApr(MarketA, 1_001, 0, 700, 6_000);
    assertEq(updatedApr, 1_001, 'cancel APR');
    assertEq(updatedReserveRatio, 2_000, 'cancel reserve ratio');
    _assertTemporaryReserveRatio(MarketA, 0, 0, 0);

    vm.warp(StartTimestamp);
    (uint32 expiry, ) = _activateReduction(MarketB, 700);
    vm.warp(expiry);
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioExpired(MarketB);
    (updatedApr, updatedReserveRatio) = _setApr(MarketB, 700, 0, 700, 6_000);
    assertEq(updatedApr, 700, 'expiry APR');
    assertEq(updatedReserveRatio, 2_000, 'expiry reserve ratio');
    _assertTemporaryReserveRatio(MarketB, 0, 0, 0);
  }

  function test_onSetApr_FurtherReductionAfterExpiryStartsANewWindow() external {
    (uint32 expiry, ) = _activateReduction(MarketA, 700);
    vm.warp(expiry);
    uint32 newExpiry = uint32(block.timestamp + 2 weeks);
    vm.expectEmit(address(hooks));
    emit MarketConstraintHooks.TemporaryExcessReserveRatioUpdated(MarketA, 2_000, 8_000, newExpiry);
    (uint16 updatedApr, uint16 updatedReserveRatio) = _setApr(MarketA, 600, 0, 700, 6_000);
    assertEq(updatedApr, 600, 'further reduction APR');
    assertEq(updatedReserveRatio, 8_000, 'further reduction reserve ratio');
    _assertTemporaryReserveRatio(MarketA, 1_000, 2_000, newExpiry);
  }

  function test_onSetApr_IncreaseOrEqualityDoesNotCreateTemporaryState(
    uint16 currentApr,
    uint16 requestedApr,
    uint16 currentReserveRatio,
    uint16 requestedReserveRatio
  ) external {
    currentApr = uint16(bound(currentApr, 0, 10_000));
    requestedApr = uint16(bound(requestedApr, currentApr, 10_000));
    currentReserveRatio = uint16(bound(currentReserveRatio, 0, 10_000));
    (uint16 updatedApr, uint16 updatedReserveRatio) = _setApr(
      MarketA,
      requestedApr,
      requestedReserveRatio,
      currentApr,
      currentReserveRatio
    );
    assertEq(updatedApr, requestedApr, 'increased APR');
    assertEq(updatedReserveRatio, currentReserveRatio, 'preserved reserve ratio');
    _assertTemporaryReserveRatio(MarketA, 0, 0, 0);
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { RAY } from 'src/libraries/MathUtils.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

interface VmStateSnapshots {
  function snapshotState() external returns (uint256 snapshotId);

  function revertToState(uint256 snapshotId) external returns (bool success);
}

contract RepayExpiryDelinquencyTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);
  address internal constant Payer = address(0xB0B);

  uint256 internal constant InitialSupply = 3e18;
  uint256 internal constant Repayment = 6e18;

  struct Outcome {
    uint256 scaleFactor;
    uint256 timeDelinquent;
    bool isDelinquent;
    uint256 scaledTotalSupply;
    uint256 scaledPendingWithdrawals;
    uint256 scaledAmountBurned;
    uint256 normalizedAmountPaid;
    uint256 totalDebts;
    uint256 drawnAmount;
  }

  function _options(bool revolving) private pure returns (Options memory options) {
    options = _defaultOptions(HooksKind.OpenTerm);
    options.revolving = revolving;
    options.protocolFeeBips = 0;
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    options.delinquencyFeeBips = 10_000;
    options.delinquencyGracePeriod = 0;
    options.reserveRatioBips = 0;
    options.withdrawalBatchDuration = 365 days;
  }

  function _setUpPendingBatch(
    bool revolving
  ) private returns (Fixture memory fixture, uint32 expiry) {
    fixture = _newMarket(_options(revolving));
    _deposit(fixture, Holder, InitialSupply);

    vm.prank(Borrower);
    fixture.market.borrow(InitialSupply);

    vm.prank(Holder);
    expiry = fixture.market.queueFullWithdrawal();
  }

  function _setUpExpiredBatch(
    bool revolving
  ) private returns (Fixture memory fixture, uint32 expiry) {
    (fixture, expiry) = _setUpPendingBatch(revolving);

    _fundAndApprove(fixture, Payer, Repayment);
    vm.warp(uint256(expiry) + 2 * 365 days);
    assertEq(fixture.market.totalDebts(), 18e18, 'projected debt before late inflow');
  }

  function _capture(
    Fixture memory fixture,
    uint32 expiry,
    bool revolving
  ) private view returns (Outcome memory outcome) {
    MarketState memory state = fixture.market.previousState();
    WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
    outcome.scaleFactor = state.scaleFactor;
    outcome.timeDelinquent = state.timeDelinquent;
    outcome.isDelinquent = state.isDelinquent;
    outcome.scaledTotalSupply = state.scaledTotalSupply;
    outcome.scaledPendingWithdrawals = state.scaledPendingWithdrawals;
    outcome.scaledAmountBurned = batch.scaledAmountBurned;
    outcome.normalizedAmountPaid = batch.normalizedAmountPaid;
    outcome.totalDebts = fixture.market.totalDebts();
    if (revolving) {
      outcome.drawnAmount = IWildcatMarketRevolving(address(fixture.market)).drawnAmount();
    }
  }

  function _assertExpectedOutcome(Outcome memory outcome, bool revolving) private pure {
    assertEq(outcome.scaleFactor, 6 * RAY, 'scale factor');
    assertEq(outcome.timeDelinquent, 3 * 365 days, 'delinquency timer');
    assertTrue(outcome.isDelinquent, 'delinquency');
    assertEq(outcome.scaledTotalSupply, 2e18, 'residual scaled supply');
    assertEq(outcome.scaledPendingWithdrawals, 2e18, 'residual scaled pending');
    assertEq(outcome.scaledAmountBurned, 1e18, 'batch burn');
    assertEq(outcome.normalizedAmountPaid, Repayment, 'batch payment');
    assertEq(outcome.totalDebts, 18e18, 'total debt');
    if (revolving) assertEq(outcome.drawnAmount, InitialSupply, 'drawn principal');
  }

  function _repay(Fixture memory fixture, bool processInSameCall) private {
    vm.prank(Payer);
    if (processInSameCall) {
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(Repayment, 1);
    } else {
      fixture.market.repay(Repayment);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    }
  }

  function _assertLateRepaymentOrdering(bool processInSameCall) private {
    for (uint256 marketKind; marketKind < 2; marketKind++) {
      bool revolving = marketKind == 1;
      (Fixture memory fixture, uint32 expiry) = _setUpExpiredBatch(revolving);
      uint256 snapshotId = VmStateSnapshots(address(vm)).snapshotState();

      fixture.market.updateState();
      _repay(fixture, processInSameCall);
      Outcome memory control = _capture(fixture, expiry, revolving);

      assertTrue(VmStateSnapshots(address(vm)).revertToState(snapshotId), 'snapshot restore');

      _repay(fixture, processInSameCall);
      Outcome memory lateRepayment = _capture(fixture, expiry, revolving);

      _assertExpectedOutcome(control, revolving);
      _assertExpectedOutcome(lateRepayment, revolving);
    }
  }

  function test_lateCombinedRepaymentDoesNotRewriteExpiredInterval_AcrossMarketTypes() external {
    _assertLateRepaymentOrdering(true);
  }

  function test_latePlainRepaymentDoesNotRewriteExpiredInterval_AcrossMarketTypes() external {
    _assertLateRepaymentOrdering(false);
  }

  function test_lateDonationDoesNotRewriteExpiredInterval_AcrossMarketTypes() external {
    for (uint256 marketKind; marketKind < 2; marketKind++) {
      bool revolving = marketKind == 1;
      (Fixture memory fixture, uint32 expiry) = _setUpExpiredBatch(revolving);
      uint256 snapshotId = VmStateSnapshots(address(vm)).snapshotState();

      fixture.market.updateState();
      vm.prank(Payer);
      fixture.asset.transfer(address(fixture.market), Repayment);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      Outcome memory control = _capture(fixture, expiry, revolving);

      assertTrue(VmStateSnapshots(address(vm)).revertToState(snapshotId), 'snapshot restore');

      vm.prank(Payer);
      fixture.asset.transfer(address(fixture.market), Repayment);
      MarketState memory projectedState = fixture.market.currentState();
      fixture.market.updateState();
      assertEq(
        keccak256(abi.encode(fixture.market.previousState())),
        keccak256(abi.encode(projectedState)),
        'projected state'
      );
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      Outcome memory lateDonation = _capture(fixture, expiry, revolving);

      _assertExpectedOutcome(control, revolving);
      _assertExpectedOutcome(lateDonation, revolving);
    }
  }

  function test_repaymentAtExpiryCountsTowardsCurrentBatch_AcrossMarketTypes() external {
    for (uint256 marketKind; marketKind < 2; marketKind++) {
      bool revolving = marketKind == 1;
      (Fixture memory fixture, uint32 expiry) = _setUpPendingBatch(revolving);
      _fundAndApprove(fixture, Payer, Repayment);

      vm.warp(expiry);
      vm.prank(Payer);
      fixture.market.repay(Repayment);

      MarketState memory state = fixture.market.previousState();
      WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
      assertEq(state.pendingWithdrawalExpiry, expiry, 'current batch');
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'unpaid batches');
      assertEq(batch.scaledAmountBurned, InitialSupply, 'batch burn');
      assertEq(batch.normalizedAmountPaid, Repayment, 'batch payment');
      assertEq(fixture.market.totalDebts(), Repayment, 'total debt');
      if (revolving) {
        assertEq(
          IWildcatMarketRevolving(address(fixture.market)).drawnAmount(),
          0,
          'drawn principal'
        );
      }
    }
  }

  function test_lateCombinedRepaymentRespectsMaxBatches_AcrossMarketTypes() external {
    for (uint256 marketKind; marketKind < 2; marketKind++) {
      bool revolving = marketKind == 1;
      (Fixture memory fixture, uint32 expiry) = _setUpExpiredBatch(revolving);

      vm.prank(Payer);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(Repayment, 0);

      WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 1, 'unpaid batches');
      assertEq(batch.scaledAmountBurned, 0, 'premature batch burn');
      assertEq(batch.normalizedAmountPaid, 0, 'premature batch payment');

      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      _assertExpectedOutcome(_capture(fixture, expiry, revolving), revolving);
    }
  }

  function _readCheckpointedTotalAssets(address market) private view returns (uint256 value) {
    uint256 slot0 = uint256(vm.load(market, bytes32(uint256(0))));
    uint256 slot3 = uint256(vm.load(market, bytes32(uint256(3))));
    value = (slot0 >> 136) | ((slot3 >> 224) << 120);
  }

  function _donate(Fixture memory fixture, uint256 amount) private {
    fixture.asset.mint(Payer, amount);
    vm.prank(Payer);
    fixture.asset.transfer(address(fixture.market), amount);
  }

  function test_checkpointedAssetBalanceUsesPaddingSaturatesAndClears() external {
    (Fixture memory fixture, uint32 expiry) = _setUpPendingBatch(false);
    uint256 splitBalance = (uint256(1) << 120) + 123;

    _donate(fixture, splitBalance);
    fixture.market.updateState();
    assertEq(_readCheckpointedTotalAssets(address(fixture.market)), splitBalance, 'split balance');

    uint256 oversizedBalance = uint256(type(uint152).max) + 123;
    _donate(fixture, oversizedBalance - splitBalance);
    fixture.market.updateState();
    assertEq(
      _readCheckpointedTotalAssets(address(fixture.market)),
      type(uint152).max,
      'saturated balance'
    );

    MarketState memory state = fixture.market.previousState();
    assertFalse(state.isClosed, 'closed');
    assertEq(state.maxTotalSupply, MaximumMarketSupply, 'max supply');
    assertEq(state.normalizedUnclaimedWithdrawals, InitialSupply, 'unclaimed withdrawals');
    assertEq(state.pendingWithdrawalExpiry, expiry, 'pending expiry');
    assertEq(state.scaleFactor, RAY, 'scale factor');

    vm.warp(uint256(expiry) + 1);
    fixture.market.updateState();
    assertEq(_readCheckpointedTotalAssets(address(fixture.market)), 0, 'cleared balance');
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { Vm } from 'forge-std/Vm.sol';
import { WildcatMarketBase } from 'src/market/WildcatMarketBase.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { PeriodicTermPolicy } from 'src/access/PeriodicTermPolicy.sol';
import { PendingAprChange } from 'src/access/types/PeriodicTermHookTypes.sol';

/// @dev R2-02 prototype evidence. uses the actual stored-initcode path and both factories.
contract RepaymentPrototypeTest is ProductionMatrixFixture {
  ProductionStack internal stack;

  function setUp() public {
    vm.warp(1_800_000_000);
    stack = _deployProductionStack();
  }

  function _cell(
    MatrixMarketKind model,
    uint32 date,
    uint32 period
  ) private returns (MatrixCell memory cell) {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, model);
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    options.repaymentDate = date;
    options.repaymentPeriod = period;
    cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      uint96(1 + uint256(model))
    );
    _authorize(stack, cell, MatrixAlice);
    _authorize(stack, cell, MatrixBob);
    _approveBorrower(stack, cell, 1_000_000e18);
  }

  function _fundAndDraw(MatrixCell memory cell) private {
    _deposit(stack, cell, MatrixAlice, 1_000e18);
    _borrow(cell, 800e18);
  }

  function test_ProductionArtifactsFitActualCodeStorageAndRuntimeLimits() public {
    string[2] memory artifacts = [
      'src/market/WildcatMarket.sol:WildcatMarket',
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
    ];
    for (uint256 i; i < artifacts.length; i++) {
      assertTrue(
        vm.getCode(artifacts[i]).length + 1 <= 24_576,
        'STOP plus initcode must fit EIP-170'
      );
      assertTrue(vm.getDeployedCode(artifacts[i]).length <= 24_576, 'runtime must fit EIP-170');
    }
  }

  function test_AllSixFactoryCombinationsAcceptDisabledAndZeroPeriodTerms() public {
    for (uint256 model; model < 2; model++) {
      for (uint256 policy; policy < 3; policy++) {
        for (uint256 enabled; enabled < 2; enabled++) {
          MatrixOptions memory options = _defaultMatrixOptions(
            MatrixHooksKind(policy),
            MatrixMarketKind(model)
          );
          options.repaymentDate = enabled == 0 ? 0 : uint32(vm.getBlockTimestamp() + 90 days);
          MatrixCell memory cell = _deployMatrixCell(
            stack,
            options,
            MatrixBorrower,
            MatrixBorrower,
            uint96(1 + model * 6 + policy * 2 + enabled)
          );
          assertEq(cell.market.repaymentDate(), options.repaymentDate, 'date');
          assertEq(cell.market.repaymentPeriod(), 0, 'zero period');
          assertEq(cell.market.repaymentDeadline(), options.repaymentDate, 'deadline');
          assertEq(cell.market.defaultedAt(), 0, 'new market');
        }
      }
    }
  }

  function test_ZeroPeriodCureAfterEarlierUpdateInSameBlock() public {
    uint32 date = uint32(vm.getBlockTimestamp() + 1 days);
    MatrixCell memory standard = _cell(MatrixMarketKind.Standard, date, 0);
    MatrixCell memory revolving = _cell(MatrixMarketKind.Revolving, date, 0);
    _fundAndDraw(standard);
    _fundAndDraw(revolving);
    vm.warp(date);
    _sameBlockCure(standard);
    _sameBlockCure(revolving);
    vm.warp(uint256(date) + 1);
    standard.market.updateState();
    revolving.market.updateState();
    assertEq(standard.market.defaultedAt(), 0, 'standard cured at cutoff');
    assertEq(revolving.market.defaultedAt(), 0, 'revolving cured at cutoff');
    assertEq(
      IWildcatMarketRevolving(address(revolving.market)).drawnAmount(),
      0,
      'closed principal'
    );
  }

  function _sameBlockCure(MatrixCell memory cell) private {
    cell.market.updateState();
    assertEq(cell.market.reserveRatioBips(), 10_000, 'repayment reserve');
    assertEq(cell.market.defaultedAt(), 0, 'inclusive date');
    cell.market.updateState();
    _repay(cell, 800e18);
    assertTrue(cell.market.isClosed(), 'full funding closes');
    assertEq(cell.market.defaultedAt(), 0, 'same-block cure');
  }

  function test_OneSecondLateRepaymentClosesButRecordsMissedDeadline() public {
    uint32 date = uint32(vm.getBlockTimestamp() + 1 days);
    MatrixCell memory standard = _cell(MatrixMarketKind.Standard, date, 0);
    MatrixCell memory revolving = _cell(MatrixMarketKind.Revolving, date, 0);
    _fundAndDraw(standard);
    _fundAndDraw(revolving);
    vm.warp(uint256(date) + 1);
    _lateCure(standard, date);
    _lateCure(revolving, date);
  }

  function _lateCure(MatrixCell memory cell, uint256 date) private {
    uint256 debts = cell.market.totalDebts();
    assertTrue(debts > 1_000e18, 'penalty from date without grace');
    _repay(cell, debts - cell.market.totalAssets());
    assertEq(cell.market.defaultedAt(), date, 'late funds do not rewrite deadline');
    assertTrue(cell.market.isClosed(), 'late funded closure');
    uint256 scale = cell.market.scaleFactor();
    vm.warp(vm.getBlockTimestamp() + 1);
    cell.market.updateState();
    assertEq(cell.market.scaleFactor(), scale, 'closed accrual frozen');
  }

  function test_RepaymentOpensPeriodicQueueButKeepsBatchExpiry() public {
    MatrixOptions memory options = _defaultMatrixOptions(
      MatrixHooksKind.PeriodicTerm,
      MatrixMarketKind.Standard
    );
    options.annualInterestBips = 0;
    options.delinquencyFeeBips = 0;
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 1 days);
    options.repaymentPeriod = 7 days;
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 9);
    _authorize(stack, cell, MatrixAlice);
    _fundAndDraw(cell);
    vm.prank(MatrixAlice);
    vm.expectRevert(PeriodicTermPolicy.WithdrawOutsideWindow.selector);
    cell.market.queueFullWithdrawal();
    vm.warp(options.repaymentDate);
    assertEq(cell.market.maximumDeposit(), 0, 'dated capacity');
    assertEq(cell.market.borrowableAssets(), 0, 'dated borrowing');
    vm.prank(MatrixBorrower);
    vm.expectRevert(WildcatMarketBase.MarketInRepayment.selector);
    cell.market.borrow(0);
    vm.prank(MatrixAlice);
    vm.expectRevert(WildcatMarketBase.MarketInRepayment.selector);
    cell.market.depositUpTo(1);
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueFullWithdrawal();
    assertEq(
      expiry,
      uint256(options.repaymentDate) + options.withdrawalBatchDuration,
      'normal batch duration'
    );
    vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchNotExpired.selector);
    cell.market.executeWithdrawal(MatrixAlice, expiry);
    vm.warp(uint256(expiry) + 1);
    assertEq(
      cell.market.executeWithdrawal(MatrixAlice, expiry),
      200e18,
      'allocated claim collectible'
    );
    assertFalse(cell.market.isClosed(), 'unpaid debt remains open');
  }

  function test_AutomaticClosureLeavesFullyBackedFifoForBoundedProcessing() public {
    uint256 start = vm.getBlockTimestamp();
    MatrixCell memory cell = _cell(MatrixMarketKind.Revolving, uint32(start + 4 days), 7 days);
    _deposit(stack, cell, MatrixAlice, 600e18);
    _deposit(stack, cell, MatrixBob, 400e18);
    _borrow(cell, 800e18);
    vm.prank(MatrixAlice);
    uint32 first = cell.market.queueFullWithdrawal();
    vm.warp(start + 2 days);
    vm.prank(MatrixBob);
    uint32 second = cell.market.queueFullWithdrawal();
    vm.warp(start + 4 days);
    _repay(cell, cell.market.totalDebts() - cell.market.totalAssets());
    assertTrue(cell.market.isClosed(), 'fully backed facility');
    assertEq(cell.market.getUnpaidBatchExpiries().length, 2, 'bounded close leaves FIFO');
    uint256 debts = cell.market.totalDebts();
    assertEq(cell.market.totalAssets(), debts, 'all claims backed');
    cell.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    assertEq(cell.market.getUnpaidBatchExpiries().length, 1, 'one batch per call');
    assertEq(cell.market.getUnpaidBatchExpiries()[0], second, 'FIFO order');
    cell.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    assertEq(cell.market.getUnpaidBatchExpiries().length, 0, 'allocation complete');
    uint256 firstPaid = cell.market.executeWithdrawal(MatrixAlice, first);
    uint256 secondPaid = cell.market.executeWithdrawal(MatrixBob, second);
    // two independently floored batch payments can leave one wei from the aggregate backing.
    // every scaled share must still settle; residual cash is not an unpaid lender claim.
    assertEq(firstPaid + secondPaid + cell.market.totalAssets(), debts, 'asset conservation');
    assertTrue(cell.market.totalAssets() <= 1, 'two-batch floor bound');
    assertEq(cell.market.totalDebts(), 0, 'no unpaid claims');
    assertEq(cell.market.scaledTotalSupply(), 0, 'no stranded scaled token');
    vm.prank(MatrixBorrower);
    vm.expectRevert(IMarketEventsAndErrors.RepayToClosedMarket.selector);
    cell.market.repayAndProcessUnpaidWithdrawalBatches(1, 1);
  }

  function test_NoDatePenaltyCutoffAllowsLaterSameBlockCure() public {
    MatrixCell memory cell = _cell(MatrixMarketKind.Standard, 0, 0);
    _fundAndDraw(cell);
    vm.prank(MatrixAlice);
    cell.market.queueFullWithdrawal();
    uint256 cutoff = vm.getBlockTimestamp() + cell.options.delinquencyGracePeriod + 90 days;
    vm.warp(cutoff);
    cell.market.updateState();
    assertEq(cell.market.defaultedAt(), 0, 'cutoff inclusive');
    _repay(cell, cell.market.coverageLiquidity() - cell.market.totalAssets());
    vm.warp(cutoff + 1);
    cell.market.updateState();
    assertEq(cell.market.defaultedAt(), 0, 'observed cure resets run');
    assertFalse(cell.market.isClosed(), 'no-date cure does not close');
  }

  function test_NoDateDefaultOnlyRecordsMarkerAndKeepsEconomics() public {
    MatrixCell memory cell = _cell(MatrixMarketKind.Standard, 0, 0);
    _fundAndDraw(cell);
    vm.prank(MatrixAlice);
    cell.market.queueWithdrawal(500e18);
    uint256 cutoff = vm.getBlockTimestamp() + cell.options.delinquencyGracePeriod + 90 days;
    vm.warp(cutoff + 1);
    cell.market.updateState();
    assertEq(cell.market.defaultedAt(), cutoff, 'historical penalty cutoff');
    assertFalse(cell.market.isClosed(), 'default is a marker');
    assertEq(cell.market.reserveRatioBips(), 2_000, 'reserve unchanged');
    uint256 scale = cell.market.scaleFactor();
    vm.warp(cutoff + 2 days);
    cell.market.updateState();
    assertTrue(cell.market.scaleFactor() > scale, 'penalty continues');
    assertEq(cell.market.defaultedAt(), cutoff, 'marker permanent');
    vm.prank(MatrixAlice);
    cell.market.queueFullWithdrawal();
  }

  function test_PeriodicViewsObserveAutomaticClosureAndRetireProposal() public {
    MatrixOptions memory options = _defaultMatrixOptions(
      MatrixHooksKind.PeriodicTerm,
      MatrixMarketKind.Standard
    );
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 70 days);
    options.repaymentPeriod = 7 days;
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 9);
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 1_000e18);
    PeriodicTermHooks hooks = PeriodicTermHooks(address(cell.hooks));
    vm.prank(MatrixBorrower);
    hooks.proposeAnnualInterestBips(address(cell.market), 500);
    stack.asset.mint(address(cell.market), 1_000e18);
    cell.market.updateState();
    vm.warp(options.repaymentDate);
    assertTrue(cell.market.isClosed(), 'live closure before write');
    assertTrue(hooks.getHookedMarket(address(cell.market)).isClosed, 'effective hook closure');
    assertTrue(hooks.isWithdrawalWindowOpen(address(cell.market)), 'closure opens schedule');
    (PendingAprChange memory proposal, , ) = hooks.getPendingAprChange(address(cell.market));
    assertEq(proposal.proposalTimestamp, 0, 'closed proposal hidden');
    vm.prank(MatrixBorrower);
    vm.expectRevert(PeriodicTermPolicy.AprReductionProposalOnClosedMarket.selector);
    hooks.proposeAnnualInterestBips(address(cell.market), 400);
    cell.market.updateState();
    assertTrue(cell.market.previousState().isClosed, 'closure committed');
    assertEq(cell.market.defaultedAt(), 0, 'funded at date');
  }

  function testFuzz_InclusiveDeadline(uint32 rawPeriod, bool late, bool revolving) public {
    uint32 period = uint32(bound(rawPeriod, 0, 90 days));
    uint32 date = uint32(vm.getBlockTimestamp() + 1 days);
    uint256 cutoff = uint256(date) + period;
    MatrixCell memory cell = _cell(
      revolving ? MatrixMarketKind.Revolving : MatrixMarketKind.Standard,
      date,
      period
    );
    _fundAndDraw(cell);
    vm.warp(cutoff);
    cell.market.updateState();
    uint256 expectedScale = RAY + MathUtils.calculateLinearInterestFromBips(1_000, period);
    assertEq(cell.market.scaleFactor(), expectedScale, 'whole-balance penalty from date');
    assertEq(cell.market.defaultedAt(), 0, 'cutoff is still curable');
    if (late) vm.warp(cutoff + 1);
    _repay(cell, cell.market.totalDebts() - cell.market.totalAssets());
    assertTrue(cell.market.isClosed(), 'repayment completion');
    assertEq(cell.market.defaultedAt(), late ? cutoff : 0, 'exact cutoff outcome');
    vm.warp(cutoff + 2);
    cell.market.updateState();
    assertEq(cell.market.defaultedAt(), late ? cutoff : 0, 'outcome permanent');
  }

  function test_ObservedCureResetsDefaultRunWithoutResettingPenaltyEconomics() public {
    uint256 start = vm.getBlockTimestamp();
    MatrixCell memory cell = _cell(MatrixMarketKind.Standard, 0, 0);
    _fundAndDraw(cell);
    vm.prank(MatrixAlice);
    cell.market.queueFullWithdrawal();
    uint256 cureAt = start + 30 days;
    vm.warp(cureAt);
    _repay(cell, cell.market.coverageLiquidity() - cell.market.totalAssets());
    uint256 timer = cell.market.previousState().timeDelinquent;
    assertTrue(timer > cell.options.delinquencyGracePeriod, 'economic timer retained');
    vm.warp(cureAt + 1);
    cell.market.updateState();
    assertEq(cell.market.previousState().timeDelinquent, timer - 1, 'normal healthy decay');
    assertTrue(
      cell.market.previousState().isDelinquent,
      'healthy-tail fees create a new shortfall'
    );
    vm.warp(start + cell.options.delinquencyGracePeriod + 90 days + 1);
    cell.market.updateState();
    assertEq(cell.market.defaultedAt(), 0, 'old run was cured');
    uint256 newCutoff = cureAt + 1 + 90 days;
    vm.warp(newCutoff + 1);
    cell.market.updateState();
    assertEq(cell.market.defaultedAt(), newCutoff, 'new run starts from observed shortfall');
  }

  function test_LateDonationCannotRewriteDeadlineOrEmitRepayment() public {
    uint32 date = uint32(vm.getBlockTimestamp() + 1 days);
    MatrixCell memory cell = _cell(MatrixMarketKind.Revolving, date, 0);
    _fundAndDraw(cell);
    stack.asset.mint(address(cell.market), 100e18);
    cell.market.updateState();
    assertEq(
      IWildcatMarketRevolving(address(cell.market)).drawnAmount(),
      800e18,
      'donation is not principal repayment'
    );
    vm.warp(uint256(date) + 1);
    stack.asset.mint(address(cell.market), 1_000e18);
    uint256 borrowerBefore = stack.asset.balanceOf(MatrixBorrower);
    uint256 excess = cell.market.totalAssets() - cell.market.totalDebts();
    vm.recordLogs();
    cell.market.updateState();
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i; i < logs.length; i++) {
      assertTrue(
        logs[i].topics[0] != keccak256('DebtRepaid(address,uint256)'),
        'no fabricated repayment'
      );
    }
    assertEq(cell.market.defaultedAt(), date, 'donation observed too late');
    assertTrue(cell.market.isClosed(), 'donation can back funded closure');
    assertEq(
      stack.asset.balanceOf(MatrixBorrower) - borrowerBefore,
      excess,
      'surplus returned to borrower'
    );
    assertEq(
      IWildcatMarketRevolving(address(cell.market)).drawnAmount(),
      0,
      'closure clears drawn principal'
    );
  }

  function test_AutomaticClosureWithdrawalViewMatchesExecutionBeforeOriginalExpiry() public {
    MatrixOptions memory options = _defaultMatrixOptions(
      MatrixHooksKind.OpenTerm,
      MatrixMarketKind.Standard
    );
    options.annualInterestBips = 0;
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 1 days);
    options.repaymentPeriod = 0;
    options.withdrawalBatchDuration = 3 days;
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 9);
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 1_000e18);
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueWithdrawal(500e18);
    vm.warp(options.repaymentDate);
    assertTrue(expiry > vm.getBlockTimestamp(), 'original expiry still in future');
    assertTrue(cell.market.isClosed(), 'fully funded closure visible before write');
    assertEq(
      cell.market.getAvailableWithdrawalAmount(MatrixAlice, expiry),
      500e18,
      'live closed claim'
    );
    assertEq(cell.market.executeWithdrawal(MatrixAlice, expiry), 500e18, 'same claim executes');
    assertEq(cell.market.defaultedAt(), 0, 'timely completion');
    vm.prank(MatrixAlice);
    uint32 freshExpiry = cell.market.queueFullWithdrawal();
    vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchNotExpired.selector);
    cell.market.getAvailableWithdrawalAmount(MatrixAlice, freshExpiry);
    vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchNotExpired.selector);
    cell.market.executeWithdrawal(MatrixAlice, freshExpiry);
    vm.warp(uint256(freshExpiry) + 1);
    assertEq(
      cell.market.getAvailableWithdrawalAmount(MatrixAlice, freshExpiry),
      500e18,
      'fresh batch expired'
    );
    assertEq(
      cell.market.executeWithdrawal(MatrixAlice, freshExpiry),
      500e18,
      'fresh batch collectible'
    );
  }
}

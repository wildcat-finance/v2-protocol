// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketLensLifecycle.t
// ║  ██▀▀     ▀▀██   Lifecycle lens parity through repayment, default, and closure.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  FIXTURE
// ║  setUp()
// ║  _cell(...)
// ║  _options(...)
// ║  _fundAndBorrow(...)
// ║
// ║  REPAYMENT AND DEFAULT DATA
// ║  test_repaymentMatrix_AccruedPhaseAndRecordedDefaultStayDistinct()
// ║  test_zeroPeriod_ExactDateCureAndLateDefault()
// ║  test_noRepaymentTerms_StillReportsOrdinaryPenaltyDefault()
// ║
// ║  CLOSURE AND PROPOSAL DATA
// ║  test_automaticClosure_ReleasesFutureBatchAndProtectsClaimsFromRecovery()
// ║  test_manualClosureBeforeDate_DoesNotReenterRepayment()
// ║  test_periodicProposal_ExposesRecordedWindowAndAccruedClosure()
// ║
// ║  ROUTE PARITY
// ║  test_routes_FullLiveLenderAggregatedAndFacadeCarryNewData()
// ║  _assertReads(...)
// ╚═════

import { MarketLens } from 'src/lens/MarketLens.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { MarketLensLive } from 'src/lens/MarketLensLive.sol';
import { MarketLensAggregator } from 'src/lens/MarketLensAggregator.sol';
import { MarketDataV2_5 } from 'src/lens/MarketData.sol';
import { MarketLiveDataV2_5 } from 'src/lens/MarketLiveData.sol';
import { BatchStatus, WithdrawalBatchDataWithLenderStatus } from 'src/lens/WithdrawalBatchData.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

// ┌─ MarketLensLifecycleTest ──────────────────────────────────────────────────
contract MarketLensLifecycleTest is ProductionMatrixFixture {
  ProductionStack internal stack;
  MarketLensCore internal core;
  MarketLensLive internal live;
  MarketLensAggregator internal aggregator;
  MarketLens internal lens;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    stack = _deployProductionStack();
    bytes memory args = abi.encode(address(stack.archController), address(stack.standardFactory));
    core = MarketLensCore(_deployCode('src/lens/MarketLensCore.sol:MarketLensCore', args));
    live = MarketLensLive(_deployCode('src/lens/MarketLensLive.sol:MarketLensLive', args));
    aggregator = MarketLensAggregator(_deployCode('src/lens/MarketLensAggregator.sol:MarketLensAggregator', args));
    lens = MarketLens(
      _deployCode(
        'src/lens/MarketLens.sol:MarketLens',
        abi.encode(
          address(stack.archController),
          address(stack.standardFactory),
          address(core),
          address(aggregator),
          address(live)
        )
      )
    );
  }

  // ┌─ _cell ─────
  function _cell(MatrixOptions memory options, uint96 nonce) internal returns (MatrixCell memory cell) {
    cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, nonce);
    _authorize(stack, cell, MatrixAlice);
  }

  // ┌─ _options ─────
  function _options(
    MatrixMarketKind kind,
    MatrixHooksKind hooksKind,
    uint32 period
  )
    internal
    view
    returns (MatrixOptions memory options)
  {
    options = _defaultMatrixOptions(hooksKind, kind);
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    options.delinquencyFeeBips = 0;
    options.fixedTermDuration = 1 days;
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 2 days);
    options.repaymentPeriod = period;
  }

  // ┌─ _fundAndBorrow ─────
  function _fundAndBorrow(MatrixCell memory cell) internal {
    _deposit(stack, cell, MatrixAlice, 100e18);
    _borrow(cell, 80e18);
    _approveBorrower(stack, cell, 100e18);
  }

  // ░░▒▒▓▓██ [ REPAYMENT AND DEFAULT DATA ] ───────────────────────────────────

  // ┌─ test_repaymentMatrix_AccruedPhaseAndRecordedDefaultStayDistinct ─────
  function test_repaymentMatrix_AccruedPhaseAndRecordedDefaultStayDistinct() external {
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _cell(_options(MatrixMarketKind(i / 3), MatrixHooksKind(i % 3), 1 days), uint96(i));
      _fundAndBorrow(cell);
      _assertReads(cell, false);
      uint256 lastWrite = cell.market.previousState().lastInterestAccruedTimestamp;
      vm.warp(cell.options.repaymentDate);
      MarketDataV2_5 memory data = _assertReads(cell, true);
      assertEq(data.market.reserveRatioBips, 10_000, 'repayment reserves');
      assertEq(data.liquidity.maximumDeposit, 0, 'deposits stopped');
      assertEq(data.liquidity.borrowableAssets, 0, 'borrowing stopped');
      assertEq(cell.market.previousState().lastInterestAccruedTimestamp, lastWrite, 'read did not write');
      if (cell.options.hooksKind == MatrixHooksKind.PeriodicTerm) {
        assertTrue(data.market.hooksConfig.periodicWithdrawalWindowOpen, 'repayment opens queue');
      }

      uint256 deadline = cell.market.repaymentDeadline();
      vm.warp(deadline);
      cell.market.updateState();
      assertEq(_assertReads(cell, true).lifecycle.defaultedAt, 0, 'deadline second still open');
      vm.warp(deadline + 1);
      assertEq(_assertReads(cell, true).lifecycle.defaultedAt, 0, 'unwritten default not fabricated');
      cell.market.updateState();
      assertEq(_assertReads(cell, true).lifecycle.defaultedAt, deadline, 'recorded historical default');
      _repay(cell, 80e18);
      data = _assertReads(cell, false);
      assertTrue(data.market.isClosed, 'funding closes');
      assertEq(data.lifecycle.defaultedAt, deadline, 'closure preserves default');
    }
  }

  // ┌─ test_zeroPeriod_ExactDateCureAndLateDefault ─────
  function test_zeroPeriod_ExactDateCureAndLateDefault() external {
    for (uint256 i; i < 2; i++) {
      MatrixCell memory cell = _cell(_options(MatrixMarketKind(i), MatrixHooksKind.OpenTerm, 0), uint96(i));
      _fundAndBorrow(cell);
      vm.warp(cell.options.repaymentDate);
      MarketDataV2_5 memory data = _assertReads(cell, true);
      assertEq(data.lifecycle.repaymentPeriod, 0, 'zero period is valid');
      assertEq(data.lifecycle.repaymentDeadline, cell.options.repaymentDate, 'date equals deadline');
      if (i == 1) vm.warp(uint256(cell.options.repaymentDate) + 1);
      _repay(cell, 80e18);
      data = _assertReads(cell, false);
      assertEq(data.lifecycle.defaultedAt, i == 1 ? cell.options.repaymentDate : 0, 'inclusive cure');
    }
  }

  // ┌─ test_noRepaymentTerms_StillReportsOrdinaryPenaltyDefault ─────
  function test_noRepaymentTerms_StillReportsOrdinaryPenaltyDefault() external {
    MatrixOptions memory options = _options(MatrixMarketKind.Standard, MatrixHooksKind.OpenTerm, 0);
    options.repaymentDate = 0;
    options.delinquencyGracePeriod = 0;
    MatrixCell memory cell = _cell(options, 0);
    _fundAndBorrow(cell);
    vm.prank(MatrixAlice);
    cell.market.queueFullWithdrawal();
    cell.market.updateState();
    uint256 cutoff = vm.getBlockTimestamp() + 90 days;
    vm.warp(cutoff + 1);
    assertEq(_assertReads(cell, false).lifecycle.defaultedAt, 0, 'stored marker before update');
    cell.market.updateState();
    MarketDataV2_5 memory data = _assertReads(cell, false);
    assertEq(data.lifecycle.repaymentDate, 0, 'no scheduled repayment');
    assertEq(data.lifecycle.repaymentDeadline, 0, 'no deadline');
    assertEq(data.lifecycle.defaultedAt, cutoff, 'ordinary penalty default');
    assertFalse(data.market.isClosed, 'default is only a marker');
  }

  // ░░▒▒▓▓██ [ CLOSURE AND PROPOSAL DATA ] ────────────────────────────────────

  // ┌─ test_automaticClosure_ReleasesFutureBatchAndProtectsClaimsFromRecovery ─────
  function test_automaticClosure_ReleasesFutureBatchAndProtectsClaimsFromRecovery() external {
    for (uint256 i; i < 2; i++) {
      MatrixOptions memory options = _options(MatrixMarketKind(i), MatrixHooksKind.OpenTerm, 1 days);
      options.withdrawalBatchDuration = 7 days;
      MatrixCell memory cell = _cell(options, uint96(i));
      _deposit(stack, cell, MatrixAlice, 100e18);
      vm.prank(MatrixAlice);
      uint32 expiry = cell.market.queueWithdrawal(40e18);
      WithdrawalBatchDataWithLenderStatus memory batch =
        core.getWithdrawalBatchDataWithLenderStatus(address(cell.market), expiry, MatrixAlice);
      assertEq(uint256(batch.batch.status), uint256(BatchStatus.Pending), 'scheduled batch');
      assertEq(batch.batch.normalizedAmountPaid, 40e18, 'reserved assets');
      assertEq(batch.lenderStatus.normalizedAmountOwed, 40e18, 'full claim');
      assertEq(batch.lenderStatus.availableWithdrawalAmount, 0, 'not collectible while pending');
      vm.expectRevert(bytes4(keccak256('WithdrawalBatchNotExpired()')));
      cell.market.getAvailableWithdrawalAmount(MatrixAlice, expiry);

      stack.asset.mint(address(cell.market), 7e18);
      assertEq(_assertReads(cell, false).liquidity.recoverableUnderlying, 0, 'open-market donation not recoverable');
      vm.warp(options.repaymentDate);
      MarketDataV2_5 memory data = _assertReads(cell, false);
      assertFalse(cell.market.previousState().isClosed, 'closure still unwritten');
      assertTrue(data.market.isClosed, 'accrued closure');
      assertEq(data.liquidity.totalDebts, 100e18, 'live shares plus paid claims');
      assertEq(data.liquidity.recoverableUnderlying, 7e18, 'only surplus recoverable');
      batch = lens.getWithdrawalBatchDataWithLenderStatus(address(cell.market), expiry, MatrixAlice);
      assertEq(uint256(batch.batch.status), uint256(BatchStatus.Complete), 'released before expiry');
      assertEq(batch.lenderStatus.availableWithdrawalAmount, 40e18, 'claim collectible');
      assertEq(
        batch.lenderStatus.availableWithdrawalAmount,
        cell.market.getAvailableWithdrawalAmount(MatrixAlice, expiry),
        'market agrees'
      );

      uint256 borrowerBalance = stack.asset.balanceOf(MatrixBorrower);
      vm.prank(MatrixBorrower);
      cell.market.rescueTokens(address(stack.asset));
      assertEq(
        stack.asset.balanceOf(MatrixBorrower) - borrowerBalance,
        data.liquidity.recoverableUnderlying,
        'recovered lens amount'
      );
      assertEq(_assertReads(cell, false).liquidity.recoverableUnderlying, 0, 'surplus swept');
      uint256 lenderBalance = stack.asset.balanceOf(MatrixAlice);
      cell.market.executeWithdrawal(MatrixAlice, expiry);
      assertEq(stack.asset.balanceOf(MatrixAlice) - lenderBalance, 40e18, 'lender paid');
      batch = core.getWithdrawalBatchDataWithLenderStatus(address(cell.market), expiry, MatrixAlice);
      assertEq(batch.lenderStatus.availableWithdrawalAmount, 0, 'claimed amount removed');
      assertEq(batch.lenderStatus.normalizedAmountOwed, 0, 'claim satisfied');
    }
  }

  // ┌─ test_manualClosureBeforeDate_DoesNotReenterRepayment ─────
  function test_manualClosureBeforeDate_DoesNotReenterRepayment() external {
    MatrixCell memory cell = _cell(_options(MatrixMarketKind.Standard, MatrixHooksKind.OpenTerm, 1 days), 0);
    _close(cell);
    vm.warp(uint256(cell.options.repaymentDate) + 2 days);
    MarketDataV2_5 memory data = _assertReads(cell, false);
    assertTrue(data.market.isClosed, 'remains closed');
    assertEq(data.lifecycle.defaultedAt, 0, 'no debt to default');
  }

  // ┌─ test_periodicProposal_ExposesRecordedWindowAndAccruedClosure ─────
  function test_periodicProposal_ExposesRecordedWindowAndAccruedClosure() external {
    MatrixOptions memory options = _options(MatrixMarketKind.Standard, MatrixHooksKind.PeriodicTerm, 1 days);
    options.annualInterestBips = 1_000;
    MatrixCell memory cell = _cell(options, 0);
    MarketDataV2_5 memory data = _assertReads(cell, false);
    assertTrue(data.market.hooksConfig.pendingAprChange.isPresent, 'proposal getter supported');
    assertEq(data.market.hooksConfig.pendingAprChange.proposalTimestamp, 0, 'no proposal');
    assertFalse(data.market.hooksConfig.periodicWithdrawalWindowOpen, 'before window');
    vm.prank(MatrixBorrower);
    PeriodicTermHooks(address(cell.hooks)).proposeAnnualInterestBips(address(cell.market), 500);
    data = _assertReads(cell, false);
    assertEq(data.market.hooksConfig.pendingAprChange.annualInterestBips, 500, 'proposed APR');
    assertEq(data.market.hooksConfig.pendingAprChange.proposalTimestamp, vm.getBlockTimestamp(), 'proposal time');
    assertEq(
      data.market.hooksConfig.pendingAprChange.responseWindowStart,
      cell.deployedAt + options.firstWindowDelay,
      'recorded start'
    );
    assertEq(
      data.market.hooksConfig.pendingAprChange.responseWindowEnd,
      cell.deployedAt + options.firstWindowDelay + options.withdrawalWindowDuration,
      'recorded end'
    );
    vm.warp(options.repaymentDate);
    data = _assertReads(cell, false);
    assertTrue(data.market.isClosed, 'empty market closes at date');
    assertFalse(cell.market.previousState().isClosed, 'closure not yet written');
    assertTrue(data.market.hooksConfig.periodicTermClosed, 'hook closure agrees');
    assertTrue(data.market.hooksConfig.periodicWithdrawalWindowOpen, 'closed window open');
    assertTrue(data.market.hooksConfig.pendingAprChange.isPresent, 'getter still present');
    assertEq(data.market.hooksConfig.pendingAprChange.proposalTimestamp, 0, 'accrued closure clears proposal view');
  }

  // ░░▒▒▓▓██ [ ROUTE PARITY ] ─────────────────────────────────────────────────

  // ┌─ test_routes_FullLiveLenderAggregatedAndFacadeCarryNewData ─────
  function test_routes_FullLiveLenderAggregatedAndFacadeCarryNewData() external {
    address[] memory markets = new address[](6);
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _cell(_options(MatrixMarketKind(i / 3), MatrixHooksKind(i % 3), 1 days), uint96(i));
      _fundAndBorrow(cell);
      markets[i] = address(cell.market);
      address wrapper = stack.wrapperFactory.createWrapper(markets[i]);
      MarketDataV2_5 memory data = _assertReads(cell, false);
      assertEq(data.registeredWrapper, wrapper, 'actual registered wrapper');
      assertEq(abi.encode(lens.getMarketDataV2(markets[i])), abi.encode(data), 'facade single');
      assertEq(
        abi.encode(
          aggregator.getAllMarketsDataV2ForHooksTemplate(
            address(_factoryFor(stack, cell.options.marketKind)), cell.hooksTemplate
          )[0]
        ),
        abi.encode(data),
        'factory aggregation'
      );
      assertEq(
        abi.encode(
          lens.getPaginatedMarketsDataV2ForHooksTemplate(
            address(_factoryFor(stack, cell.options.marketKind)), cell.hooksTemplate, 0, 1
          )[0]
        ),
        abi.encode(data),
        'facade pagination'
      );
    }
    assertEq(abi.encode(lens.getMarketsDataV2(markets)), abi.encode(core.getMarketsDataV2(markets)), 'facade full list');
    assertEq(
      abi.encode(lens.getMarketsLiveDataV2(markets)), abi.encode(live.getMarketsLiveDataV2(markets)), 'facade live list'
    );
    assertEq(
      abi.encode(lens.getMarketsLiveDataWithLenderStatusV2(MatrixAlice, markets)),
      abi.encode(live.getMarketsLiveDataWithLenderStatusV2(MatrixAlice, markets)),
      'facade live lender list'
    );
    for (uint256 i; i < 3; i++) {
      MarketDataV2_5[] memory all = lens.getAggregatedAllMarketsDataV2ForHooksTemplate(stack.hooksTemplates[i]);
      assertEq(all.length, 2, 'both factories aggregated');
      assertEq(abi.encode(all[0]), abi.encode(core.getMarketDataV2(markets[i])), 'standard aggregate');
      assertEq(abi.encode(all[1]), abi.encode(core.getMarketDataV2(markets[i + 3])), 'revolving aggregate');
    }
  }

  // ┌─ _assertReads ─────
  function _assertReads(MatrixCell memory cell, bool inRepayment) internal view returns (MarketDataV2_5 memory data) {
    data = core.getMarketDataV2(address(cell.market));
    assertTrue(data.lifecycle.isPresent, 'lifecycle supported');
    assertEq(data.lifecycle.repaymentDate, cell.market.repaymentDate(), 'repayment date');
    assertEq(data.lifecycle.repaymentPeriod, cell.market.repaymentPeriod(), 'repayment period');
    assertEq(data.lifecycle.repaymentDeadline, cell.market.repaymentDeadline(), 'inclusive deadline');
    assertEq(data.lifecycle.defaultedAt, cell.market.defaultedAt(), 'committed marker');
    assertEq(data.lifecycle.isInRepayment, inRepayment, 'repayment phase');
    assertEq(data.market.isClosed, cell.market.isClosed(), 'accrued closure');
    assertEq(data.liquidity.maximumDeposit, cell.market.maximumDeposit(), 'deposit capacity');
    assertEq(data.liquidity.borrowableAssets, cell.market.borrowableAssets(), 'borrow capacity');
    assertEq(data.liquidity.totalDebts, cell.market.totalDebts(), 'all liabilities');
    assertEq(data.registeredWrapper, cell.market.registeredWrapper(), 'registered wrapper');
    assertTrue(data.market.hooks.repaymentConstraintsAvailable, 'repayment constraints supported');
    assertTrue(data.market.hooks.hooksTemplate.initCodeHash.isPresent, 'code hash supported');
    assertEq(
      data.market.hooks.hooksTemplate.initCodeHash.value,
      _factoryFor(stack, cell.options.marketKind).getHooksTemplateInitCodeHash(cell.hooksTemplate),
      'factory commitment'
    );
    address[] memory markets = new address[](1);
    markets[0] = address(cell.market);
    MarketLiveDataV2_5 memory current = live.getMarketsLiveDataV2(markets)[0];
    assertEq(abi.encode(current.lifecycle), abi.encode(data.lifecycle), 'live lifecycle parity');
    assertEq(abi.encode(current.liquidity), abi.encode(data.liquidity), 'live liquidity parity');
    assertEq(current.isClosed, data.market.isClosed, 'live closure parity');
    assertEq(abi.encode(current.commitmentFeeBips), abi.encode(data.commitmentFeeBips), 'commitment fee parity');
    assertEq(abi.encode(current.drawnAmount), abi.encode(data.drawnAmount), 'drawn principal parity');
  }
}

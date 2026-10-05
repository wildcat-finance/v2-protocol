// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketSurplus.t
//  \ ^ /   Closure funding, surplus recovery, and transfer rejection tests.
//    V
//
//  FIXTURE
//  setUp()
//  _fixture(...)
//  _deployFixtureDependencies()
//  _reject(...)
//
//  MARKET CLOSURE
//  test_lenderActionsCanCommitClosureWithRejectedBorrower()
//  _lenderAction(...)
//  test_exactFundingClosesEvenWhenBorrowerRejectsTransfers()
//  test_automaticClosureDoesNotPushSurplus()
//  test_repaymentCanCloseWithSurplusAndRejectedBorrower()
//  _assertClosed(...)
//
//  SURPLUS RECOVERY
//  test_surplusRecoveryPreservesEveryLiabilityAndBatchExit()
//  test_surplusRecoveryRequiresBorrowerAndClosedMarket()
//  test_surplusRecoveryCanCommitEffectiveClosure()
//  test_surplusRecoveryFollowsTransferredBorrowerAuthority()
//  test_failedRecoveryRollsBackEffectiveClosureAndStillAllowsCollection()
//  test_manualClosureWithoutTermsAllowsLaterDonationRecovery()
// ═════

import { MarketFixture } from '../shared/MarketFixture.sol';
import { RecipientRejectingERC20 } from '../mocks/RecipientRejectingERC20.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { Vm } from 'forge-std/Vm.sol';

// ┌─ MarketSurplusTest ────────────────────────────────────────────────────────
contract MarketSurplusTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() public {
    vm.warp(1_800_000_000);
  }

  // ┌─ _fixture ─────
  function _fixture(bool revolving, bool interest) private returns (Fixture memory fixture) {
    Options memory options = _defaultOptions(HooksKind.OpenTerm);
    options.revolving = revolving;
    options.annualInterestBips = interest ? 1_000 : 0;
    options.commitmentFeeBips = interest ? 500 : 0;
    options.delinquencyFeeBips = 0;
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 3 days);
    options.repaymentPeriod = 10 days;
    fixture = _newMarket(options);
    _deposit(fixture, Holder, 1_000e18);
    _fundAndApprove(fixture, Borrower, 10_000e18);
  }

  // ┌─ _deployFixtureDependencies ─────
  function _deployFixtureDependencies() internal override returns (Fixture memory fixture) {
    fixture = super._deployFixtureDependencies();
    fixture.asset =
      RecipientRejectingERC20(_deployCode('test/mocks/RecipientRejectingERC20.sol:RecipientRejectingERC20'));
  }

  // ┌─ _reject ─────
  function _reject(Fixture memory fixture, bool returnsFalse) private {
    RecipientRejectingERC20(address(fixture.asset)).rejectRecipient(Borrower, returnsFalse);
  }

  // ░░▒▒▓▓██ [ MARKET CLOSURE ] ───────────────────────────────────────────────

  // ┌─ test_lenderActionsCanCommitClosureWithRejectedBorrower ─────
  function test_lenderActionsCanCommitClosureWithRejectedBorrower() external {
    for (uint256 model; model < 2; ++model) {
      for (uint256 action; action < 10; ++action) {
        Fixture memory fixture = _fixture(model != 0, true);
        fixture.asset.mint(address(fixture.market), 50e18);
        vm.prank(Holder);
        uint32 expiry = fixture.market.queueWithdrawal(500e18);
        _reject(fixture, action % 2 != 0);
        vm.warp(uint256(fixture.market.repaymentDate()) + 1);
        uint256 borrowerBefore = fixture.asset.balanceOf(Borrower);
        vm.recordLogs();
        _lenderAction(fixture, expiry, action);
        _assertClosed(fixture, model != 0);
        uint256 scale = fixture.market.scaleFactor();
        vm.warp(vm.getBlockTimestamp() + 1);
        fixture.market.updateState();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 closures;
        for (uint256 i; i < logs.length; ++i) {
          if (logs[i].topics[0] == keccak256('MarketClosed(address,uint256)')) ++closures;
        }
        assertEq(closures, 1, 'closure emitted once');
        assertEq(fixture.market.scaleFactor(), scale, 'closed accrual frozen');
        assertEq(fixture.asset.balanceOf(Borrower), borrowerBefore, 'no borrower payout');
      }
    }
  }

  // ┌─ _lenderAction ─────
  function _lenderAction(Fixture memory fixture, uint32 expiry, uint256 action) private {
    if (action == 0) {
      vm.prank(Holder);
      fixture.market.queueWithdrawal(1e18);
    } else if (action == 1) {
      vm.prank(Holder);
      fixture.market.queueWithdrawalScaled(1e18);
    } else if (action == 2) {
      vm.prank(Holder);
      fixture.market.queueFullWithdrawal();
    } else if (action == 3) {
      assertEq(fixture.market.executeWithdrawal(Holder, expiry), 500e18, 'paid claim');
    } else if (action == 4) {
      address[] memory accounts = new address[](1);
      uint32[] memory expiries = new uint32[](1);
      accounts[0] = Holder;
      expiries[0] = expiry;
      assertEq(fixture.market.executeWithdrawals(accounts, expiries)[0], 500e18, 'bulk paid claim');
    } else if (action == 5) {
      fixture.market.updateState();
    } else if (action == 6) {
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    } else if (action == 7) {
      vm.prank(Holder);
      fixture.market.transfer(Recipient, 1e18);
    } else if (action == 8) {
      vm.prank(Holder);
      fixture.market.approve(Recipient, 1e18);
      vm.prank(Recipient);
      fixture.market.transferFrom(Holder, Recipient, 1e18);
    } else {
      uint256 fees = fixture.market.currentState().accruedProtocolFees;
      assertTrue(fees > 0, 'fee collection exercised');
      fixture.market.collectFees();
      assertEq(fixture.asset.balanceOf(FeeRecipient), fees, 'protocol fees collected');
    }
  }

  // ┌─ test_exactFundingClosesEvenWhenBorrowerRejectsTransfers ─────
  function test_exactFundingClosesEvenWhenBorrowerRejectsTransfers() external {
    for (uint256 model; model < 2; ++model) {
      Fixture memory fixture = _fixture(model != 0, false);
      _reject(fixture, false);
      vm.warp(fixture.market.repaymentDate());
      fixture.market.updateState();
      _assertClosed(fixture, model != 0);
    }
  }

  // ┌─ test_automaticClosureDoesNotPushSurplus ─────
  function test_automaticClosureDoesNotPushSurplus() external {
    for (uint256 model; model < 2; ++model) {
      for (uint256 mode; mode < 2; ++mode) {
        Fixture memory fixture = _fixture(model != 0, mode != 0);
        fixture.asset.mint(address(fixture.market), 50e18);
        fixture.market.updateState();
        uint256 borrowerBefore = fixture.asset.balanceOf(Borrower);
        _reject(fixture, mode != 0);
        vm.warp(uint256(fixture.market.repaymentDate()) + 30 days);
        fixture.market.updateState();
        _assertClosed(fixture, model != 0);
        assertEq(fixture.asset.balanceOf(Borrower), borrowerBefore, 'surplus retained');
        assertEq(fixture.market.totalAssets(), 1_050e18, 'all cash retained');
      }
    }
  }

  // ┌─ test_repaymentCanCloseWithSurplusAndRejectedBorrower ─────
  function test_repaymentCanCloseWithSurplusAndRejectedBorrower() external {
    for (uint256 model; model < 2; ++model) {
      for (uint256 mode; mode < 2; ++mode) {
        Fixture memory fixture = _fixture(model != 0, mode != 0);
        vm.prank(Borrower);
        fixture.market.borrow(800e18);
        vm.warp(fixture.market.repaymentDate());
        fixture.market.updateState();
        uint256 amount = fixture.market.totalDebts() - fixture.market.totalAssets() + 50e18;
        _reject(fixture, mode != 0);
        vm.prank(Borrower);
        fixture.market.repay(amount);
        _assertClosed(fixture, model != 0);
        assertEq(fixture.market.totalAssets() - fixture.market.totalDebts(), 50e18, 'excess retained');
      }
    }
  }

  // ┌─ _assertClosed ─────
  function _assertClosed(Fixture memory fixture, bool revolving) private view {
    assertTrue(fixture.market.previousState().isClosed, 'closure committed');
    assertTrue(fixture.market.totalAssets() >= fixture.market.totalDebts(), 'claims fully backed');
    if (revolving) {
      assertEq(IWildcatMarketRevolving(address(fixture.market)).drawnAmount(), 0, 'principal cleared');
    }
  }

  // ░░▒▒▓▓██ [ SURPLUS RECOVERY ] ─────────────────────────────────────────────

  // ┌─ test_surplusRecoveryPreservesEveryLiabilityAndBatchExit ─────
  function test_surplusRecoveryPreservesEveryLiabilityAndBatchExit() external {
    for (uint256 model; model < 2; ++model) {
      Fixture memory fixture = _fixture(model != 0, true);
      vm.prank(Borrower);
      fixture.market.borrow(800e18);
      vm.prank(Holder);
      uint32 oldExpiry = fixture.market.queueWithdrawal(400e18);
      vm.warp(uint256(fixture.market.repaymentDate()) - 1 days + 1);
      fixture.market.updateState();
      vm.prank(Holder);
      uint32 currentExpiry = fixture.market.queueWithdrawal(100e18);
      vm.warp(fixture.market.repaymentDate());
      uint256 amount = fixture.market.totalDebts() - fixture.market.totalAssets() + 50e18;
      _reject(fixture, model != 0);
      vm.prank(Borrower);
      fixture.market.repay(amount);
      _assertClosed(fixture, model != 0);

      MarketState memory state = fixture.market.previousState();
      assertTrue(state.scaledTotalSupply > 0, 'live supply still owed');
      assertTrue(state.scaledPendingWithdrawals > 0, 'old unpaid shares still owed');
      assertTrue(state.normalizedUnclaimedWithdrawals > 0, 'paid claims still owed');
      assertTrue(state.accruedProtocolFees > 0, 'protocol fees still owed');
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 1, 'old batch awaits processing');
      uint256 cash = fixture.market.totalAssets();
      uint256 debts = fixture.market.totalDebts();
      vm.prank(Borrower);
      vm.expectRevert(LibERC20.TransferFailed.selector);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(fixture.market.totalAssets(), cash, 'failed sweep preserves cash');
      assertEq(fixture.market.totalDebts(), debts, 'failed sweep preserves claims');

      RecipientRejectingERC20(address(fixture.asset)).rejectRecipient(address(0), false);
      uint256 borrowerBefore = fixture.asset.balanceOf(Borrower);
      vm.prank(Borrower);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(fixture.asset.balanceOf(Borrower) - borrowerBefore, cash - debts, 'only surplus');
      assertEq(fixture.market.totalAssets(), debts, 'all liabilities remain backed');
      vm.prank(Borrower);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(fixture.market.totalAssets(), debts, 'no double sweep');

      // rejecting the borrower again cannot block FIFO processing or any lender collection.
      _reject(fixture, model != 0);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      assertEq(fixture.market.getUnpaidBatchExpiries().length, 0, 'old batch processed');
      assertTrue(fixture.market.executeWithdrawal(Holder, oldExpiry) > 0, 'old claim collected');
      assertTrue(fixture.market.executeWithdrawal(Holder, currentExpiry) > 0, 'current claim collected');
      vm.prank(Holder);
      uint32 finalExpiry = fixture.market.queueFullWithdrawal();
      vm.warp(uint256(finalExpiry) + 1);
      fixture.market.updateState();
      assertTrue(fixture.market.executeWithdrawal(Holder, finalExpiry) > 0, 'remaining supply collected');
      fixture.market.collectFees();
      assertEq(fixture.market.scaledTotalSupply(), 0, 'all shares settled');
      assertEq(fixture.market.currentState().accruedProtocolFees, 0, 'fees collected');
      assertTrue(fixture.market.totalAssets() >= fixture.market.totalDebts(), 'rounding liabilities protected');
    }
  }

  // ┌─ test_surplusRecoveryRequiresBorrowerAndClosedMarket ─────
  function test_surplusRecoveryRequiresBorrowerAndClosedMarket() external {
    for (uint256 model; model < 2; ++model) {
      Fixture memory fixture = _fixture(model != 0, false);
      fixture.asset.mint(address(fixture.market), 50e18);
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.BadRescueAsset.selector);
      fixture.market.rescueTokens(address(fixture.asset));
      vm.warp(fixture.market.repaymentDate());
      fixture.market.updateState();
      vm.prank(Holder);
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.rescueTokens(address(fixture.asset));
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.BadRescueAsset.selector);
      fixture.market.rescueTokens(address(fixture.market));
      vm.prank(Borrower);
      fixture.market.rescueTokens(address(fixture.asset));
      uint256 borrowerBefore = fixture.asset.balanceOf(Borrower);
      fixture.asset.mint(address(fixture.market), 7e18);
      vm.prank(Borrower);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(fixture.asset.balanceOf(Borrower) - borrowerBefore, 7e18, 'later donation recovered');
      assertEq(fixture.market.totalAssets(), fixture.market.totalDebts(), 'lender backing unchanged');
    }
  }

  // ┌─ test_surplusRecoveryCanCommitEffectiveClosure ─────
  function test_surplusRecoveryCanCommitEffectiveClosure() external {
    for (uint256 model; model < 2; ++model) {
      Fixture memory fixture = _fixture(model != 0, true);
      fixture.asset.mint(address(fixture.market), 50e18);
      fixture.market.updateState();
      vm.warp(uint256(fixture.market.repaymentDate()) + 1);
      assertTrue(fixture.market.isClosed(), 'effective closure');
      assertFalse(fixture.market.previousState().isClosed, 'closure not yet written');
      vm.prank(Borrower);
      fixture.market.rescueTokens(address(fixture.asset));
      _assertClosed(fixture, model != 0);
      assertEq(fixture.market.totalAssets(), fixture.market.totalDebts(), 'sweep leaves every debt');
      assertEq(fixture.market.previousState().lastInterestAccruedTimestamp, vm.getBlockTimestamp(), 'state persisted');
    }
  }

  // ┌─ test_surplusRecoveryFollowsTransferredBorrowerAuthority ─────
  function test_surplusRecoveryFollowsTransferredBorrowerAuthority() external {
    for (uint256 model; model < 2; ++model) {
      Fixture memory fixture = _fixture(model != 0, false);
      fixture.asset.mint(address(fixture.market), 50e18);
      fixture.market.updateState();
      vm.warp(fixture.market.repaymentDate());
      fixture.market.updateState();
      fixture.archController.registerBorrower(Recipient);
      vm.prank(Borrower);
      fixture.market.requestBorrowerTransfer(Recipient);
      vm.prank(Recipient);
      fixture.market.acceptBorrowerTransfer();
      vm.prank(Borrower);
      vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
      fixture.market.rescueTokens(address(fixture.asset));
      vm.prank(Recipient);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(fixture.asset.balanceOf(Recipient), 50e18, 'current operational borrower');
      assertEq(fixture.market.totalAssets(), 1_000e18, 'lender backing retained');
    }
  }

  // ┌─ test_failedRecoveryRollsBackEffectiveClosureAndStillAllowsCollection ─────
  function test_failedRecoveryRollsBackEffectiveClosureAndStillAllowsCollection() external {
    for (uint256 model; model < 2; ++model) {
      Fixture memory fixture = _fixture(model != 0, true);
      vm.prank(Borrower);
      fixture.market.borrow(800e18);
      vm.prank(Holder);
      uint32 expiry = fixture.market.queueWithdrawal(200e18);
      fixture.asset.mint(address(fixture.market), 1_000e18);
      fixture.market.updateState();
      bytes32 stored = keccak256(abi.encode(fixture.market.previousState()));
      _reject(fixture, model != 0);
      vm.warp(uint256(fixture.market.repaymentDate()) + 1);
      assertTrue(fixture.market.isClosed(), 'effective closure');
      vm.prank(Borrower);
      vm.expectRevert(LibERC20.TransferFailed.selector);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(keccak256(abi.encode(fixture.market.previousState())), stored, 'failed recovery rolls back state');
      if (model != 0) {
        assertEq(IWildcatMarketRevolving(address(fixture.market)).drawnAmount(), 800e18, 'principal change rolled back');
      }
      assertEq(fixture.market.executeWithdrawal(Holder, expiry), 200e18, 'lender still collects');
      _assertClosed(fixture, model != 0);
    }
  }

  // ┌─ test_manualClosureWithoutTermsAllowsLaterDonationRecovery ─────
  function test_manualClosureWithoutTermsAllowsLaterDonationRecovery() external {
    for (uint256 model; model < 2; ++model) {
      Options memory options = _defaultOptions(HooksKind.OpenTerm);
      options.revolving = model != 0;
      Fixture memory fixture = _newMarket(options);
      _deposit(fixture, Holder, 1_000e18);
      vm.prank(Borrower);
      fixture.market.closeMarket();
      fixture.asset.mint(address(fixture.market), 7e18);
      vm.prank(Borrower);
      fixture.market.rescueTokens(address(fixture.asset));
      assertEq(fixture.asset.balanceOf(Borrower), 7e18, 'post-close donation recovered');
      assertEq(fixture.market.totalAssets(), 1_000e18, 'all lender backing retained');
    }
  }
}

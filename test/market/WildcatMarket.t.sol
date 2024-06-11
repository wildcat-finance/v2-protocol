// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import 'src/interfaces/IMarketEventsAndErrors.sol';
import 'src/libraries/MathUtils.sol';
import 'src/libraries/SafeCastLib.sol';
import 'src/libraries/MarketState.sol';
import 'solady/utils/SafeTransferLib.sol';
import { AccessControlHooksDataFuzzInputs, ExistingCredentialFuzzInputs } from '../helpers/fuzz/AccessControlHooksFuzzContext.sol';

contract WildcatMarketTest is BaseMarketTest {
  using stdStorage for StdStorage;
  using MathUtils for int256;
  using MathUtils for uint256;
  using SafeCastLib for uint256;

  // ===================================================================== //
  //                             updateState()                             //
  // ===================================================================== //

  function test_updateState() external {
    _deposit(alice, 1e18);
    fastForward(365 days);
    MarketState memory state = pendingState();
    updateState(state);
    market.updateState();
    assertEq(market.previousState(), state);
  }

  function test_updateState_NoChange() external {
    _deposit(alice, 1e18);
    MarketState memory state = pendingState();
    bytes32 stateHash = keccak256(abi.encode(state));
    market.updateState();
    assertEq(keccak256(abi.encode(market.previousState())), stateHash);
    assertEq(keccak256(abi.encode(market.currentState())), stateHash);
  }

  function test_updateState_HasPendingExpiredBatch() external {
    parameters.annualInterestBips = 3650;
    setUp();
    _deposit(alice, 1e18);
    _requestWithdrawal(alice, 1e18);
    uint32 timestamp = uint32(block.timestamp);
    uint32 expiry = previousState.pendingWithdrawalExpiry;
    fastForward(2 days);
    MarketState memory state = pendingState();
    vm.expectEmit(address(market));
    emit InterestAndFeesAccrued(timestamp, expiry, 1.001e27, 1e24, 0, 0);
    vm.expectEmit(address(market));
    emit WithdrawalBatchExpired(expiry, 1e18, 1e18, 1e18);
    vm.expectEmit(address(market));
    emit WithdrawalBatchClosed(expiry);
    uint256 scaleFactorDelta = uint(1.001e27).rayMul(.001e27);
    vm.expectEmit(address(market));
    emit InterestAndFeesAccrued(
      expiry,
      expiry + 1 days,
      uint256(1.001e27) + scaleFactorDelta,
      1e24,
      0,
      0
    );
    vm.expectEmit(address(market));
    emit StateUpdated(uint256(1.001e27) + scaleFactorDelta, false);
    market.updateState();
  }

  function test_updateState_HasPendingExpiredBatch_SameBlock() external {
    parameters.annualInterestBips = 3650;
    parameters.withdrawalBatchDuration = 0;
    setUpContracts(false, true);
    setUp();
    _deposit(alice, 1e18);
    _requestWithdrawal(alice, 1e18);
    uint32 timestamp = uint32(block.timestamp);
    fastForward(1 days);
    MarketState memory state = pendingState();
    vm.expectEmit(address(market));
    emit WithdrawalBatchExpired(timestamp, 1e18, 1e18, 1e18);
    vm.expectEmit(address(market));
    emit WithdrawalBatchClosed(timestamp);
    vm.expectEmit(address(market));
    emit InterestAndFeesAccrued(timestamp, timestamp + 1 days, uint256(1.001e27), 1e24, 0, 0);
    vm.expectEmit(address(market));
    emit StateUpdated(uint256(1.001e27), false);
    market.updateState();
  }

  // ===================================================================== //
  //                         depositUpTo(uint256)                          //
  // ===================================================================== //

  function test_depositUpTo() external asAccount(alice) {
    _deposit(alice, 50_000e18);
    assertEq(market.totalSupply(), 50_000e18);
    assertEq(market.balanceOf(alice), 50_000e18);
  }

  function test_depositUpTo(uint256 amount) external asAccount(alice) {
    amount = bound(amount, 1, DefaultMaximumSupply);
    market.depositUpTo(amount);
  }

  function test_depositUpTo_ApprovedOnController() public asAccount(bob) {
    _authorizeLender(bob);
    // @todo
    // vm.expectEmit(address(market));
    // emit AuthorizationStatusUpdated(bob, AuthRole.DepositAndWithdraw);
    market.depositUpTo(1e18);
    // @todo
    // assertEq(uint(market.getAccountRole(bob)), uint(AuthRole.DepositAndWithdraw));
  }

  function test_depositUpTo_NullMintAmount() external asAccount(alice) {
    vm.expectRevert(IMarketEventsAndErrors.NullMintAmount.selector);
    market.depositUpTo(0);
  }

  function testDepositUpTo_MaxSupplyExceeded() public asAccount(bob) {
    _authorizeLender(bob);
    asset.transfer(address(1), type(uint128).max);
    asset.mint(bob, DefaultMaximumSupply);
    asset.approve(address(market), DefaultMaximumSupply);
    market.depositUpTo(DefaultMaximumSupply - 1);
    market.depositUpTo(2);
    assertEq(market.balanceOf(bob), DefaultMaximumSupply);
    assertEq(asset.balanceOf(bob), 0);
  }

  function testDepositUpTo_NotApprovedLender() public asAccount(bob) {
    asset.mint(bob, 1e18);
    asset.approve(address(market), 1e18);
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedLender.selector);
    market.depositUpTo(1e18);
  }

  function testDepositUpTo_TransferFail() public asAccount(alice) {
    asset.approve(address(market), 0);
    vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
    market.depositUpTo(50_000e18);
  }

  // ===================================================================== //
  //                           deposit(uint256)                            //
  // ===================================================================== //

  function test_deposit(uint256 amount) external asAccount(alice) {
    amount = bound(amount, 1, DefaultMaximumSupply);
    market.deposit(amount);
  }

  function testDeposit_NotApprovedLender() public asAccount(bob) {
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedLender.selector);
    market.deposit(1e18);
  }

  function testDeposit_MaxSupplyExceeded() public asAccount(alice) {
    market.deposit(DefaultMaximumSupply - 1);
    vm.expectRevert(IMarketEventsAndErrors.MaxSupplyExceeded.selector);
    market.deposit(2);
  }

  // ===================================================================== //
  //                             collectFees()                             //
  // ===================================================================== //

  function test_collectFees_NoFeesAccrued() external {
    vm.expectRevert(IMarketEventsAndErrors.NullFeeAmount.selector);
    market.collectFees();
  }

  function test_collectFees() external {
    _deposit(alice, 1e18);
    fastForward(365 days);
    vm.expectEmit(address(asset));
    emit Transfer(address(market), feeRecipient, 1e16);
    vm.expectEmit(address(market));
    emit FeesCollected(1e16);
    market.collectFees();
  }

  function test_collectFees_InsufficientReservesForFeeWithdrawal() external {
    _deposit(alice, 1e18);
    fastForward(1);
    asset.burn(address(market), 1e18);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForFeeWithdrawal.selector);
    market.collectFees();
  }

  // ===================================================================== //
  //                            borrow(uint256)                            //
  // ===================================================================== //

  function test_borrow(uint256 amount) external {
    uint256 availableCollateral = market.borrowableAssets();
    assertEq(availableCollateral, 0, 'borrowable should be 0');

    vm.prank(alice);
    market.depositUpTo(50_000e18);
    assertEq(market.borrowableAssets(), 40_000e18, 'borrowable should be 40k');
    vm.prank(borrower);
    market.borrow(40_000e18);
    assertEq(asset.balanceOf(borrower), 40_000e18);
  }

  function test_borrow_BorrowAmountTooHigh() external {
    vm.prank(alice);
    market.depositUpTo(50_000e18);

    vm.startPrank(borrower);
    vm.expectRevert(IMarketEventsAndErrors.BorrowAmountTooHigh.selector);
    market.borrow(40_000e18 + 1);
  }

  // ===================================================================== //
  //                             closeMarket()                              //
  // ===================================================================== //

  function test_closeMarket_TransferRemainingDebt() external asAccount(borrower) {
    // Borrow 80% of deposits then request withdrawal of 100% of deposits
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    // startPrank(borrower);
    asset.approve(address(market), 8e17);
    // stopPrank();
    vm.expectEmit(address(asset));
    emit Transfer(borrower, address(market), 8e17);
    market.closeMarket();
  }

  function test_closeMarket_TransferExcessAssets() external asAccount(borrower) {
    // Borrow 80% of deposits then request withdrawal of 100% of deposits
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    asset.mint(address(market), 1e18);
    vm.expectEmit(address(asset));
    emit Transfer(address(market), borrower, 2e17);
    market.closeMarket();
  }

  function test_closeMarket_FailTransferRemainingDebt() external asAccount(borrower) {
    // Borrow 80% of deposits then request withdrawal of 100% of deposits
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
    market.closeMarket();
  }

  function test_closeMarket_NotApprovedBorrower() external {
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.closeMarket();
  }

  function test_closeMarket_repayUnpaidAndPendingWithdrawals() external asAccount(borrower) {
    _depositBorrowWithdraw(alice, 2e18, 16e17, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);
    // updateState(pendingState());
    _requestWithdrawal(alice, 1e18);
    assertEq(market.getUnpaidBatchExpiries().length, 1, 'batch not still open');

    uint remainingDebt = market.totalDebts() - 4e17;

    MarketState memory state = pendingState();
    asset.mint(borrower, remainingDebt);
    asset.approve(address(market), remainingDebt);
    _trackRepay(state, borrower, remainingDebt);
    _applyWithdrawalBatchPayment(
      _getWithdrawalBatch(state.pendingWithdrawalExpiry),
      state,
      state.pendingWithdrawalExpiry,
      lastTotalAssets - (state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees),
      true
    );
    _trackProcessUnpaidWithdrawalBatch(state);
    state.annualInterestBips = 0;
    state.isClosed = true;
    state.reserveRatioBips = 10000;
    state.timeDelinquent = 0;
    updateState(state);
    market.closeMarket();
    assertEq(market.getUnpaidBatchExpiries().length, 0);
    _checkState();
  }

  function test_closeMarket_repayUnpaidWithdrawals() external asAccount(borrower) {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);
    market.updateState();
    updateState(pendingState());
    assertEq(market.getUnpaidBatchExpiries().length, 1);

    uint remainingDebt = market.totalDebts() - 2e17;

    MarketState memory state = pendingState();
    asset.mint(borrower, remainingDebt);
    asset.approve(address(market), remainingDebt);
    _trackRepay(state, borrower, remainingDebt);
    _trackProcessUnpaidWithdrawalBatch(state);
    state.annualInterestBips = 0;
    state.isClosed = true;
    state.reserveRatioBips = 10000;
    state.timeDelinquent = 0;
    updateState(state);
    market.closeMarket();
    assertEq(market.getUnpaidBatchExpiries().length, 0);
    _checkState();
  }

  function test_closeMarket_UnpaidWithdrawals_TransferFailure() external asAccount(borrower) {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    fastForward(parameters.withdrawalBatchDuration + 1);
    market.updateState();
    uint32[] memory unpaidBatches = market.getUnpaidBatchExpiries();
    assertEq(unpaidBatches.length, 1);
    vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
    market.closeMarket();
  }

  /* ========================================================================== */
  /*                                   repay()                                  */
  /* ========================================================================== */

  function test_repay() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    asset.mint(address(this), 2e17);
    asset.approve(address(market), 2e17);
    vm.expectEmit(address(market));
    emit DebtRepaid(address(this), 2e17);
    market.repay(2e17);
  }

  function test_repay_NullRepayAmount() external {
    vm.expectRevert(IMarketEventsAndErrors.NullRepayAmount.selector);
    market.repay(0);
  }

  function test_repay_RepayToClosedMarket() external {
    vm.prank(borrower);
    market.closeMarket();
    asset.mint(address(this), 1e18);
    asset.approve(address(market), 1e18);
    vm.expectRevert(IMarketEventsAndErrors.RepayToClosedMarket.selector);
    market.repay(1e18);
  }

  /* ========================================================================== */
  /*                           repayOutstandingDebt()                           */
  /* ========================================================================== */

  function test_repayOutstandingDebt() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    asset.mint(address(this), 8e17);
    asset.approve(address(market), 8e17);
    vm.expectEmit(address(market));
    emit DebtRepaid(address(this), 8e17);
    market.repayOutstandingDebt();
  }

  function test_repayOutstandingDebt_NullRepayAmount() external {
    vm.expectRevert(IMarketEventsAndErrors.NullRepayAmount.selector);
    market.repayOutstandingDebt();
  }

  /* ========================================================================== */
  /*                            repayDelinquentDebt()                           */
  /* ========================================================================== */

  function test_repayDelinquentDebt() external {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 2e17); // 20% of 8e17
    asset.mint(address(this), 1.6e17);
    asset.approve(address(market), 1.6e17);
    vm.expectEmit(address(market));
    emit DebtRepaid(address(this), 1.6e17);
    market.repayDelinquentDebt();
  }

  function test_repayDelinquentDebt2() public asAccount(borrower) {
    assertEq(market.delinquencyGracePeriod(), 2000);
    parameters.delinquencyGracePeriod = 86_400;
    parameters.withdrawalBatchDuration = 0;
    setUp();

    assertEq(market.delinquencyGracePeriod(), 86_400, 'delinquencyGracePeriod');
    assertEq(market.delinquencyFeeBips(), 1_000, 'delinquencyFeeBips');
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);

    assertTrue(market.currentState().isDelinquent, 'should be delinquent');
    fastForward(365 days);

    MarketState memory state = pendingState();
    updateState(state);
    market.updateState();
    _checkState();
    uint delinquentDebt = state.liquidityRequired().satSub(lastTotalAssets);
    asset.mint(borrower, delinquentDebt);
    asset.approve(address(market), delinquentDebt);

    state = pendingState();
    _trackRepay(state, borrower, delinquentDebt);
    updateState(state);
    market.repayDelinquentDebt();
    _checkState();
  }

  function test_repayDelinquentDebt_NullRepayAmount() external {
    vm.expectRevert(IMarketEventsAndErrors.NullRepayAmount.selector);
    market.repayDelinquentDebt();
  }

  // ========================================================================== //
  //                            Credentials Provider                            //
  // ========================================================================== //

  function test_depositUpTo_FuzzAccess(AccessControlHooksFuzzInputs memory fuzzInputs) external {
    address carol = address(0xca701);
    AccessControlHooksFuzzContext memory context = createAccessControlHooksFuzzContext(
      fuzzInputs,
      hooks,
      roleProvider1,
      roleProvider2,
      carol
    );

    uint amount = 10e18;
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, carol);
    asset.mint(carol, amount);
    vm.prank(carol);
    asset.approve(address(market), amount);
    (uint104 scaledAmount, uint256 expectedNormalizedAmount) = _trackDeposit(state, carol, amount);
    bytes memory data = abi.encodePacked(
      abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, amount),
      context.hooksData
    );
    address marketAddress = address(market);

    // If the caller won't be authorized and no other error is expected, expect NotApprovedLender error
    if (
      !context.expectations.hasValidCredential && context.expectations.expectedError == bytes4(0)
    ) {
      context.expectations.expectedError = IMarketEventsAndErrors.NotApprovedLender.selector;
    }
    context.registerExpectations(true);
    vm.prank(carol);
    (bool success, bytes memory returnData) = marketAddress.call(data);
    // Check both because expectRevert will change success to true if it reverts
    if (success && context.expectations.expectedError == bytes4(0)) {
      uint256 actualNormalizedAmount = abi.decode(returnData, (uint256));
      assertEq(actualNormalizedAmount, expectedNormalizedAmount, 'Actual amount deposited');
      _checkState();
      assertApproxEqAbs(market.balanceOf(carol), currentBalance + amount, 1);
      assertEq(market.scaledBalanceOf(carol), currentScaledBalance + scaledAmount);
    }
  }

  function test_queueWithdrawal_FuzzAccess(
    AccessControlHooksFuzzInputs memory fuzzInputs
  ) external {
    address carol = address(0xca701);
    AccessControlHooksFuzzContext memory context = createAccessControlHooksFuzzContext(
      fuzzInputs,
      hooks,
      roleProvider1,
      roleProvider2,
      carol
    );

    uint amount = 1e18;
    _deposit(alice, amount);
    MarketState memory state = pendingState();
    updateState(state);
    uint104 scaledAmount = state.scaleAmount(amount).toUint104();
    MarketAccount storage _alice = _getAccount(alice);
    MarketAccount storage _carol = _getAccount(carol);
    _alice.scaledBalance -= scaledAmount;
    _carol.scaledBalance += scaledAmount;
    vm.prank(alice);
    market.transfer(carol, amount);
    bytes memory data = abi.encodePacked(
      abi.encodeWithSelector(market.queueWithdrawal.selector, amount),
      context.hooksData
    );
    address marketAddress = address(market);

    // If the caller won't be authorized and no other error is expected, expect NotApprovedLender error
    if (
      !context.expectations.hasValidCredential && context.expectations.expectedError == bytes4(0)
    ) {
      context.expectations.expectedError = IMarketEventsAndErrors.NotApprovedLender.selector;
    }
    context.registerExpectations(true);
    vm.prank(carol);
    if (context.expectations.expectedError == bytes4(0)) {
      _trackQueueWithdrawal(state, carol, amount);
    }
    (bool success, bytes memory returnData) = marketAddress.call(data);
    // Check both because expectRevert will change success to true if it reverts
    if (success && context.expectations.expectedError == bytes4(0)) {
      _checkState();
      assertEq(market.balanceOf(carol), 0, 'carol balance');
    }
  }
}

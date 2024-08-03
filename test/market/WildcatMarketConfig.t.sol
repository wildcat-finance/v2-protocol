// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'src/interfaces/IMarketEventsAndErrors.sol';
import '../BaseMarketTest.sol';

contract WildcatMarketConfigTest is BaseMarketTest {
  function test_maximumDeposit(uint256 _depositAmount) external returns (uint256) {
    assertEq(market.maximumDeposit(), parameters.maxTotalSupply, 'maximumDeposit');
    _depositAmount = bound(_depositAmount, 1, DefaultMaximumSupply);
    _deposit(alice, _depositAmount);
    assertEq(market.maximumDeposit(), DefaultMaximumSupply - _depositAmount, 'new maximumDeposit');
  }

  function test_maximumDeposit_SupplyExceedsMaximum() external {
    _deposit(alice, parameters.maxTotalSupply);
    fastForward(365 days);
    _checkState('state after one year');
    assertEq(market.maximumDeposit(), 0, 'maximumDeposit after 1 year');
  }

  function test_maxTotalSupply() external asAccount(borrower) {
    assertEq(market.maxTotalSupply(), parameters.maxTotalSupply);
    market.setMaxTotalSupply(10000);
    assertEq(market.maxTotalSupply(), 10000);
  }

  function test_annualInterestBips() external asAccount(borrower) {
    assertEq(market.annualInterestBips(), parameters.annualInterestBips);
    market.setAnnualInterestAndReserveRatioBips(10000, 10000);
    assertEq(market.annualInterestBips(), 10000);
  }

  function test_reserveRatioBips() external asAccount(borrower) {
    assertEq(market.reserveRatioBips(), parameters.reserveRatioBips);
    market.setAnnualInterestAndReserveRatioBips(10000, 10000);
    assertEq(market.reserveRatioBips(), 10000);
  }

  function test_nukeFromOrbit(address _account) external {
    _deposit(_account, 1e18);
    sanctionsSentinel.sanction(_account);

    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, _account);
    (uint32 expiry, uint104 scaledAmount) = _trackQueueWithdrawal(state, _account, 1e18);
    vm.expectEmit(address(market));
    emit SanctionedAccountAssetsQueuedForWithdrawal(_account, expiry, currentScaledBalance, currentBalance);
    market.nukeFromOrbit(_account);
    fastForward(parameters.withdrawalBatchDuration+1);
    state = pendingState();
    _trackExecuteWithdrawal(state, expiry, _account, 1e18, true);
    market.executeWithdrawal(_account, expiry);
  }

  function test_nukeFromOrbit_AlreadyNuked(address _account) external {
    sanctionsSentinel.sanction(_account);
    market.nukeFromOrbit(_account);
    market.nukeFromOrbit(_account);
  }

  function test_nukeFromOrbit_NullBalance(address _account) external {
    sanctionsSentinel.sanction(_account);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, _account, address(market));
    market.nukeFromOrbit(_account);
    assertEq(escrow.code.length, 0, 'escrow should not be deployed');
  }

  function test_nukeFromOrbit_WithBalance() external {
    _deposit(alice, 1e18);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(asset));
    sanctionsSentinel.sanction(alice);
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, alice);
    (uint32 expiry, uint104 scaledAmount) = _trackQueueWithdrawal(state, alice, 1e18);
    vm.expectEmit(address(market));
    emit SanctionedAccountAssetsQueuedForWithdrawal(alice, expiry, currentScaledBalance, currentBalance);
    market.nukeFromOrbit(alice);
  }

  function test_nukeFromOrbit_BadLaunchCode(address _account) external {
    vm.expectRevert(IMarketEventsAndErrors.BadLaunchCode.selector);
    market.nukeFromOrbit(_account);
  }

  function test_setMaxTotalSupply(
    uint256 _totalSupply,
    uint256 _maxTotalSupply
  ) external asAccount(borrower) {
    _totalSupply = bound(_totalSupply, 0, DefaultMaximumSupply);
    _maxTotalSupply = bound(_maxTotalSupply, _totalSupply, type(uint128).max);
    if (_totalSupply > 0) {
      _deposit(alice, _totalSupply);
    }
    market.setMaxTotalSupply(_maxTotalSupply);
    assertEq(market.maxTotalSupply(), _maxTotalSupply, 'maxTotalSupply should be _maxTotalSupply');
  }

  function test_setMaxTotalSupply_NotApprovedBorrower(uint128 _maxTotalSupply) external {
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.setMaxTotalSupply(_maxTotalSupply);
  }

  function test_setMaxTotalSupply_BelowCurrentSupply(
    uint256 _totalSupply,
    uint256 _maxTotalSupply
  ) external asAccount(borrower) {
    _totalSupply = bound(_totalSupply, 1, DefaultMaximumSupply - 1);
    _maxTotalSupply = bound(_maxTotalSupply, 0, _totalSupply - 1);
    _deposit(alice, _totalSupply);
    market.setMaxTotalSupply(_maxTotalSupply);
    assertEq(market.maxTotalSupply(), _maxTotalSupply, 'maxTotalSupply should be _maxTotalSupply');
  }

  function test_setAnnualInterestAndReserveRatioBips(
    uint16 _annualInterestBips,
    uint16 _reserveRatioBips
  ) external asAccount(borrower) {
    _annualInterestBips = uint16(bound(_annualInterestBips, 0, 10000));
    _reserveRatioBips = uint16(bound(_reserveRatioBips, 0, 10000));
    market.setAnnualInterestAndReserveRatioBips(_annualInterestBips, _reserveRatioBips);
    assertEq(market.annualInterestBips(), _annualInterestBips);
    assertEq(market.reserveRatioBips(), _reserveRatioBips);
  }

  function test_setAnnualInterestAndReserveRatioBips_AnnualInterestBipsTooHigh(
    uint16 _reserveRatioBips
  ) external asAccount(borrower) {
    _reserveRatioBips = uint16(bound(_reserveRatioBips, 0, 10000));
    vm.expectRevert(IMarketEventsAndErrors.AnnualInterestBipsTooHigh.selector);
    market.setAnnualInterestAndReserveRatioBips(10001, _reserveRatioBips);
  }

  function test_setAnnualInterestAndReserveRatioBips_NotApprovedBorrower() external {
    vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
    market.setAnnualInterestAndReserveRatioBips(0, 0);
  }

  function test_setAnnualInterestAndReserveRatioBips_AnnualInterestBipsTooHigh()
    external
    asAccount(borrower)
  {
    vm.expectRevert(IMarketEventsAndErrors.AnnualInterestBipsTooHigh.selector);
    market.setAnnualInterestAndReserveRatioBips(10001, 0);
  }

  /* function test_setAnnualInterestAndReserveRatioBips_IncreaseWhileDelinquent(
		uint256 _reserveRatioBips
	) external asAccount(borrower) {
		_reserveRatioBips = bound(
			_reserveRatioBips,
			parameters.reserveRatioBips + 1,
			10000
		);
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
		vm.expectEmit(address(market));
		emit ReserveRatioBipsUpdated(uint16(_reserveRatioBips));
		market.setAnnualInterestAndReserveRatioBips(uint16(parameters.annualInterestBips), uint16(_reserveRatioBips));
		assertEq(market.reserveRatioBips(), _reserveRatioBips);
	} */

  // Market already deliquent, LCR set to lower value
  function test_setAnnualInterestAndReserveRatioBips_InsufficientReservesForOldLiquidityRatio()
    external
    asAccount(borrower)
  {
    _depositBorrowWithdraw(alice, 1e18, 8e17, 1e18);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForOldLiquidityRatio.selector);
    market.setAnnualInterestAndReserveRatioBips(10000, 1000);
  }

  function test_setAnnualInterestAndReserveRatioBips_InsufficientReservesForNewLiquidityRatio()
    external
    asAccount(borrower)
  {
    _deposit(alice, 1e18);
    _borrow(7e17);
    vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForNewLiquidityRatio.selector);
    market.setAnnualInterestAndReserveRatioBips(10000, 3001);
  }
}

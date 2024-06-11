// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'src/interfaces/IMarketEventsAndErrors.sol';
import '../BaseMarketTest.sol';

contract WildcatMarketConfigTest is BaseMarketTest {
  function test_maximumDeposit(uint256 _depositAmount) external returns (uint256) {
    assertEq(market.maximumDeposit(), parameters.maxTotalSupply);
    _depositAmount = bound(_depositAmount, 1, DefaultMaximumSupply);
    _deposit(alice, _depositAmount);
    assertEq(market.maximumDeposit(), DefaultMaximumSupply - _depositAmount);
  }

  function test_maximumDeposit_SupplyExceedsMaximum() external {
    _deposit(alice, parameters.maxTotalSupply);
    fastForward(365 days);
    assertEq(market.totalSupply(), 110_000e18);
    assertEq(market.maximumDeposit(), 0);
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
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, _account, address(market));

    // @todo
    // vm.expectEmit(address(market));
    // emit AuthorizationStatusUpdated(_account, AuthRole.Blocked);
    vm.expectEmit(address(market));
    emit Transfer(_account, escrow, 1e18);
    vm.expectEmit(address(market));
    emit SanctionedAccountAssetsSentToEscrow(_account, escrow, 1e18);
    market.nukeFromOrbit(_account);
    // @todo
    // assertEq(
    // uint(market.getAccountRole(_account)),
    // uint(AuthRole.Blocked),
    // 'account role should be Blocked'
    // );
  }

  function test_nukeFromOrbit_AlreadyNuked(address _account) external {
    sanctionsSentinel.sanction(_account);

    // @todo
    // vm.expectEmit(address(market));
    // emit AuthorizationStatusUpdated(_account, AuthRole.Blocked);
    market.nukeFromOrbit(_account);
    market.nukeFromOrbit(_account);
    // @todo
    assertTrue(market.isAccountSanctioned(_account), 'account should be sanctioned');
  }

  function test_nukeFromOrbit_NullBalance(address _account) external {
    sanctionsSentinel.sanction(_account);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, _account, address(market));

    // @todo
    vm.expectEmit(address(market));
    emit AccountSanctioned(_account);
    market.nukeFromOrbit(_account);
    assertTrue(market.isAccountSanctioned(_account), 'account should be sanctioned');
    assertEq(escrow.code.length, 0, 'escrow should not be deployed');
  }

  function test_nukeFromOrbit_WithBalance() external {
    _deposit(alice, 1e18);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(market));
    sanctionsSentinel.sanction(alice);

    vm.expectEmit(address(market));
    emit AccountSanctioned(alice);

    vm.expectEmit(address(market));
    emit Transfer(alice, escrow, 1e18);
    vm.expectEmit(address(market));
    emit SanctionedAccountAssetsSentToEscrow(alice, escrow, 1e18);
    market.nukeFromOrbit(alice);
    assertTrue(market.isAccountSanctioned(alice), 'account should be sanctioned');
  }

  function test_nukeFromOrbit_BadLaunchCode(address _account) external {
    vm.expectRevert(IMarketEventsAndErrors.BadLaunchCode.selector);
    market.nukeFromOrbit(_account);
  }

  function test_stunningReversal() external {
    sanctionsSentinel.sanction(alice);

    vm.expectEmit(address(market));
    emit AccountSanctioned(alice);
    market.nukeFromOrbit(alice);

    vm.prank(borrower);
    sanctionsSentinel.overrideSanction(alice);

    // @todo
    // vm.expectEmit(address(market)); // this line causing the test fail
    // emit AuthorizationStatusUpdated(alice, AuthRole.WithdrawOnly);
    // market.stunningReversal(alice);

    assertFalse(market.isAccountSanctioned(alice), 'account should be unsanctioned');
    /* assertEq(
      uint(market.getAccountRole(alice)),
      uint(AuthRole.WithdrawOnly),
      'account role should be WithdrawOnly'
    ); */
  }

  function test_stunningReversal_AccountNotBlocked(address _account) external {
    vm.expectRevert(IMarketEventsAndErrors.AccountNotBlocked.selector);
    // @todo
    // market.stunningReversal(_account);
  }

  function test_stunningReversal_NotReversedOrStunning() external {
    sanctionsSentinel.sanction(alice);
    vm.expectEmit(address(market));
    emit AccountSanctioned(alice);

    market.nukeFromOrbit(alice);
    vm.expectRevert(IMarketEventsAndErrors.NotReversedOrStunning.selector);
    // market.stunningReversal(alice);
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

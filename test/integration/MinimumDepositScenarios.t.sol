// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';

/// @dev Minimum-deposit knob across the matrix. Most production borrowers run
///      without a minimum, so this isolates the knob: rejection below the
///      minimum, acceptance at it, the `depositUpTo` capacity-clamp edge where
///      a valid request is clamped below the minimum, and mid-life updates.
contract MinimumDepositScenariosTest is MarketConfigMatrix {
  uint128 internal constant MIN_DEPOSIT = 10_000e18;

  function test_minimumDeposit_openTerm_standard() external {
    _runMinimumDeposit(defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard));
  }

  function test_minimumDeposit_periodicTerm_standard() external {
    _runMinimumDeposit(defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard));
  }

  function test_minimumDeposit_fixedTerm_revolving() external {
    _runMinimumDeposit(defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Revolving));
  }

  function _runMinimumDeposit(Cell memory cell) internal {
    cell.minimumDeposit = MIN_DEPOSIT;
    DeployedCell memory d = deployCell(cell);

    // Below the minimum: rejected by the hooks.
    startPrank(alice);
    vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
    d.market.depositUpTo(MIN_DEPOSIT - 1);
    stopPrank();

    // Exactly the minimum: accepted.
    _depositAs(d, alice, MIN_DEPOSIT);
    assertEq(d.market.balanceOf(alice), MIN_DEPOSIT, 'deposit at minimum');

    // Above the minimum: accepted.
    _depositAs(d, bob, MIN_DEPOSIT * 3);
    assertEq(d.market.balanceOf(bob), MIN_DEPOSIT * 3, 'deposit above minimum');
  }

  /// @dev The subtle edge: `depositUpTo` clamps the request to remaining
  ///      capacity BEFORE the hook sees it, so a request that satisfies the
  ///      minimum can still be rejected once clamped below it.
  function test_minimumDeposit_capacityClampBelowMinimum() external {
    Cell memory cell = defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard);
    cell.minimumDeposit = MIN_DEPOSIT;
    cell.maxTotalSupply = 3 * MIN_DEPOSIT - 1;
    DeployedCell memory d = deployCell(cell);

    _depositAs(d, alice, MIN_DEPOSIT);
    _depositAs(d, bob, MIN_DEPOSIT);
    // Remaining capacity is MIN_DEPOSIT - 1.

    startPrank(alice);
    vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
    d.market.depositUpTo(MIN_DEPOSIT);
    stopPrank();

    // The exact-amount entry point runs the same clamped flow before its own
    // capacity check, so the hook error surfaces there too.
    startPrank(alice);
    vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
    d.market.deposit(MIN_DEPOSIT);
    stopPrank();
  }

  function test_minimumDeposit_updatedMidLife() external {
    Cell memory cell = defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard);
    cell.minimumDeposit = MIN_DEPOSIT;
    DeployedCell memory d = deployCell(cell);

    _depositAs(d, alice, MIN_DEPOSIT);

    // Borrower raises the minimum: yesterday's valid amount is now rejected.
    startPrank(borrower);
    PeriodicTermHooks(d.hooksInstance).setMinimumDeposit(address(d.market), MIN_DEPOSIT * 2);
    stopPrank();

    startPrank(bob);
    vm.expectRevert(OpenTermHooks.DepositBelowMinimum.selector);
    d.market.depositUpTo(MIN_DEPOSIT);
    stopPrank();
    _depositAs(d, bob, MIN_DEPOSIT * 2);

    // Borrower clears the minimum: small deposits flow again.
    startPrank(borrower);
    PeriodicTermHooks(d.hooksInstance).setMinimumDeposit(address(d.market), 0);
    stopPrank();
    _depositAs(d, alice, 1e18);
    assertEq(d.market.balanceOf(alice), MIN_DEPOSIT + 1e18, 'small deposit after clearing');

    // Only the borrower can move the knob.
    startPrank(alice);
    vm.expectRevert(BaseAccessControls.CallerNotBorrower.selector);
    PeriodicTermHooks(d.hooksInstance).setMinimumDeposit(address(d.market), 1);
    stopPrank();
  }
}

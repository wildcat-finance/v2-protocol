// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';

/// @dev Integration scenarios for the periodic-term APR reduction lifecycle,
///      run through the real market entry points (not the hooks in isolation):
///      propose -> lenders respond during the next withdrawal window ->
///      permissionless execution after the window -> expiry and cancellation.
contract AprGovernanceTest is MarketConfigMatrix {
  using MathUtils for uint256;

  uint256 internal constant DEPOSIT = 100_000e18;
  uint16 internal constant REDUCED_APR = 800;

  function test_aprReductionLifecycle_periodic_standard() external {
    _runAprReductionLifecycle(defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard));
  }

  function test_aprReductionLifecycle_periodic_revolving() external {
    _runAprReductionLifecycle(
      defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Revolving)
    );
  }

  /// @dev Full happy path: proposal outside a window, a lender exits during
  ///      the response window, and a third party executes the reduction
  ///      permissionlessly once the window closes.
  function _runAprReductionLifecycle(Cell memory cell) internal {
    DeployedCell memory d = deployCell(cell);
    PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);
    _depositAs(d, alice, DEPOSIT);
    _depositAs(d, bob, DEPOSIT / 2);

    uint256 windowStart = d.deployedAt + cell.firstWindowDelay;
    uint256 windowEnd = windowStart + cell.withdrawalWindowDuration;

    // --- Propose outside the window ---
    fastForward(10 days);
    startPrank(borrower);
    pth.proposeAnnualInterestBips(address(d.market), REDUCED_APR);
    stopPrank();

    (PendingAprChange memory pending, uint32 responseStart, uint32 responseEnd) = pth
      .getPendingAprChange(address(d.market));
    assertEq(pending.annualInterestBips, REDUCED_APR, 'proposed bips');
    assertEq(responseStart, windowStart, 'response window start');
    assertEq(responseEnd, windowEnd, 'response window end');

    // --- Premature execution must revert (permissionless caller) ---
    startPrank(bob);
    vm.expectRevert(PeriodicTermHooks.AprChangeNotReady.selector);
    d.market.executePendingAnnualInterestBipsReduction();
    stopPrank();

    // --- A lender responds by exiting during the window ---
    vm.warp(windowStart);
    uint32 expiry = _queueWithdrawalAs(d, alice, DEPOSIT / 4);
    fastForward(cell.withdrawalBatchDuration + 1);
    d.market.updateState();
    _executeWithdrawalAs(d, alice, expiry);

    // --- After the window ends, anyone can execute ---
    vm.warp(windowEnd);
    assertEq(d.market.annualInterestBips(), cell.annualInterestBips, 'APR before execution');
    startPrank(bob);
    d.market.executePendingAnnualInterestBipsReduction();
    stopPrank();
    assertEq(d.market.annualInterestBips(), REDUCED_APR, 'APR after execution');

    (pending, , ) = pth.getPendingAprChange(address(d.market));
    assertEq(pending.proposalTimestamp, 0, 'proposal not cleared');

    // --- Accrual continues at the reduced rate ---
    fastForward(5 days);
    d.market.updateState();
    assertEq(d.market.annualInterestBips(), REDUCED_APR, 'APR stable after accrual');
  }

  function test_aprReductionExpires_periodic_standard() external {
    Cell memory cell = defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard);
    DeployedCell memory d = deployCell(cell);
    PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);
    _depositAs(d, alice, DEPOSIT);

    fastForward(10 days);
    startPrank(borrower);
    pth.proposeAnnualInterestBips(address(d.market), REDUCED_APR);
    stopPrank();

    // Validity runs for AprReductionProposalValidityPeriods periods from the
    // response window start; one period after it the proposal is stale.
    uint256 windowStart = d.deployedAt + cell.firstWindowDelay;
    vm.warp(windowStart + cell.periodDuration * pth.AprReductionProposalValidityPeriods());
    startPrank(bob);
    vm.expectRevert(PeriodicTermHooks.AprReductionProposalExpired.selector);
    d.market.executePendingAnnualInterestBipsReduction();
    stopPrank();
    assertEq(d.market.annualInterestBips(), cell.annualInterestBips, 'APR changed after expiry');
  }

  function test_aprIncreaseCancelsPendingReduction_periodic_standard() external {
    Cell memory cell = defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard);
    DeployedCell memory d = deployCell(cell);
    PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);
    _depositAs(d, alice, DEPOSIT);

    fastForward(10 days);
    startPrank(borrower);
    pth.proposeAnnualInterestBips(address(d.market), REDUCED_APR);
    stopPrank();

    // Raising the APR through the ordinary borrower path cancels the proposal.
    startPrank(borrower);
    d.market.setAnnualInterestAndReserveRatioBips(
      cell.annualInterestBips + 100,
      cell.reserveRatioBips
    );
    stopPrank();
    assertEq(d.market.annualInterestBips(), cell.annualInterestBips + 100, 'APR not raised');

    (PendingAprChange memory pending, , ) = pth.getPendingAprChange(address(d.market));
    assertEq(pending.proposalTimestamp, 0, 'proposal should be cancelled');

    // With no live proposal, execution must revert.
    startPrank(bob);
    vm.expectRevert(PeriodicTermHooks.NoPendingAprChange.selector);
    d.market.executePendingAnnualInterestBipsReduction();
    stopPrank();
  }

  function test_closeMarketCancelsPendingReduction_periodic_standard() external {
    Cell memory cell = defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard);
    DeployedCell memory d = deployCell(cell);
    PeriodicTermHooks pth = PeriodicTermHooks(d.hooksInstance);
    _depositAs(d, alice, DEPOSIT);

    fastForward(10 days);
    startPrank(borrower);
    pth.proposeAnnualInterestBips(address(d.market), REDUCED_APR);
    stopPrank();

    _closeMarketAs(d);
    (PendingAprChange memory pending, , ) = pth.getPendingAprChange(address(d.market));
    assertEq(pending.proposalTimestamp, 0, 'close should cancel the proposal');
  }

  /// @dev The permissionless executor is gated by an explicit hook flag:
  ///      non-periodic markets must reject it outright.
  function test_executeReverts_onNonPeriodicMarkets() external {
    DeployedCell memory open = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    DeployedCell memory fixedTerm = deployCell(
      defaultCell(MatrixHooksKind.FixedTerm, MatrixMarketKind.Revolving)
    );
    _depositAs(open, alice, DEPOSIT);
    _depositAs(fixedTerm, alice, DEPOSIT);

    startPrank(bob);
    vm.expectRevert(IMarketEventsAndErrors.ExecutePendingAprReductionNotEnabled.selector);
    open.market.executePendingAnnualInterestBipsReduction();
    vm.expectRevert(IMarketEventsAndErrors.ExecutePendingAprReductionNotEnabled.selector);
    fixedTerm.market.executePendingAnnualInterestBipsReduction();
    stopPrank();
  }
}

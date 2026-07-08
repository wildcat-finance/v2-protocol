// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';

/// @dev Sanctions lifecycle across the matrix, including the documented
///      caf-03 limitation: `nukeFromOrbit` routes through the ordinary
///      withdrawal path, so periodic-term withdrawal windows gate it.
contract SanctionsScenariosTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 50_000e18;

  /// @dev Full lifecycle on the open/standard control: sanction -> nuke
  ///      queues the balance -> execution diverts to escrow -> borrower
  ///      override releases the escrow to the lender.
  function test_sanctionsLifecycle_openTerm_standard() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    _depositAs(d, alice, DEPOSIT);
    _depositAs(d, bob, DEPOSIT);

    sanctionsSentinel.sanction(bob);

    // Anyone may nuke a sanctioned lender; the balance is queued through the
    // ordinary withdrawal path (caf-03).
    startPrank(alice);
    d.market.nukeFromOrbit(bob);
    stopPrank();
    assertEq(d.market.balanceOf(bob), 0, 'bob balance not queued');

    // Once the batch expires, execution diverts bob's payout to his escrow.
    fastForward(d.cell.withdrawalBatchDuration + 1);
    d.market.updateState();
    MarketState memory state = d.market.previousState();
    uint32 expiry = uint32(d.deployedAt + d.cell.withdrawalBatchDuration);
    state; // silence unused warning; expiry derives from queue time
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, bob, address(asset));
    uint256 bobBalanceBefore = asset.balanceOf(bob);
    d.market.executeWithdrawal(bob, expiry);
    assertEq(asset.balanceOf(bob), bobBalanceBefore, 'sanctioned lender was paid directly');
    uint256 escrowed = asset.balanceOf(escrow);
    assertGe(escrowed, DEPOSIT, 'escrow did not receive the payout');

    // The borrower can override the sanction, after which the escrow releases.
    startPrank(borrower);
    sanctionsSentinel.overrideSanction(bob);
    stopPrank();
    IWildcatSanctionsEscrow(escrow).releaseEscrow();
    assertEq(asset.balanceOf(bob), bobBalanceBefore + escrowed, 'escrow release failed');
  }

  /// @dev Pins the caf-03 accepted limitation: on a periodic market outside a
  ///      withdrawal window, a sanctioned lender cannot be nuked until the
  ///      window opens (documented in Known Issues).
  function test_sanctionsNuke_gatedByPeriodicWindow() external {
    Cell memory cell = defaultCell(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard);
    DeployedCell memory d = deployCell(cell);
    _depositAs(d, bob, DEPOSIT);

    sanctionsSentinel.sanction(bob);

    // Outside the window: the nuke is blocked by the withdrawal gate.
    startPrank(alice);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    d.market.nukeFromOrbit(bob);
    stopPrank();

    // Inside the window: the nuke goes through.
    _warpToNextWithdrawalWindow(d);
    startPrank(alice);
    d.market.nukeFromOrbit(bob);
    stopPrank();
    assertEq(d.market.balanceOf(bob), 0, 'nuke failed inside window');
  }

  /// @dev On a revolving market the sanctioned exit must not disturb the
  ///      drawn-amount accounting.
  function test_sanctionsNuke_revolvingDrawnUnaffected() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving)
    );
    _depositAs(d, alice, DEPOSIT);
    _depositAs(d, bob, DEPOSIT);
    _borrowAs(d, 40_000e18);
    uint256 drawnBefore = IWildcatMarketRevolving(address(d.market)).drawnAmount();

    sanctionsSentinel.sanction(bob);
    startPrank(alice);
    d.market.nukeFromOrbit(bob);
    stopPrank();

    assertEq(
      IWildcatMarketRevolving(address(d.market)).drawnAmount(),
      drawnBefore,
      'nuke changed drawn amount'
    );
  }
}

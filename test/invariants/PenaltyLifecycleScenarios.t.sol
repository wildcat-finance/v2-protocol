// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { PenaltyLifecycleFixture } from './LifecycleFixture.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { MarketState } from 'src/libraries/MarketState.sol';

contract PenaltyLifecycleScenariosTest is PenaltyLifecycleFixture {
  function test_donationAndPendingPaymentCanDrainAfterScheduledClosure() external {
    lifecycle.advance(5, 0, 1);
    lifecycle.advance(3, 3, 14 days);
    lifecycle.sanctionLender(0);
    lifecycle.nukeFromOrbit(0);
    lifecycle.donate(2, 2, 86);
    _assertLifecycle();
    uint256 snapshot = vm.snapshot();
    lifecycle.fund(2, 1, 0, false);
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(2));
    MarketState memory state = market.previousState();
    assertFalse(state.isClosed, 'preview quote leaves a rounding shortfall');
    assertEq(state.totalDebts(), market.totalAssets() + 1, 'shortfall is exactly one unit');
    _assertLifecycle();
    assertTrue(vm.revertTo(snapshot), 'restore the liveness regression');
    _finishLifecycle('donation-rounding-regression');
  }

  function setUp() external {
    _setupPenaltyLifecycle();
  }

  function test_idleQueueAllocationMatchesOracle() external {
    lifecycle.advance(13367, 13832, 31);
    lifecycle.queueFullWithdrawal(10360);
    for (uint256 i; i < MatrixSize; ++i) {
      (MarketState memory expected, MarketState memory actual) = lifecycle.viewStates(i);
      assertEq(expected.scaledTotalSupply, actual.scaledTotalSupply, 'scaled supply preview');
      assertEq(
        expected.scaledPendingWithdrawals,
        actual.scaledPendingWithdrawals,
        'pending preview'
      );
      assertEq(
        expected.normalizedUnclaimedWithdrawals,
        actual.normalizedUnclaimedWithdrawals,
        'allocated preview'
      );
      assertEq(abi.encode(expected), abi.encode(actual), 'full preview');
    }
    _assertLifecycle();
  }

  function testFuzz_penaltyCureAtCutoffAndOneSecondLate(
    uint8 cell,
    bool late,
    bool process
  ) external {
    uint256 i = uint256(cell) % MatrixSize;
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
    uint256 cutoff = lifecycle.penaltyCutoff(i);
    assertTrue(cutoff > vm.getBlockTimestamp(), 'active penalty run');
    vm.warp(cutoff + (late ? 1 : 0));
    lifecycle.checkpoint(i);
    lifecycle.fund(i, 4, 1, process);
    assertEq(market.defaultedAt(), late ? cutoff : 0, 'inclusive penalty cutoff');
    assertFalse(market.previousState().isClosed, 'default does not close');
    assertEq(market.reserveRatioBips(), 2_000, 'no accelerated repayment');
    assertEq(market.annualInterestBips(), 1_000, 'no rate change');
    lifecycle.queueWithdrawal(0, 1e18);
    _assertLifecycle();
  }

  function testFuzz_observedCureResetsRunWithoutForgivingEconomicTimer(uint8 cell) external {
    uint256 i = uint256(cell) % MatrixSize;
    WildcatMarket market = WildcatMarket(lifecycle.marketAt(i));
    uint256 oldCutoff = lifecycle.penaltyCutoff(i);
    vm.warp(oldCutoff);
    lifecycle.checkpoint(i);
    uint256 economicTimer = market.previousState().timeDelinquent;
    lifecycle.fund(i, 4, 0, false);
    assertEq(market.previousState().timeDelinquent, economicTimer, 'economic timer retained');
    assertEq(lifecycle.penaltyCutoff(i), 0, 'observed cure resets run');
    vm.warp(oldCutoff + 1);
    lifecycle.checkpoint(i);
    assertTrue(market.previousState().isDelinquent, 'interest creates a new shortfall');
    uint256 newCutoff = lifecycle.penaltyCutoff(i);
    assertEq(newCutoff, vm.getBlockTimestamp() + 90 days, 'fresh default clock');
    assertEq(market.defaultedAt(), 0, 'old cutoff cannot default the new run');
    vm.warp(newCutoff + 1);
    lifecycle.checkpoint(i);
    assertEq(market.defaultedAt(), newCutoff, 'new run default');
    lifecycle.fund(i, 1, 1, false);
    assertEq(market.defaultedAt(), newCutoff, 'cure cannot clear default');
    assertFalse(market.isClosed(), 'fully funded before date or without terms');
    _assertLifecycle();
  }
}

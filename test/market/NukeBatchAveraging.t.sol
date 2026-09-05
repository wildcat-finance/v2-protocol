// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract NukeBatchAveragingTest is MarketFixture {
  address internal constant EarlyLender = address(0xA11CE);
  address internal constant LateLender = address(0xB0B);

  uint256 internal constant EarlyAmount = 900e18;
  uint256 internal constant LateAmount = 100e18;

  struct Outcome {
    uint256 scaledTotalAmount;
    uint256 scaledAmountBurned;
    uint256 normalizedAmountPaid;
    uint256 earlyPayout;
    uint256 latePayout;
    uint256 lateDestinationBalance;
  }

  function _options() private pure returns (Options memory options) {
    options = _defaultOptions(HooksKind.OpenTerm);
    options.protocolFeeBips = 0;
    options.annualInterestBips = 10_000;
    options.delinquencyFeeBips = 0;
    options.withdrawalBatchDuration = 365 days;
    options.reserveRatioBips = 0;
  }

  function _runScenario(bool forceWithNuke) private returns (Outcome memory outcome) {
    Fixture memory fixture = _newMarket(_options());
    _deposit(fixture, EarlyLender, EarlyAmount);
    _deposit(fixture, LateLender, LateAmount);

    vm.prank(EarlyLender);
    uint32 expiry = fixture.market.queueFullWithdrawal();

    WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
    assertEq(batch.scaledTotalAmount, EarlyAmount, 'initial scaled total');
    assertEq(batch.scaledAmountBurned, EarlyAmount, 'initial scaled burn');
    assertEq(batch.normalizedAmountPaid, EarlyAmount, 'initial normalized payment');

    // At the exact expiry, the batch remains current and the scale factor has doubled. Add the
    // interest needed to pay the late lender before entering through either equivalent path.
    vm.warp(expiry);
    fixture.asset.mint(address(fixture.market), LateAmount);

    if (forceWithNuke) {
      fixture.sentinel.setSanctioned(LateLender, true);
      fixture.market.nukeFromOrbit(LateLender);
    } else {
      vm.prank(LateLender);
      assertEq(fixture.market.queueFullWithdrawal(), expiry, 'voluntary expiry');
    }

    batch = fixture.market.getWithdrawalBatch(expiry);
    outcome.scaledTotalAmount = batch.scaledTotalAmount;
    outcome.scaledAmountBurned = batch.scaledAmountBurned;
    outcome.normalizedAmountPaid = batch.normalizedAmountPaid;

    vm.warp(uint256(expiry) + 1);
    fixture.market.updateState();
    outcome.earlyPayout = fixture.market.executeWithdrawal(EarlyLender, expiry);
    outcome.latePayout = fixture.market.executeWithdrawal(LateLender, expiry);
    outcome.lateDestinationBalance = fixture.asset.balanceOf(
      forceWithNuke ? fixture.sentinel.EscrowAddress() : LateLender
    );

    assertEq(
      fixture.market.previousState().normalizedUnclaimedWithdrawals,
      0,
      'unclaimed withdrawals'
    );
  }

  function test_nukeFromOrbitMatchesVoluntaryLateBatchEntry() external {
    uint256 initialBlockTimestamp = vm.getBlockTimestamp();
    Outcome memory voluntary = _runScenario(false);

    vm.warp(initialBlockTimestamp);
    Outcome memory forced = _runScenario(true);

    assertEq(
      keccak256(abi.encode(forced)),
      keccak256(abi.encode(voluntary)),
      'forced and voluntary accounting'
    );
    assertEq(voluntary.scaledTotalAmount, 1_000e18, 'final scaled total');
    assertEq(voluntary.scaledAmountBurned, 1_000e18, 'final scaled burn');
    assertEq(voluntary.normalizedAmountPaid, 1_100e18, 'conserved batch payment');
    assertEq(voluntary.earlyPayout, 990e18, 'early averaged payout');
    assertEq(voluntary.latePayout, 110e18, 'late averaged payout');
    assertEq(voluntary.lateDestinationBalance, 110e18, 'late destination balance');
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketFixture } from '../shared/MarketFixture.sol';
import { WithdrawalPaymentHarness } from '../mocks/WithdrawalPaymentHarness.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { RAY } from 'src/libraries/MathUtils.sol';

/// @dev Exercise the actual payment, pending-liquidity and release helpers with a
///      separate exact-numerator ledger. This is an accounting-helper sequence,
///      complementary to the real-market lifecycle and claim invariant suites.
contract WithdrawalCarrySequenceTest is MarketFixture {
  WithdrawalPaymentHarness internal harness;

  struct Sequence {
    MarketState state;
    WithdrawalBatch[3] batches;
    uint256[3] burnedNumerators;
    uint256[3] releasedNumerators;
    bool[3] finalized;
    uint256 initialSupply;
    uint256 cash;
  }

  function setUp() external {
    Fixture memory fixture = _newMarket(HooksKind.OpenTerm);
    harness = WithdrawalPaymentHarness(
      fixture.factory.deployMarket(vm.getCode('test/mocks/WithdrawalPaymentHarness.sol:WithdrawalPaymentHarness'))
    );
  }

  // Deliberately use binary search instead of the production inverse formula.
  function _affordable(
    WithdrawalBatch memory batch,
    uint112 factor,
    uint256 available
  )
    private
    pure
    returns (uint256 low)
  {
    uint256 high = batch.scaledTotalAmount - batch.scaledAmountBurned;
    while (low < high) {
      uint256 middle = low + (high - low + 1) / 2;
      if ((middle * factor + batch.paymentRemainder) / RAY <= available) low = middle;
      else high = middle - 1;
    }
  }

  function _debts(Sequence memory s) private pure returns (uint256) {
    uint256 fractions;
    uint256 funded;
    for (uint256 i; i < 3; ++i) {
      fractions += s.batches[i].paymentRemainder;
      funded += s.batches[i].normalizedAmountPaid;
    }
    return (uint256(s.state.scaledTotalSupply) * s.state.scaleFactor + fractions + RAY / 2) / RAY + funded
      + s.state.accruedProtocolFees;
  }

  function _assertLedger(Sequence memory s) private pure {
    uint256 pending;
    uint256 fractions;
    uint256 funded;
    uint256 burned;
    for (uint256 i; i < 3; ++i) {
      WithdrawalBatch memory batch = s.batches[i];
      assertTrue(batch.paymentRemainder < RAY, 'batch fraction bound');
      assertEq(
        uint256(batch.normalizedAmountPaid) * RAY + batch.paymentRemainder + s.releasedNumerators[i],
        s.burnedNumerators[i],
        'exact lifetime numerator ledger'
      );
      pending += batch.scaledTotalAmount - batch.scaledAmountBurned;
      fractions += batch.paymentRemainder;
      funded += batch.normalizedAmountPaid;
      burned += batch.scaledAmountBurned;
      if (s.finalized[i]) {
        assertEq(batch.scaledTotalAmount, batch.scaledAmountBurned);
        assertEq(batch.paymentRemainder, 0);
      }
    }
    assertEq(s.state.scaledPendingWithdrawals, pending);
    assertEq(s.state.scaledTotalSupply, s.initialSupply - burned);
    assertEq(s.state.withdrawalRemainder, fractions, 'aggregate equals all batch fractions');
    assertEq(s.state.normalizedUnclaimedWithdrawals, funded);
    assertEq(s.state.totalDebts(), _debts(s), 'debt independently reconstructed');
    assertTrue(s.cash >= funded + s.state.accruedProtocolFees, 'funded assets cannot be reused');
  }

  function _pay(Sequence memory s, uint256 index, uint256 available) private view {
    uint256 beforeDebt = _debts(s);
    uint256 beforeReserves = s.state.liquidityRequired();
    uint256 expectedBurn = _affordable(s.batches[index], s.state.scaleFactor, available);
    uint256 expectedPrice = (expectedBurn * s.state.scaleFactor + s.batches[index].paymentRemainder) / RAY;
    (WithdrawalBatch memory batch, MarketState memory state, uint104 burned, uint128 paid) =
      harness.applyPayment(s.batches[index], s.state, available);
    assertEq(burned, expectedBurn, 'independent maximal burn');
    assertEq(paid, expectedPrice, 'exact price');
    s.burnedNumerators[index] += uint256(burned) * s.state.scaleFactor;
    s.batches[index] = batch;
    s.state = state;
    assertEq(_debts(s), beforeDebt, 'payment cannot create or erase debt');
    assertEq(s.state.liquidityRequired(), beforeReserves, 'payment preserves reserves');
  }

  function _release(Sequence memory s, uint256 index) private view {
    if (s.finalized[index]) return;
    uint256 beforeDebt = _debts(s);
    uint256 beforeReserves = s.state.liquidityRequired();
    uint128 oldRemainder = s.batches[index].paymentRemainder;
    (WithdrawalBatch memory batch, MarketState memory state) = harness.release(s.batches[index], s.state);
    s.releasedNumerators[index] += oldRemainder - batch.paymentRemainder;
    s.batches[index] = batch;
    s.state = state;
    if (batch.scaledTotalAmount == batch.scaledAmountBurned) {
      s.finalized[index] = true;
      assertTrue(beforeDebt - _debts(s) <= 1, 'terminal release changes at most one atom');
      assertTrue(s.state.liquidityRequired() <= beforeReserves, 'release cannot raise reserves');
    } else {
      assertEq(batch.paymentRemainder, oldRemainder, 'unpaid batch must retain its fraction');
      assertEq(_debts(s), beforeDebt);
    }
  }

  function _pendingAvailable(Sequence memory s) private view returns (uint256 actual) {
    // Independently reconstruct prior liabilities from the two older batches.
    uint256 priorShares;
    uint256 priorFractions;
    for (uint256 i; i < 2; ++i) {
      priorShares += s.batches[i].scaledTotalAmount - s.batches[i].scaledAmountBurned;
      priorFractions += s.batches[i].paymentRemainder;
    }
    uint256 protected = s.state.normalizedUnclaimedWithdrawals + s.state.accruedProtocolFees
      + (priorShares * s.state.scaleFactor + priorFractions + RAY / 2) / RAY;
    uint256 expected = s.cash > protected ? s.cash - protected : 0;
    actual = harness.pendingLiquidity(s.batches[2], s.state, s.cash);
    assertEq(actual, expected, 'pending batch must protect the independent prior ledger');
  }

  function _growCurrent(Sequence memory s, uint256 amount) private pure {
    uint256 beforeDebt = _debts(s);
    s.state.scaledPendingWithdrawals += uint104(amount);
    s.batches[2].scaledTotalAmount += uint128(amount);
    assertEq(_debts(s), beforeDebt, 'queueing only reassigns existing live shares');
  }

  function testFuzz_multipleBatchSequenceConservesAndCloses(uint256 seed) external view {
    Sequence memory s;
    s.state.scaleFactor = uint112(RAY + (seed % RAY));
    s.state.reserveRatioBips = uint16(seed % 10001);
    s.state.accruedProtocolFees = uint128(seed % 7);
    s.cash = s.state.accruedProtocolFees;
    s.initialSupply = 100 + (seed % 101);
    for (uint256 i; i < 3; ++i) {
      seed = uint256(keccak256(abi.encode(seed, i)));
      s.batches[i].scaledTotalAmount = uint128(1 + (seed % 101));
      s.state.scaledPendingWithdrawals += uint104(s.batches[i].scaledTotalAmount);
      s.initialSupply += s.batches[i].scaledTotalAmount;
    }
    s.state.scaledTotalSupply = uint104(s.initialSupply);
    for (uint256 step; step < 32; ++step) {
      seed = uint256(keccak256(abi.encode(seed, step)));
      uint256 action = seed % 5;
      if (action == 0) {
        s.cash += 1 + ((seed >> 8) % 17);
      } else if (action == 1) {
        uint256 beforeNumerator = uint256(s.state.scaledTotalSupply) * s.state.scaleFactor + s.state.withdrawalRemainder;
        uint112 increase = uint112(1 + ((seed >> 8) % (RAY / 20)));
        uint128 beforeFraction = s.state.withdrawalRemainder;
        s.state.scaleFactor += increase;
        assertEq(s.state.withdrawalRemainder, beforeFraction, 'fractions do not earn interest');
        assertEq(
          uint256(s.state.scaledTotalSupply) * s.state.scaleFactor + s.state.withdrawalRemainder,
          beforeNumerator + uint256(s.state.scaledTotalSupply) * increase
        );
      } else if (action == 2) {
        uint256 freeShares = s.state.scaledTotalSupply - s.state.scaledPendingWithdrawals;
        _growCurrent(s, (seed >> 8) % (freeShares + 1));
      } else if (action == 3) {
        _pay(s, 2, _pendingAvailable(s));
        // The current batch can grow again even if fully paid: do not release it.
      } else {
        uint256 index = s.finalized[0] ? 1 : 0;
        uint256 available = s.cash - s.state.normalizedUnclaimedWithdrawals - s.state.accruedProtocolFees;
        _pay(s, index, available);
        _release(s, index);
      }
      _assertLedger(s);
    }

    // Queue the remaining free shares, then fund precisely the independently
    // calculated debt. No extra unit may be requested to finish all batches.
    _growCurrent(s, s.state.scaledTotalSupply - s.state.scaledPendingWithdrawals);
    s.cash = _debts(s);
    uint256 owed = s.batches[2].scaledTotalAmount - s.batches[2].scaledAmountBurned;
    uint256 beforeBurned = s.batches[2].scaledAmountBurned;
    _pay(s, 2, _pendingAvailable(s));
    assertEq(s.batches[2].scaledAmountBurned - beforeBurned, owed, 'current batch closes funded');
    _release(s, 2);
    for (uint256 i; i < 2; ++i) {
      _pay(s, i, s.cash - s.state.normalizedUnclaimedWithdrawals - s.state.accruedProtocolFees);
      _release(s, i);
    }
    _assertLedger(s);
    assertEq(s.state.scaledTotalSupply, 0);
    assertEq(s.state.scaledPendingWithdrawals, 0);
    assertEq(s.state.withdrawalRemainder, 0);
    for (uint256 i; i < 3; ++i) {
      assertTrue(s.finalized[i]);
    }
    assertTrue(s.cash >= _debts(s), 'closed claims and fees fully backed');
  }

  function test_paidCurrentBatchRetainsFractionWhenItGrows() external view {
    Sequence memory s;
    s.initialSupply = 4;
    s.state.scaledTotalSupply = 4;
    s.state.scaledPendingWithdrawals = 3;
    s.state.scaleFactor = uint112((5 * RAY) / 4);
    s.batches[2].scaledTotalAmount = 3;
    s.cash = 3;
    _pay(s, 2, _pendingAvailable(s));
    assertEq(s.batches[2].paymentRemainder, (3 * RAY) / 4);
    _growCurrent(s, 1);
    ++s.cash;
    _pay(s, 2, _pendingAvailable(s));
    assertEq(s.batches[2].scaledAmountBurned, 3, 'one unit cannot fund the carried price');
    ++s.cash;
    _pay(s, 2, _pendingAvailable(s));
    assertEq(s.batches[2].normalizedAmountPaid, 5);
    _release(s, 2);
    _assertLedger(s);
  }
}

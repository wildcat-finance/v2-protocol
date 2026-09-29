// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { WithdrawalBatch, AccountWithdrawalStatus } from 'src/libraries/Withdrawal.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { WithdrawalBatchDataWithLenderStatus } from 'src/lens/WithdrawalBatchData.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

interface NarrowWithdrawalReader {
  struct Batch {
    uint104 scaledTotalAmount;
    uint104 scaledAmountBurned;
    uint128 normalizedAmountPaid;
  }

  struct Status {
    uint104 scaledAmount;
    uint128 normalizedAmountWithdrawn;
  }

  function getWithdrawalBatch(uint32 expiry) external view returns (Batch memory);

  function getAccountWithdrawalStatus(
    address lender,
    uint32 expiry
  ) external view returns (Status memory);
}

contract WithdrawalCountersTest is MarketFixture {
  address internal constant Lender = address(0xA11CE);
  address internal constant OtherLender = address(0xB0B);
  address internal constant LaterLender = address(0xCAFE);

  function _fixture(bool revolving, HooksKind kind) private returns (Fixture memory fixture) {
    Options memory options = _defaultOptions(kind);
    options.revolving = revolving;
    options.maxTotalSupply = type(uint104).max / 2;
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    options.protocolFeeBips = 0;
    options.delinquencyFeeBips = 0;
    fixture = _newMarket(options);
  }

  function _queue(Fixture memory fixture, address lender, uint256 amount) private returns (uint32) {
    _deposit(fixture, lender, amount);
    vm.prank(lender);
    return fixture.market.queueFullWithdrawal();
  }

  function _core(Fixture memory fixture) private returns (MarketLensCore) {
    return MarketLensCore(
      _deployCode(
        'src/lens/MarketLensCore.sol:MarketLensCore',
        abi.encode(address(fixture.archController), address(fixture.factory))
      )
    );
  }

  // Use a separate external call so a caller can observe the legacy decoder's revert.
  function readNarrowBatch(address market, uint32 expiry) external view returns (uint256) {
    return NarrowWithdrawalReader(market).getWithdrawalBatch(expiry).scaledTotalAmount;
  }

  function readNarrowAccount(address market, uint32 expiry) external view returns (uint256) {
    return NarrowWithdrawalReader(market)
      .getAccountWithdrawalStatus(Lender, expiry)
      .scaledAmount;
  }

  function _checkCumulativeBatch(bool revolving, HooksKind kind, bool sameLender) private {
    Fixture memory fixture = _fixture(revolving, kind);
    uint256 tranche = type(uint104).max / 2;
    uint32 expiry = _queue(fixture, Lender, tranche);
    assertEq(_queue(fixture, Lender, tranche), expiry, 'same batch after payment');
    assertEq(
      this.readNarrowBatch(address(fixture.market), expiry),
      tranche * 2,
      'legacy batch within range'
    );
    assertEq(
      this.readNarrowAccount(address(fixture.market), expiry),
      tranche * 2,
      'legacy account within range'
    );
    address thirdLender = sameLender ? Lender : OtherLender;
    assertEq(_queue(fixture, thirdLender, 2), expiry, 'cross former counter ceiling');

    // A small unrelated withdrawal must still join the paid batch after its
    // cumulative volume exceeds uint104, even though live supply never does.
    _deposit(fixture, LaterLender, 7);
    vm.prank(LaterLender);
    assertEq(fixture.market.queueWithdrawalScaled(7), expiry, 'later lender can queue');

    uint256 total = tranche * 2 + 9;
    WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
    assertEq(batch.scaledTotalAmount, total, 'cumulative total');
    assertEq(batch.scaledAmountBurned, total, 'cumulative paid shares');
    assertEq(batch.normalizedAmountPaid, total, 'reserved assets');
    assertEq(fixture.market.totalSupply(), 0, 'all shares burned');
    assertEq(fixture.market.currentState().normalizedUnclaimedWithdrawals, total, 'claims protected');
    AccountWithdrawalStatus memory status = fixture.market.getAccountWithdrawalStatus(Lender, expiry);
    uint256 lenderAmount = tranche * 2 + (sameLender ? 2 : 0);
    assertEq(status.scaledAmount, lenderAmount, 'lender cumulative ownership');

    vm.expectRevert();
    this.readNarrowBatch(address(fixture.market), expiry);
    if (sameLender) {
      vm.expectRevert();
      this.readNarrowAccount(address(fixture.market), expiry);
    }

    MarketLensCore core = _core(fixture);
    WithdrawalBatchDataWithLenderStatus memory lensData = core.getWithdrawalBatchDataWithLenderStatus(
      address(fixture.market),
      expiry,
      Lender
    );
    assertEq(lensData.batch.scaledTotalAmount, total, 'wide lens total');
    assertEq(lensData.lenderStatus.scaledAmount, lenderAmount, 'wide lens ownership');
    assertEq(lensData.lenderStatus.normalizedAmountOwed, lenderAmount, 'wide lens claim');
    assertEq(lensData.lenderStatus.availableWithdrawalAmount, 0, 'pending claim');

    vm.warp(uint256(expiry) + 1);
    lensData = core.getWithdrawalBatchDataWithLenderStatus(address(fixture.market), expiry, Lender);
    assertEq(lensData.lenderStatus.availableWithdrawalAmount, lenderAmount, 'expired claim');
    assertEq(fixture.market.executeWithdrawal(Lender, expiry), lenderAmount, 'full lender payout');
    if (!sameLender) {
      assertEq(fixture.market.executeWithdrawal(OtherLender, expiry), 2, 'other lender payout');
    }
    assertEq(fixture.market.executeWithdrawal(LaterLender, expiry), 7, 'later lender payout');
    assertEq(fixture.market.totalAssets(), 0, 'all assets returned');
    assertEq(fixture.market.currentState().normalizedUnclaimedWithdrawals, 0, 'all claims executed');
  }

  function test_cumulativeBatchCounterExceedsUint104_AcrossMarketKinds() external {
    for (uint256 i; i < 4; i++) {
      _checkCumulativeBatch(i >= 2, HooksKind(i % 2), false);
    }
  }

  function test_cumulativeAccountCounterExceedsUint104_AcrossMarketKinds() external {
    for (uint256 i; i < 4; i++) {
      _checkCumulativeBatch(i >= 2, HooksKind(i % 2), true);
    }
  }

  function test_wideBatch_PartialPaymentAndRepeatedExecution_AcrossMarketKinds() external {
    for (uint256 i; i < 4; i++) {
      Fixture memory fixture = _fixture(i >= 2, HooksKind(i % 2));
      uint256 tranche = type(uint104).max / 2;
      uint32 expiry = _queue(fixture, Lender, tranche);
      _queue(fixture, Lender, tranche);
      _deposit(fixture, Lender, 100);
      vm.prank(Borrower);
      fixture.market.borrow(80);
      vm.prank(Lender);
      assertEq(fixture.market.queueWithdrawal(100), expiry, 'same expiry');

      WithdrawalBatch memory batch = fixture.market.getWithdrawalBatch(expiry);
      assertEq(batch.scaledTotalAmount, tranche * 2 + 100, 'wide partially paid total');
      assertEq(batch.scaledAmountBurned, tranche * 2 + 20, 'wide partially paid shares');
      assertEq(fixture.market.currentState().scaledPendingWithdrawals, 80, 'live unpaid shares');

      vm.warp(uint256(expiry) + 1);
      assertEq(fixture.market.executeWithdrawal(Lender, expiry), tranche * 2 + 20, 'first claim');
      vm.startPrank(Borrower);
      fixture.asset.approve(address(fixture.market), 80);
      fixture.market.repayAndProcessUnpaidWithdrawalBatches(80, 1);
      vm.stopPrank();
      assertEq(fixture.market.executeWithdrawal(Lender, expiry), 80, 'remaining claim');
      assertEq(fixture.market.totalSupply(), 0, 'remaining shares burned');
      assertEq(fixture.market.totalAssets(), 0, 'all assets returned');
      assertEq(
        fixture.market.currentState().normalizedUnclaimedWithdrawals,
        0,
        'all claims collected'
      );
    }
  }
}

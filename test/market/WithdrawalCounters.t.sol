// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { WithdrawalBatch, AccountWithdrawalStatus } from 'src/libraries/Withdrawal.sol';
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

  function getAccountWithdrawalStatus(address lender, uint32 expiry) external view returns (Status memory);
}

contract WithdrawalCountersTest is MarketFixture {
  address internal constant Lender = address(0xA11CE);
  address internal constant OtherLender = address(0xB0B);
  uint256 internal constant RAY = 1e27;

  struct CapacityScenario {
    Fixture fixture;
    uint256 amount;
    uint32[4] expiries;
  }

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

  function _fillCurrentBatchToCapMinusOne(Fixture memory fixture) private returns (uint32 expiry) {
    uint256 tranche = type(uint104).max / 2;
    expiry = _queue(fixture, Lender, tranche);
    assertEq(_queue(fixture, Lender, tranche), expiry, 'same batch after payment');
  }

  // Use separate external calls so the legacy decoders validate the returned widths.
  function readNarrowBatch(address market, uint32 expiry) external view returns (uint256) {
    return NarrowWithdrawalReader(market).getWithdrawalBatch(expiry).scaledTotalAmount;
  }

  function readNarrowAccount(address market, uint32 expiry) external view returns (uint256) {
    return NarrowWithdrawalReader(market).getAccountWithdrawalStatus(Lender, expiry).scaledAmount;
  }

  function _checkCumulativeCap(bool revolving, HooksKind kind) private {
    Fixture memory fixture = _fixture(revolving, kind);
    uint32 expiry = _fillCurrentBatchToCapMinusOne(fixture);
    uint256 total = type(uint104).max - 1;

    assertEq(this.readNarrowBatch(address(fixture.market), expiry), total, 'legacy batch decoder');
    assertEq(this.readNarrowAccount(address(fixture.market), expiry), total, 'legacy account decoder');

    _deposit(fixture, Lender, 2);
    bytes memory stateBefore = abi.encode(fixture.market.previousState());
    WithdrawalBatch memory batchBefore = fixture.market.getWithdrawalBatch(expiry);
    AccountWithdrawalStatus memory statusBefore = fixture.market.getAccountWithdrawalStatus(Lender, expiry);

    vm.startPrank(Lender);
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    fixture.market.queueFullWithdrawal();
    vm.stopPrank();

    assertEq(abi.encode(fixture.market.previousState()), stateBefore, 'state unchanged');
    assertEq(abi.encode(fixture.market.getWithdrawalBatch(expiry)), abi.encode(batchBefore), 'batch unchanged');
    assertEq(
      abi.encode(fixture.market.getAccountWithdrawalStatus(Lender, expiry)),
      abi.encode(statusBefore),
      'account status unchanged'
    );
    assertEq(fixture.market.scaledBalanceOf(Lender), 2, 'request remains unqueued');

    vm.warp(uint256(expiry) + 1);
    assertEq(fixture.market.executeWithdrawal(Lender, expiry), total, 'first batch pays');
    vm.prank(Lender);
    uint32 nextExpiry = fixture.market.queueFullWithdrawal();
    assertTrue(nextExpiry > expiry, 'rejected balance uses next batch');
    vm.warp(uint256(nextExpiry) + 1);
    assertEq(fixture.market.executeWithdrawal(Lender, nextExpiry), 2, 'next batch pays');
    assertEq(fixture.market.totalAssets(), 0, 'all assets returned');
  }

  function test_cumulativeBatchCapacityRejectsBeforeAdmission_AcrossMarketKinds() external {
    for (uint256 i; i < 4; i++) {
      _checkCumulativeCap(i >= 2, HooksKind(i % 2));
    }
  }

  function test_exactCumulativeBatchCapacityIsAccepted() external {
    Fixture memory fixture = _fixture(false, HooksKind.OpenTerm);
    uint32 expiry = _fillCurrentBatchToCapMinusOne(fixture);
    _deposit(fixture, OtherLender, 1);

    vm.prank(OtherLender);
    assertEq(fixture.market.queueFullWithdrawal(), expiry, 'exact cap joins batch');
    assertEq(fixture.market.getWithdrawalBatch(expiry).scaledTotalAmount, type(uint104).max, 'exact cap stored');
    assertEq(this.readNarrowBatch(address(fixture.market), expiry), type(uint104).max, 'legacy decoder accepts cap');

    _deposit(fixture, OtherLender, 1);
    vm.prank(OtherLender);
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    fixture.market.queueFullWithdrawal();
    assertEq(fixture.market.scaledBalanceOf(OtherLender), 1, 'excess stays live');
  }

  function test_allAdmissionRoutesUseCumulativeBatchCapacity() external {
    for (uint256 mode; mode < 4; mode++) {
      Fixture memory fixture = _fixture(false, HooksKind.OpenTerm);
      uint32 expiry = _fillCurrentBatchToCapMinusOne(fixture);
      _deposit(fixture, OtherLender, 2);
      if (mode == 3) fixture.sentinel.setSanctioned(OtherLender, true);

      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      if (mode == 0) {
        vm.prank(OtherLender);
        fixture.market.queueWithdrawal(2);
      } else if (mode == 1) {
        vm.prank(OtherLender);
        fixture.market.queueWithdrawalScaled(2);
      } else if (mode == 2) {
        vm.prank(OtherLender);
        fixture.market.queueFullWithdrawal();
      } else {
        fixture.market.nukeFromOrbit(OtherLender);
      }

      assertEq(fixture.market.scaledBalanceOf(OtherLender), 2, 'balance unchanged');
      assertEq(fixture.market.getAccountWithdrawalStatus(OtherLender, expiry).scaledAmount, 0, 'status unchanged');
      assertEq(fixture.market.getWithdrawalBatch(expiry).scaledTotalAmount, type(uint104).max - 1, 'batch unchanged');
    }
  }

  function _setFactor(Fixture memory fixture, uint112 factor) private {
    uint256 packed = uint256(vm.load(address(fixture.market), bytes32(uint256(3))));
    uint256 mask = uint256(type(uint112).max) << 80;
    vm.store(address(fixture.market), bytes32(uint256(3)), bytes32((packed & ~mask) | (uint256(factor) << 80)));
  }

  function _globalCapacityFixture(
    bool revolving,
    HooksKind kind,
    uint32 repaymentDate
  )
    private
    returns (CapacityScenario memory scenario)
  {
    Options memory options = _defaultOptions(kind);
    options.revolving = revolving;
    options.maxTotalSupply = type(uint128).max;
    options.reserveRatioBips = 0;
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    options.protocolFeeBips = 0;
    options.delinquencyFeeBips = 0;
    options.repaymentDate = repaymentDate;
    options.repaymentPeriod = repaymentDate == 0 ? 0 : 10 days;
    scenario.fixture = _newMarket(options);
    _setFactor(scenario.fixture, uint112(4e33));

    scenario.amount = uint256(type(uint104).max) * 4_000_000;
    for (uint256 i; i < 4; i++) {
      scenario.expiries[i] = _queue(scenario.fixture, Lender, scenario.amount);
      vm.warp(uint256(scenario.expiries[i]) + 1);
      scenario.fixture.market.updateState();
    }
    assertEq(
      scenario.fixture.market.previousState().normalizedUnclaimedWithdrawals,
      scenario.amount * 4,
      'four batches reserved'
    );
  }

  function _openUnfundedBatch(Fixture memory fixture, uint256 amount) private returns (uint32 expiry) {
    _deposit(fixture, Lender, amount);
    vm.prank(Borrower);
    fixture.market.borrow(amount);
    vm.prank(Lender);
    expiry = fixture.market.queueFullWithdrawal();
  }

  function test_globalUnclaimedCapacityRecoversWhenPriorClaimExecutes() external {
    CapacityScenario memory scenario = _globalCapacityFixture(false, HooksKind.OpenTerm, 0);
    uint32 unpaidExpiry = _openUnfundedBatch(scenario.fixture, scenario.amount);
    vm.warp(uint256(unpaidExpiry) + 1);

    uint256 headroom = type(uint128).max - scenario.fixture.market.previousState().normalizedUnclaimedWithdrawals;
    vm.startPrank(Borrower);
    scenario.fixture.asset.approve(address(scenario.fixture.market), scenario.amount);
    scenario.fixture.market.repayAndProcessUnpaidWithdrawalBatches(scenario.amount, 1);
    vm.stopPrank();

    WithdrawalBatch memory capped = scenario.fixture.market.getWithdrawalBatch(unpaidExpiry);
    assertTrue(capped.normalizedAmountPaid > 0, 'available headroom used');
    assertTrue(capped.normalizedAmountPaid <= headroom, 'global headroom respected');
    assertTrue(capped.scaledAmountBurned < capped.scaledTotalAmount, 'remainder stays unpaid');

    assertEq(
      scenario.fixture.market.executeWithdrawal(Lender, scenario.expiries[0]), scenario.amount, 'old claim exits'
    );
    scenario.fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);

    WithdrawalBatch memory recovered = scenario.fixture.market.getWithdrawalBatch(unpaidExpiry);
    assertEq(recovered.scaledAmountBurned, type(uint104).max, 'pending batch paid');
    for (uint256 i = 1; i < 4; i++) {
      assertEq(
        scenario.fixture.market.executeWithdrawal(Lender, scenario.expiries[i]), scenario.amount, 'old claim pays'
      );
    }
    assertEq(scenario.fixture.market.executeWithdrawal(Lender, unpaidExpiry), scenario.amount, 'new claim pays');
    assertEq(scenario.fixture.market.totalAssets(), 0, 'all claims collected');
  }

  function _checkDirectDonationDoesNotBlockPriorClaim(bool revolving, HooksKind kind) private {
    CapacityScenario memory scenario = _globalCapacityFixture(revolving, kind, 0);
    uint32 currentExpiry = _openUnfundedBatch(scenario.fixture, scenario.amount);
    assertTrue(block.timestamp < currentExpiry, 'batch is still current');

    uint256 reservedBefore = scenario.fixture.market.previousState().normalizedUnclaimedWithdrawals;
    uint256 headroom = type(uint128).max - reservedBefore;
    scenario.fixture.asset.mint(OtherLender, scenario.amount);
    vm.prank(OtherLender);
    scenario.fixture.asset.transfer(address(scenario.fixture.market), scenario.amount);

    WithdrawalBatch memory capped = scenario.fixture.market.getWithdrawalBatch(currentExpiry);
    assertTrue(capped.normalizedAmountPaid > 0, 'donation uses available headroom');
    assertTrue(capped.normalizedAmountPaid <= headroom, 'donation cannot overflow aggregate');
    assertTrue(capped.scaledAmountBurned < capped.scaledTotalAmount, 'excess stays pending');
    assertEq(
      scenario.fixture.market.executeWithdrawal(Lender, scenario.expiries[0]), scenario.amount, 'old claim exits'
    );

    scenario.fixture.market.updateState();
    WithdrawalBatch memory recovered = scenario.fixture.market.getWithdrawalBatch(currentExpiry);
    assertEq(recovered.scaledAmountBurned, type(uint104).max, 'freed capacity funds remainder');
    assertEq(recovered.normalizedAmountPaid, scenario.amount, 'current batch fully paid');
    for (uint256 i = 1; i < 4; i++) {
      assertEq(
        scenario.fixture.market.executeWithdrawal(Lender, scenario.expiries[i]), scenario.amount, 'old claim pays'
      );
    }
    vm.warp(uint256(currentExpiry) + 1);
    assertEq(scenario.fixture.market.executeWithdrawal(Lender, currentExpiry), scenario.amount, 'new claim pays');
    assertEq(scenario.fixture.market.totalAssets(), 0, 'all claims collected');
  }

  function test_directDonationCannotBlockPriorClaim_AcrossMarketKinds() external {
    for (uint256 i; i < 4; i++) {
      _checkDirectDonationDoesNotBlockPriorClaim(i >= 2, HooksKind(i % 2));
    }
  }

  function _checkRepaymentClosureQueuesHeadroomLimitedBatch(bool revolving) private {
    uint32 repaymentDate = uint32(vm.getBlockTimestamp() + 4 days + 12 hours);
    CapacityScenario memory scenario = _globalCapacityFixture(revolving, HooksKind.OpenTerm, repaymentDate);
    uint32 currentExpiry = _openUnfundedBatch(scenario.fixture, scenario.amount);
    assertTrue(repaymentDate < currentExpiry, 'repayment precedes batch expiry');

    vm.warp(repaymentDate);
    vm.startPrank(Borrower);
    scenario.fixture.asset.approve(address(scenario.fixture.market), scenario.amount);
    scenario.fixture.market.repay(scenario.amount);
    vm.stopPrank();

    assertTrue(scenario.fixture.market.previousState().isClosed, 'fully backed market closes');
    assertEq(scenario.fixture.market.previousState().pendingWithdrawalExpiry, 0, 'current key cleared');
    uint32[] memory unpaid = scenario.fixture.market.getUnpaidBatchExpiries();
    assertEq(unpaid.length, 1, 'partial batch remains reachable');
    assertEq(unpaid[0], currentExpiry, 'partial batch queued');
    WithdrawalBatch memory capped = scenario.fixture.market.getWithdrawalBatch(currentExpiry);
    assertTrue(capped.normalizedAmountPaid > 0, 'headroom reserved');
    assertTrue(capped.scaledAmountBurned < capped.scaledTotalAmount, 'batch remains partial');

    assertEq(
      scenario.fixture.market.executeWithdrawal(Lender, scenario.expiries[0]), scenario.amount, 'old claim exits'
    );
    scenario.fixture.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
    assertEq(scenario.fixture.market.getUnpaidBatchExpiries().length, 0, 'partial batch completed');
    for (uint256 i = 1; i < 4; i++) {
      assertEq(
        scenario.fixture.market.executeWithdrawal(Lender, scenario.expiries[i]), scenario.amount, 'old claim pays'
      );
    }
    assertEq(scenario.fixture.market.executeWithdrawal(Lender, currentExpiry), scenario.amount, 'new claim pays');
    assertEq(scenario.fixture.market.totalAssets(), 0, 'all claims collected');
  }

  function test_repaymentClosureQueuesHeadroomLimitedBatch_AcrossMarketKinds() external {
    _checkRepaymentClosureQueuesHeadroomLimitedBatch(false);
    _checkRepaymentClosureQueuesHeadroomLimitedBatch(true);
  }

  function test_uint104CapKeepsWorstCaseNormalizedPaymentWithinUint128() external pure {
    uint256 worstCase = (uint256(type(uint104).max) * uint256(type(uint112).max)) / RAY;
    assertTrue(worstCase < type(uint128).max);
  }
}

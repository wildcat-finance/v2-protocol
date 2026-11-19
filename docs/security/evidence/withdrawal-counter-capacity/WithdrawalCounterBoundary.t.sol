// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { WithdrawalBatch, AccountWithdrawalStatus } from 'src/libraries/Withdrawal.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { WithdrawalBatchDataWithLenderStatus } from 'src/lens/WithdrawalBatchData.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

/// Boundary-state injection compresses millions of earlier legal queue/payment
/// actions. It checks representation and execution; it is not a reachability PoC.
contract WithdrawalCounterBoundaryTest is MarketFixture {
  address internal constant A = address(0xA11CE);
  address internal constant B = address(0xB0B);

  function _fixture(bool revolving, bool fixedTerm) private returns (Fixture memory f) {
    Options memory o = _defaultOptions(fixedTerm ? HooksKind.FixedTerm : HooksKind.OpenTerm);
    o.revolving = revolving;
    o.annualInterestBips = 0;
    o.commitmentFeeBips = 0;
    o.protocolFeeBips = 0;
    o.delinquencyFeeBips = 0;
    f = _newMarket(o);
  }

  function _batchSlot(uint32 expiry) private pure returns (bytes32) {
    // Exact 23c47cd layout: withdrawal root 5, batch map 7, account map 8.
    return keccak256(abi.encode(uint256(expiry), uint256(7)));
  }

  function _claimSlot(uint32 expiry, address lender) private pure returns (bytes32) {
    return keccak256(abi.encode(lender, keccak256(abi.encode(uint256(expiry), uint256(8)))));
  }

  function _seed(Fixture memory f, uint32 expiry, uint128 total, uint128 paid, uint128 ownedA) private {
    bytes32 slot = _batchSlot(expiry);
    vm.store(address(f.market), slot, bytes32(uint256(total) | (uint256(total) << 128)));
    vm.store(address(f.market), bytes32(uint256(slot) + 1), bytes32(uint256(paid)));
    vm.store(address(f.market), _claimSlot(expiry, A), bytes32(uint256(ownedA)));
    vm.store(address(f.market), _claimSlot(expiry, B), bytes32(uint256(total - ownedA)));
    // Preserve accrued protocol fees in the low half; update U in the high half.
    uint256 fees = uint128(uint256(vm.load(address(f.market), bytes32(uint256(1)))));
    vm.store(address(f.market), bytes32(uint256(1)), bytes32(fees | (uint256(paid) << 128)));
    uint256 assets = f.asset.balanceOf(address(f.market));
    f.asset.mint(address(f.market), uint256(paid) - assets);
  }

  function test_uint128Ceiling_RevertsAtomicallyThenAllowsExitAndNextBatch() external {
    for (uint256 i; i < 4; ++i) {
      Fixture memory f = _fixture(i >= 2, i % 2 == 1);
      _deposit(f, A, 1);
      vm.prank(A);
      uint32 expiry = f.market.queueFullWithdrawal();
      uint128 prior = type(uint128).max - 1;
      _seed(f, expiry, prior, prior, prior);
      _deposit(f, A, 1);
      vm.prank(A);
      assertEq(f.market.queueFullWithdrawal(), expiry);
      WithdrawalBatch memory atLimit = f.market.getWithdrawalBatch(expiry);
      assertEq(atLimit.scaledTotalAmount, type(uint128).max);
      assertEq(atLimit.scaledAmountBurned, type(uint128).max);
      assertEq(atLimit.normalizedAmountPaid, type(uint128).max);
      assertEq(f.market.getAccountWithdrawalStatus(A, expiry).scaledAmount, type(uint128).max);

      _deposit(f, B, 1);
      bytes memory beforeState = abi.encode(f.market.previousState());
      vm.prank(B);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      f.market.queueFullWithdrawal();
      assertEq(abi.encode(f.market.previousState()), beforeState, 'failed queue is atomic');
      assertEq(f.market.scaledBalanceOf(B), 1, 'failed queue preserves balance');
      assertEq(f.market.getAccountWithdrawalStatus(B, expiry).scaledAmount, 0);
      assertEq(f.market.getWithdrawalBatch(expiry).scaledTotalAmount, type(uint128).max);

      vm.warp(uint256(expiry) + 1);
      assertEq(f.market.getAvailableWithdrawalAmount(A, expiry), type(uint128).max);
      assertEq(f.market.executeWithdrawal(A, expiry), type(uint128).max);
      assertEq(f.market.currentState().normalizedUnclaimedWithdrawals, 0);
      assertEq(f.market.getAccountWithdrawalStatus(A, expiry).normalizedAmountWithdrawn, type(uint128).max);
      vm.prank(B);
      uint32 next = f.market.queueFullWithdrawal();
      assertTrue(next > expiry);
      vm.warp(uint256(next) + 1);
      assertEq(f.market.executeWithdrawal(B, next), 1);
      assertEq(f.market.totalAssets(), 0);
    }
  }

  function testFuzz_wideMultiLenderClaims_PreservePackingAndConservePaidAmount(
    uint128 totalSeed, uint128 paidSeed, uint128 ownershipSeed, bool revolving, bool fixedTerm
  ) external {
    Fixture memory f = _fixture(revolving, fixedTerm);
    uint128 total = uint128(bound(totalSeed, uint256(type(uint104).max) + 1, type(uint128).max));
    uint128 paid = uint128(bound(paidSeed, total, type(uint128).max));
    uint128 ownedA = uint128(bound(ownershipSeed, 1, total - 1));
    uint32 expiry = 1;
    vm.warp(2);
    _seed(f, expiry, total, paid, ownedA);
    uint256 expectedA = uint256(paid) * ownedA / total;
    uint256 expectedB = uint256(paid) * (total - ownedA) / total;
    assertEq(f.market.getAvailableWithdrawalAmount(A, expiry), expectedA);
    assertEq(f.market.getAvailableWithdrawalAmount(B, expiry), expectedB);
    assertEq(f.market.executeWithdrawal(A, expiry), expectedA);
    assertEq(f.market.getAccountWithdrawalStatus(A, expiry).scaledAmount, ownedA, 'claim write preserves ownership');
    assertEq(f.market.executeWithdrawal(B, expiry), expectedB);
    uint256 dust = uint256(paid) - expectedA - expectedB;
    assertTrue(dust <= 1, 'only pro-rata dust remains');
    assertEq(f.market.totalAssets(), dust);
    assertEq(f.market.currentState().normalizedUnclaimedWithdrawals, dust);
    assertEq(f.market.getAvailableWithdrawalAmount(A, expiry), 0);
    assertEq(f.market.getAvailableWithdrawalAmount(B, expiry), 0);
  }

  function _setFactor(Fixture memory f, uint112 factor) private {
    uint256 packed = uint256(vm.load(address(f.market), bytes32(uint256(3))));
    uint256 mask = uint256(type(uint112).max) << 80;
    vm.store(address(f.market), bytes32(uint256(3)), bytes32((packed & ~mask) | (uint256(factor) << 80)));
  }

  function test_normalizedBatchCapacity_CanStrandUnpaidSharesAfterExpiry() external {
    for (uint256 i; i < 4; ++i) {
      Fixture memory f = _fixture(i >= 2, i % 2 == 1);
      _deposit(f, A, 1);
      vm.prank(A);
      uint32 expiry = f.market.queueFullWithdrawal();
      // Compressed history at F=2*RAY: all earlier shares fully paid, then
      // one more borrower-funded share can join without receiving payment.
      uint128 prior = type(uint128).max / 2;
      uint128 paid = type(uint128).max - 1;
      _seed(f, expiry, prior, paid, prior);
      _setFactor(f, uint112(2e27));
      _deposit(f, B, 2);
      // Keep all existing paid claims backed, but remove the new two units.
      vm.prank(Borrower);
      f.market.borrow(2);
      vm.prank(B);
      assertEq(f.market.queueFullWithdrawal(), expiry);
      assertEq(f.market.previousState().scaledPendingWithdrawals, 1);

      // Expiry permits collecting existing payments but does not reset the
      // normalized batch-payment counter. Its next two-unit payment overflows.
      vm.warp(uint256(expiry) + 1);
      assertEq(f.market.executeWithdrawal(A, expiry), paid - 2);
      // Pro-rata attribution gives the new lender one earlier paid unit;
      // the remaining atom is the existing per-lender allocation dust.
      assertEq(f.market.executeWithdrawal(B, expiry), 1);
      assertEq(f.market.totalAssets(), 1);
      f.asset.mint(address(f.market), 2);
      vm.prank(Borrower);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      f.market.repayAndProcessUnpaidWithdrawalBatches(0, 1);
      WithdrawalBatch memory batch = f.market.getWithdrawalBatch(expiry);
      assertEq(batch.scaledTotalAmount - batch.scaledAmountBurned, 1);
      assertEq(batch.normalizedAmountPaid, paid);
      assertEq(f.market.previousState().normalizedUnclaimedWithdrawals, 1, 'global capacity already released');
    }
  }

  function test_highFactorLifetimeVolume_AcceptsAnUnsettleableRequest() external {
    for (uint256 i; i < 4; ++i) {
      Options memory o = _defaultOptions(i % 2 == 1 ? HooksKind.FixedTerm : HooksKind.OpenTerm);
      o.revolving = i >= 2;
      o.maxTotalSupply = type(uint128).max;
      o.reserveRatioBips = 0;
      o.annualInterestBips = 0;
      o.commitmentFeeBips = 0;
      o.protocolFeeBips = 0;
      o.delinquencyFeeBips = 0;
      Fixture memory f = _newMarket(o);
      // The only injected condition is a legal high scale factor, standing in
      // for prior accrual. All batch/account/cash history uses public actions.
      _setFactor(f, uint112(4e33));
      uint256 amount = uint256(type(uint104).max) * 4_000_000;
      uint32 expiry;
      for (uint256 j; j < 4; ++j) {
        _deposit(f, A, amount);
        vm.prank(A);
        uint32 joined = f.market.queueFullWithdrawal();
        if (j == 0) expiry = joined;
        assertEq(joined, expiry);
      }
      assertEq(f.market.getWithdrawalBatch(expiry).normalizedAmountPaid, amount * 4);
      _deposit(f, A, amount);
      vm.prank(Borrower);
      f.market.borrow(amount);
      vm.prank(A);
      assertEq(f.market.queueFullWithdrawal(), expiry, 'request accepted without payment');
      assertEq(f.market.previousState().scaledPendingWithdrawals, type(uint104).max);

      vm.warp(uint256(expiry) + 1);
      assertEq(f.market.executeWithdrawal(A, expiry), amount * 4, 'earlier paid claims all exit');
      assertEq(f.market.previousState().normalizedUnclaimedWithdrawals, 0);
      vm.startPrank(Borrower);
      f.asset.approve(address(f.market), amount);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      f.market.repayAndProcessUnpaidWithdrawalBatches(amount, 1);
      vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
      f.market.closeMarket();
      vm.stopPrank();
      WithdrawalBatch memory batch = f.market.getWithdrawalBatch(expiry);
      assertEq(batch.scaledTotalAmount - batch.scaledAmountBurned, type(uint104).max);
      assertEq(batch.normalizedAmountPaid, amount * 4, 'immutable lifetime payment ceiling');
    }
  }
}

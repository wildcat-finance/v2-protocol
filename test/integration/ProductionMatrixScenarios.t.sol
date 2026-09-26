// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { VmSafe } from 'forge-std/Vm.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { TemporaryReserveRatio } from 'src/access/MarketConstraintHooks.sol';
import { AprValidationPolicy } from '../mocks/AprValidationPolicy.sol';
import { AprReplacementPolicy } from '../mocks/AprReplacementPolicy.sol';
import { OpenAprReplacementHooks } from '../mocks/AprReplacementHooks.sol';
import { FixedAprReplacementHooks } from '../mocks/AprReplacementHooks.sol';
import { PeriodicAprReplacementHooks } from '../mocks/AprReplacementHooks.sol';
import { BaseHooks } from 'src/access/BaseHooks.sol';
import { IHooksFactory } from 'src/IHooksFactory.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { FixedTermPolicy } from 'src/access/FixedTermPolicy.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { PendingAprChange, PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { PeriodicTermPolicy } from 'src/access/PeriodicTermPolicy.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { IWildcatSanctionsEscrow } from 'src/interfaces/IWildcatSanctionsEscrow.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { MarketParameterConstraints } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketLensCore } from 'src/lens/MarketLensCore.sol';
import { MarketLensAggregator } from 'src/lens/MarketLensAggregator.sol';
import { MarketDataV2_5 } from 'src/lens/MarketData.sol';
import { MarketHooksData, HooksInstanceKind } from 'src/lens/HooksConfigData.sol';
import { HooksInstanceData } from 'src/lens/HooksInstanceData.sol';
import { RoleProviderData } from 'src/lens/RoleProviderData.sol';
import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { BorrowAmountPolicy } from '../mocks/BorrowAmountPolicy.sol';
import { OpenBorrowHooks } from '../mocks/BorrowFeatureHooks.sol';
import { FixedBorrowHooks } from '../mocks/BorrowFeatureHooks.sol';
import { PeriodicBorrowHooks } from '../mocks/BorrowFeatureHooks.sol';
import { RecipientRestrictionPolicy } from '../mocks/TransferFeaturePolicies.sol';
import { TransferAmountPolicy } from '../mocks/TransferFeaturePolicies.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

contract ProductionMatrixScenariosTest is ProductionMatrixFixture {
  uint256 internal constant AliceDeposit = 100_000e18;
  uint256 internal constant BobDeposit = 50_000e18;
  uint128 internal constant MinimumDeposit = 10_000e18;

  function _aprReplacementArtifacts() private pure returns (string[3] memory) {
    return [
      string.concat('test/mocks/AprReplacementHooks.sol:', type(OpenAprReplacementHooks).name),
      string.concat('test/mocks/AprReplacementHooks.sol:', type(FixedAprReplacementHooks).name),
      string.concat('test/mocks/AprReplacementHooks.sol:', type(PeriodicAprReplacementHooks).name)
    ];
  }

  function _replacementConfig(address hooks) private view returns (HooksConfig) {
    return
      IHooks(hooks).config().optionalFlags().setHooksAddress(hooks).mergeAllFlags(
        IHooks(hooks).config().requiredFlags()
      );
  }

  function _setAprBounds(MatrixCell memory cell, uint16 floor, uint16 ceiling) private {
    vm.prank(MatrixBorrower);
    AprValidationPolicy(address(cell.hooks)).setValidationBounds(floor, ceiling);
  }

  function _pendingAprHash(MatrixCell memory cell) private view returns (bytes32) {
    (PendingAprChange memory pending, uint32 start, uint32 end) = PeriodicTermPolicy(
      address(cell.hooks)
    ).getPendingAprChange(address(cell.market));
    return keccak256(abi.encode(pending, start, end));
  }

  function _temporaryReserveHash(MatrixCell memory cell) private view returns (bytes32) {
    (uint16 apr, uint16 reserve, uint32 expiry) = BaseHooks(address(cell.hooks))
      .temporaryExcessReserveRatio(address(cell.market));
    return keccak256(abi.encode(expiry, apr, reserve));
  }

  function test_replacementFactoriesApplyEffectiveAprAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack(_aprReplacementArtifacts());
    for (uint256 i; i < 6; i++) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind(i % 3),
        MatrixMarketKind(i / 3)
      );
      IHooksFactory factory = _factoryFor(stack, options.marketKind);
      vm.prank(MatrixBorrower);
      address hooks = factory.deployHooksInstance(stack.hooksTemplates[i % 3], '');
      // APR validation belongs to updates. these bounds would reject the creation values.
      vm.prank(MatrixBorrower);
      AprValidationPolicy(hooks).setValidationBounds(1_001, 1_999);
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(300 + i),
        _replacementConfig(hooks)
      );
      assertEq(cell.market.annualInterestBips(), 1_000, 'creation APR');
      assertEq(cell.market.reserveRatioBips(), 2_000, 'creation reserves');
      assertEq(
        AprReplacementPolicy(hooks).lastSelectedApr(address(cell.market)),
        0,
        'no creation update'
      );
      assertEq(
        factory.getHooksTemplateForInstance(hooks),
        cell.hooksTemplate,
        'replacement template'
      );
      assertTrue(
        stack.archController.isRegisteredMarket(address(cell.market)),
        'replacement registered'
      );
      assertTrue(
        cell.market.hooks().useOnSetAnnualInterestAndReserveRatioBips(),
        'APR dispatch enabled'
      );
      vm.prank(MatrixBorrower);
      cell.hooks.addRoleProvider(address(stack.roleProvider), type(uint32).max);
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _approveBorrower(stack, cell, AliceDeposit);
      _borrow(cell, cell.market.borrowableAssets());
      bytes32 beforeState = keccak256(abi.encode(cell.market.previousState()));

      _setAprBounds(cell, 1_100, 3_332);
      vm.prank(MatrixBorrower);
      vm.expectRevert(
        abi.encodeWithSelector(AprValidationPolicy.ReserveAboveCeiling.selector, uint16(3_333))
      );
      cell.market.setAnnualInterestAndReserveRatioBips(1_100, 0);
      assertEq(
        AprReplacementPolicy(hooks).lastSelectedApr(address(cell.market)),
        0,
        'validation rolls back selection'
      );
      assertEq(
        keccak256(abi.encode(cell.market.previousState())),
        beforeState,
        'validation rolls back market'
      );

      _setAprBounds(cell, 1_100, 3_333);
      vm.prank(MatrixBorrower);
      vm.expectRevert(IMarketEventsAndErrors.InsufficientReservesForNewLiquidityRatio.selector);
      cell.market.setAnnualInterestAndReserveRatioBips(1_100, 0);
      assertEq(
        AprReplacementPolicy(hooks).lastSelectedApr(address(cell.market)),
        0,
        'core rejection rolls back selection'
      );
      assertEq(
        keccak256(abi.encode(cell.market.previousState())),
        beforeState,
        'core rejection rolls back market'
      );

      _repay(cell, 20_000e18);
      vm.expectEmit(address(cell.hooks));
      emit AprReplacementPolicy.AprDefaultSelected(address(cell.market), 1_100, 3_333);
      vm.expectEmit(address(cell.market));
      emit IMarketEventsAndErrors.AnnualInterestAndReserveRatioBipsUpdated(
        MatrixBorrower,
        1_000,
        1_100,
        2_000,
        3_333
      );
      vm.prank(MatrixBorrower);
      cell.market.setAnnualInterestAndReserveRatioBips(1_100, 0);
      assertEq(cell.market.annualInterestBips(), 1_100, 'effective APR stored');
      assertEq(cell.market.reserveRatioBips(), 3_333, 'effective reserves stored');
      assertEq(
        AprReplacementPolicy(hooks).lastSelectedApr(address(cell.market)),
        1_100,
        'selection committed'
      );
      assertEq(
        stack.asset.balanceOf(address(cell.market)),
        40_000e18,
        'APR update moves no assets'
      );
    }
  }

  function _callReplacementReduction(
    MatrixCell memory cell,
    bool dedicated
  ) private returns (bool success, bytes memory result) {
    bytes memory data = dedicated
      ? abi.encodeWithSelector(cell.market.executePendingAnnualInterestBipsReduction.selector)
      : abi.encodeWithSelector(
        cell.market.setAnnualInterestAndReserveRatioBips.selector,
        uint16(800),
        uint16(7_777)
      );
    vm.prank(dedicated ? MatrixCaller : MatrixBorrower);
    return address(cell.market).call(bytes.concat(data, hex'deadbeef'));
  }

  function _assertReductionRejection(
    MatrixCell memory cell,
    bool dedicated,
    bytes memory reason
  ) private {
    bytes32 proposal = _pendingAprHash(cell);
    bytes32 state = keccak256(abi.encode(cell.market.previousState()));
    bytes32 temporaryReserve = _temporaryReserveHash(cell);
    (bool success, bytes memory result) = _callReplacementReduction(cell, dedicated);
    assertFalse(success, 'reduction rejected');
    assertEq(result, reason, 'reduction rejection reason');
    assertEq(_pendingAprHash(cell), proposal, 'proposal restored');
    assertEq(keccak256(abi.encode(cell.market.previousState())), state, 'market state restored');
    assertEq(_temporaryReserveHash(cell), temporaryReserve, 'temporary reserve preserved');
    assertEq(
      AprReplacementPolicy(address(cell.hooks)).lastSelectedApr(address(cell.market)),
      0,
      'replacement default skipped'
    );
  }

  function _assertDedicatedCallData(MatrixCell memory cell, MarketState memory state) private {
    VmSafe.AccountAccess[] memory calls = vm.stopAndReturnStateDiff();
    uint256 hookCalls;
    for (uint256 i; i < calls.length; i++) {
      if (
        calls[i].kind == VmSafe.AccountAccessKind.Call && calls[i].account == address(cell.hooks)
      ) {
        assertEq(calls[i].accessor, address(cell.market), 'market calls hook');
        assertEq(
          calls[i].data,
          abi.encodeCall(PeriodicTermPolicy.executePendingAnnualInterestBipsReduction, (state)),
          'dedicated callback excludes trailing bytes'
        );
        assertFalse(calls[i].reverted, 'dedicated callback accepted');
        hookCalls++;
      }
    }
    assertEq(hookCalls, 1, 'one dedicated callback');
  }

  function test_replacementPeriodicExecutionRechecksBothMarketRoutes() external {
    ProductionStack memory stack = _deployProductionStack(_aprReplacementArtifacts());
    for (uint256 i; i < 4; i++) {
      bool dedicated = i % 2 == 1;
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        _defaultMatrixOptions(MatrixHooksKind.PeriodicTerm, MatrixMarketKind(i / 2)),
        MatrixBorrower,
        MatrixBorrower,
        uint96(310 + i)
      );
      PeriodicAprReplacementHooks hooks = PeriodicAprReplacementHooks(address(cell.hooks));
      _authorize(stack, cell, MatrixAlice);
      _authorize(stack, cell, MatrixBob);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _deposit(stack, cell, MatrixBob, BobDeposit);
      _approveBorrower(stack, cell, AliceDeposit + BobDeposit);
      _borrow(cell, cell.market.borrowableAssets());
      vm.startPrank(MatrixBorrower);
      hooks.seedTemporaryReserve(
        address(cell.market),
        TemporaryReserveRatio(1_200, 1_500, uint32(cell.deployedAt + 1))
      );
      hooks.proposeAnnualInterestBips(address(cell.market), 800);
      vm.stopPrank();
      (, uint32 responseStart, uint32 responseEnd) = hooks.getPendingAprChange(
        address(cell.market)
      );
      bytes32 temporaryReserve = _temporaryReserveHash(cell);
      _setAprBounds(cell, 801, 10_000);
      vm.warp(responseStart);
      vm.prank(MatrixAlice);
      uint32 expiry = cell.market.queueFullWithdrawal();
      vm.warp(uint256(responseEnd) - 1);
      _assertReductionRejection(
        cell,
        dedicated,
        abi.encodeWithSelector(PeriodicTermPolicy.AprChangeNotReady.selector)
      );
      vm.warp(responseEnd);
      cell.market.updateState();
      assertTrue(
        cell.market.previousState().scaledPendingWithdrawals > 0,
        'unpaid response withdrawal'
      );
      _assertReductionRejection(
        cell,
        dedicated,
        abi.encodeWithSelector(PeriodicTermPolicy.UnpaidWithdrawalsExist.selector)
      );

      uint256 shortfall = cell.market.currentState().totalDebts() - cell.market.totalAssets();
      vm.prank(MatrixBorrower);
      cell.market.repayAndProcessUnpaidWithdrawalBatches(shortfall, 1);
      assertEq(
        cell.market.previousState().scaledPendingWithdrawals,
        0,
        'response withdrawal funded'
      );
      // payment is required; claiming is not. the proposal stays blocked by the changed APR floor.
      assertTrue(
        cell.market.getAvailableWithdrawalAmount(MatrixAlice, expiry) > 0,
        'paid claim remains unexecuted'
      );
      _assertReductionRejection(
        cell,
        dedicated,
        abi.encodeWithSelector(AprValidationPolicy.AprBelowFloor.selector, uint16(800))
      );
      _setAprBounds(cell, 800, 1_999);
      _assertReductionRejection(
        cell,
        dedicated,
        abi.encodeWithSelector(AprValidationPolicy.ReserveAboveCeiling.selector, uint16(2_000))
      );
      _setAprBounds(cell, 800, 2_000);

      MarketState memory state = cell.market.currentState();
      uint256 assets = stack.asset.balanceOf(address(cell.market));
      vm.expectEmit(address(cell.hooks));
      emit PeriodicTermPolicy.AnnualInterestBipsReductionExecuted(address(cell.market), 800);
      vm.expectEmit(address(cell.market));
      emit IMarketEventsAndErrors.AnnualInterestAndReserveRatioBipsUpdated(
        dedicated ? MatrixCaller : MatrixBorrower,
        1_000,
        800,
        2_000,
        2_000
      );
      if (dedicated) vm.startStateDiffRecording();
      (bool success, bytes memory result) = _callReplacementReduction(cell, dedicated);
      assertTrue(success, 'restored bounds permit execution');
      assertEq(result.length, 0, 'market execution has no return payload');
      if (dedicated) _assertDedicatedCallData(cell, state);
      assertEq(cell.market.annualInterestBips(), 800, 'proposed APR stored');
      assertEq(cell.market.reserveRatioBips(), 2_000, 'both routes keep current reserves');
      assertEq(
        hooks.lastSelectedApr(address(cell.market)),
        0,
        'neither route selects replacement reserves'
      );
      assertEq(
        _temporaryReserveHash(cell),
        temporaryReserve,
        'neither route expires temporary reserves'
      );
      (PendingAprChange memory pending, , ) = hooks.getPendingAprChange(address(cell.market));
      assertEq(pending.proposalTimestamp, 0, 'executed proposal cleared');
      assertEq(
        stack.asset.balanceOf(address(cell.market)),
        assets,
        'APR execution moves no assets'
      );
      uint256 aliceAssets = stack.asset.balanceOf(MatrixAlice);
      uint256 claim = cell.market.getAvailableWithdrawalAmount(MatrixAlice, expiry);
      cell.market.executeWithdrawal(MatrixAlice, expiry);
      assertEq(
        stack.asset.balanceOf(MatrixAlice) - aliceAssets,
        claim,
        'paid response withdrawal claimed'
      );
    }
  }

  function test_replacementPeriodicEqualityAndIncreaseUseMarketState() external {
    ProductionStack memory stack = _deployProductionStack(_aprReplacementArtifacts());
    for (uint256 i; i < 2; i++) {
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        _defaultMatrixOptions(MatrixHooksKind.PeriodicTerm, MatrixMarketKind(i)),
        MatrixBorrower,
        MatrixBorrower,
        uint96(320 + i)
      );
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      PeriodicAprReplacementHooks hooks = PeriodicAprReplacementHooks(address(cell.hooks));
      vm.prank(MatrixBorrower);
      hooks.proposeAnnualInterestBips(address(cell.market), 800);
      bytes32 proposal = _pendingAprHash(cell);
      vm.prank(MatrixBorrower);
      cell.market.setAnnualInterestAndReserveRatioBips(1_000, 0);
      assertEq(_pendingAprHash(cell), proposal, 'equality retains proposal');
      assertEq(cell.market.reserveRatioBips(), 3_333, 'equality applies replacement reserves');
      assertEq(hooks.lastSelectedApr(address(cell.market)), 1_000, 'equality recorded');

      _setAprBounds(cell, 1_101, 10_000);
      bytes32 state = keccak256(abi.encode(cell.market.previousState()));
      vm.prank(MatrixBorrower);
      vm.expectRevert(
        abi.encodeWithSelector(AprValidationPolicy.AprBelowFloor.selector, uint16(1_100))
      );
      cell.market.setAnnualInterestAndReserveRatioBips(1_100, 0);
      assertEq(_pendingAprHash(cell), proposal, 'rejected increase restores cancellation');
      assertEq(
        keccak256(abi.encode(cell.market.previousState())),
        state,
        'rejected increase restores market'
      );
      assertEq(
        hooks.lastSelectedApr(address(cell.market)),
        1_000,
        'rejected increase restores prior selection'
      );
      _setAprBounds(cell, 1_100, 3_333);
      vm.expectEmit(address(cell.hooks));
      emit PeriodicTermPolicy.AnnualInterestBipsReductionProposalCancelled(address(cell.market));
      vm.expectEmit(address(cell.hooks));
      emit AprReplacementPolicy.AprDefaultSelected(address(cell.market), 1_100, 3_333);
      vm.prank(MatrixBorrower);
      cell.market.setAnnualInterestAndReserveRatioBips(1_100, 0);
      (PendingAprChange memory pending, , ) = hooks.getPendingAprChange(address(cell.market));
      assertEq(pending.proposalTimestamp, 0, 'accepted increase cancels proposal');
      assertEq(cell.market.annualInterestBips(), 1_100, 'increased APR stored');
      assertEq(hooks.lastSelectedApr(address(cell.market)), 1_100, 'increase recorded');
    }
  }

  function _queueClosingBatch(MatrixCell memory cell) private returns (uint32 expiry) {
    vm.warp(cell.deployedAt + 1 days);
    if (cell.options.hooksKind == MatrixHooksKind.FixedTerm) {
      vm.prank(MatrixAlice);
      vm.expectRevert(FixedTermPolicy.WithdrawBeforeTermEnd.selector);
      cell.market.queueWithdrawal(AliceDeposit / 2);
      return 0;
    }
    vm.prank(MatrixAlice);
    expiry = cell.market.queueWithdrawal(AliceDeposit / 2);
    vm.prank(MatrixBob);
    assertEq(cell.market.queueWithdrawal(BobDeposit / 2), expiry, 'lenders share pre-close batch');
    assertEq(
      expiry,
      vm.getBlockTimestamp() + cell.options.withdrawalBatchDuration,
      'market chooses batch duration'
    );
  }

  function _claimSharedBatch(
    ProductionStack memory stack,
    MatrixCell memory cell,
    uint32 expiry
  ) private {
    WithdrawalBatch memory batch = cell.market.getWithdrawalBatch(expiry);
    assertEq(batch.scaledAmountBurned, batch.scaledTotalAmount, 'batch fully funded');
    address[2] memory lenders = [MatrixBob, MatrixAlice];
    for (uint256 i; i < 2; i++) {
      uint256 claim = (uint256(batch.normalizedAmountPaid) *
        cell.market.getAccountWithdrawalStatus(lenders[i], expiry).scaledAmount) /
        batch.scaledTotalAmount;
      uint256 assets = stack.asset.balanceOf(lenders[i]);
      assertEq(cell.market.executeWithdrawal(lenders[i], expiry), claim, 'pro-rata batch claim');
      assertEq(stack.asset.balanceOf(lenders[i]) - assets, claim, 'batch assets received');
    }
  }

  function test_replacementClosureRetainsBatchingAndAccessAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack(_aprReplacementArtifacts());
    for (uint256 i; i < 6; i++) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind(i % 3),
        MatrixMarketKind(i / 3)
      );
      options.firstWindowDelay = 1 days;
      options.withdrawalWindowDuration = 1 days;
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(330 + i)
      );
      _authorize(stack, cell, MatrixAlice);
      _authorize(stack, cell, MatrixBob);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _deposit(stack, cell, MatrixBob, BobDeposit);
      _approveBorrower(stack, cell, AliceDeposit + BobDeposit);
      vm.prank(MatrixBorrower);
      cell.market.setAnnualInterestAndReserveRatioBips(1_100, 0);
      _borrow(cell, cell.market.borrowableAssets());
      if (options.hooksKind == MatrixHooksKind.PeriodicTerm) {
        vm.prank(MatrixBorrower);
        PeriodicTermPolicy(address(cell.hooks)).proposeAnnualInterestBips(
          address(cell.market),
          800
        );
      }
      uint32 expiry = _queueClosingBatch(cell);
      vm.warp(cell.deployedAt + 2 days + 1);
      cell.market.updateState();
      if (expiry != 0)
        assertTrue(
          cell.market.previousState().scaledPendingWithdrawals > 0,
          'closure must fund unpaid batch'
        );
      if (options.hooksKind == MatrixHooksKind.PeriodicTerm) {
        assertFalse(
          PeriodicTermPolicy(address(cell.hooks)).isWithdrawalWindowOpen(address(cell.market)),
          'schedule closed before market closure'
        );
      }
      // closeMarket forces APR zero and 100% reserves. this example deliberately permits it.
      _setAprBounds(cell, 1_200, 3_333);
      uint256 marketAssets = stack.asset.balanceOf(address(cell.market));
      uint256 borrowerAssets = stack.asset.balanceOf(MatrixBorrower);
      uint256 shortfall = cell.market.currentState().totalDebts() - marketAssets;
      vm.expectEmit(address(cell.market));
      emit IMarketEventsAndErrors.DebtRepaid(MatrixBorrower, shortfall);
      vm.expectEmit(address(cell.market));
      emit IMarketEventsAndErrors.AnnualInterestAndReserveRatioBipsUpdated(
        MatrixBorrower,
        1_100,
        0,
        3_333,
        10_000
      );
      vm.expectEmit(address(cell.market));
      emit IMarketEventsAndErrors.MarketClosed(MatrixBorrower, vm.getBlockTimestamp());
      _close(cell);
      assertTrue(cell.market.isClosed(), 'replacement market closed');
      assertEq(cell.market.annualInterestBips(), 0, 'core closure APR');
      assertEq(cell.market.reserveRatioBips(), 10_000, 'core closure reserves');
      assertEq(
        stack.asset.balanceOf(MatrixBorrower),
        borrowerAssets - shortfall,
        'borrower funded closure'
      );
      assertEq(
        stack.asset.balanceOf(address(cell.market)),
        marketAssets + shortfall,
        'market received closure debt'
      );
      assertEq(
        AprReplacementPolicy(address(cell.hooks)).lastSelectedApr(address(cell.market)),
        1_100,
        'closure skips APR selection'
      );
      assertEq(
        cell.market.previousState().scaledPendingWithdrawals,
        0,
        'closure funded all withdrawals'
      );
      assertEq(cell.market.getUnpaidBatchExpiries().length, 0, 'closure cleared unpaid queue');
      if (options.marketKind == MatrixMarketKind.Revolving)
        assertEq(
          IWildcatMarketRevolving(address(cell.market)).drawnAmount(),
          0,
          'closure clears drawn principal'
        );
      if (options.hooksKind == MatrixHooksKind.FixedTerm)
        assertEq(
          FixedAprReplacementHooks(address(cell.hooks))
            .getHookedMarket(address(cell.market))
            .fixedTermEndTime,
          vm.getBlockTimestamp(),
          'early closure moves maturity'
        );
      if (options.hooksKind == MatrixHooksKind.PeriodicTerm) {
        PeriodicAprReplacementHooks hooks = PeriodicAprReplacementHooks(address(cell.hooks));
        assertTrue(
          hooks.getHookedMarket(address(cell.market)).isClosed,
          'periodic schedule closed'
        );
        assertTrue(
          hooks.isWithdrawalWindowOpen(address(cell.market)),
          'closure removes schedule restriction'
        );
        (PendingAprChange memory pending, , ) = hooks.getPendingAprChange(address(cell.market));
        assertEq(pending.proposalTimestamp, 0, 'closure cancels proposal');
      }
      vm.prank(MatrixCaller);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      cell.market.queueWithdrawal(1e18);
      if (expiry != 0) _claimSharedBatch(stack, cell, expiry);

      vm.prank(MatrixBorrower);
      cell.hooks.blockFromDeposits(MatrixBob);
      vm.prank(MatrixAlice);
      uint32 finalExpiry = cell.market.queueFullWithdrawal();
      vm.prank(MatrixBob);
      assertEq(
        cell.market.queueFullWithdrawal(),
        finalExpiry,
        'known blocked lender shares post-close batch'
      );
      assertEq(finalExpiry, vm.getBlockTimestamp(), 'closed batch has zero duration');
      vm.expectRevert(IMarketEventsAndErrors.WithdrawalBatchNotExpired.selector);
      cell.market.executeWithdrawal(MatrixAlice, finalExpiry);
      vm.warp(uint256(finalExpiry) + 1);
      _claimSharedBatch(stack, cell, finalExpiry);
      assertEq(cell.market.previousState().scaledTotalSupply, 0, 'closed market drained');
      assertTrue(
        stack.asset.balanceOf(address(cell.market)) <= MatrixDust,
        'only rounding dust remains'
      );
    }
  }

  function test_replacementFixedClosurePermissionsRemainIndependentAcrossMarkets() external {
    ProductionStack memory stack = _deployProductionStack(_aprReplacementArtifacts());
    for (uint256 i; i < 8; i++) {
      bool allowClosure = (i % 4 & 1) != 0;
      bool allowReduction = (i % 4 & 2) != 0;
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind.FixedTerm,
        MatrixMarketKind(i / 4)
      );
      vm.prank(MatrixBorrower);
      address hooksAddress = _factoryFor(stack, options.marketKind).deployHooksInstance(
        stack.hooksTemplates[1],
        ''
      );
      FixedAprReplacementHooks hooks = FixedAprReplacementHooks(hooksAddress);
      uint32 term = uint32(vm.getBlockTimestamp() + options.fixedTermDuration);
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(340 + i),
        _replacementConfig(hooksAddress),
        abi.encode(term, uint128(0), false, allowClosure, allowReduction)
      );
      vm.prank(MatrixBorrower);
      hooks.addRoleProvider(address(stack.roleProvider), type(uint32).max);
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _approveBorrower(stack, cell, AliceDeposit);
      _borrow(cell, 50_000e18);
      _setAprBounds(cell, 1_001, 1_999);
      vm.prank(MatrixBorrower);
      if (!allowReduction) vm.expectRevert(FixedTermPolicy.TermReductionDisabled.selector);
      hooks.setFixedTermEndTime(address(cell.market), term - 1 days);
      assertEq(
        hooks.getHookedMarket(address(cell.market)).fixedTermEndTime,
        allowReduction ? term - 1 days : term,
        'setter uses its own permissions'
      );
      assertEq(hooks.lastSelectedApr(address(cell.market)), 0, 'setter does not select APR');

      if (!allowClosure && !allowReduction) {
        bytes32 state = keccak256(abi.encode(cell.market.previousState()));
        uint256 borrowerAssets = stack.asset.balanceOf(MatrixBorrower);
        uint256 marketAssets = stack.asset.balanceOf(address(cell.market));
        vm.prank(MatrixBorrower);
        vm.expectRevert(FixedTermPolicy.ClosureDisabledBeforeTerm.selector);
        cell.market.closeMarket();
        assertEq(
          keccak256(abi.encode(cell.market.previousState())),
          state,
          'rejected closure restores state'
        );
        assertEq(
          stack.asset.balanceOf(MatrixBorrower),
          borrowerAssets,
          'rejected closure restores borrower funds'
        );
        assertEq(
          stack.asset.balanceOf(address(cell.market)),
          marketAssets,
          'rejected closure restores repayment'
        );
        vm.warp(term);
      }
      _close(cell);
      assertTrue(cell.market.isClosed(), 'either permission or maturity permits closure');
      assertEq(
        hooks.getHookedMarket(address(cell.market)).fixedTermEndTime,
        vm.getBlockTimestamp(),
        'closure maturity'
      );
      assertEq(hooks.lastSelectedApr(address(cell.market)), 0, 'closure does not select APR');
    }
  }

  function _borrowArtifacts() private pure returns (string[3] memory) {
    return [
      string.concat('test/mocks/BorrowFeatureHooks.sol:', type(OpenBorrowHooks).name),
      string.concat('test/mocks/BorrowFeatureHooks.sol:', type(FixedBorrowHooks).name),
      string.concat('test/mocks/BorrowFeatureHooks.sol:', type(PeriodicBorrowHooks).name)
    ];
  }

  function _deployBorrowCell(
    ProductionStack memory stack,
    uint256 index
  ) private returns (MatrixCell memory cell) {
    MatrixOptions memory options = _defaultMatrixOptions(
      MatrixHooksKind(index % 3),
      MatrixMarketKind(index / 3)
    );
    IHooksFactory factory = _factoryFor(stack, options.marketKind);
    vm.prank(MatrixBorrower);
    address hooks = factory.deployHooksInstance(stack.hooksTemplates[index % 3], '');
    // request deposit credentials only. the composition must force borrow/transfer dispatch itself.
    HooksConfig requested = EmptyHooksConfig.setHooksAddress(hooks).setFlag(Bit_Enabled_Deposit);
    cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      uint96(200 + index),
      requested
    );
    vm.prank(MatrixBorrower);
    cell.hooks.addRoleProvider(address(stack.roleProvider), type(uint32).max);
  }

  function test_fourPolicyFactoriesForceCallbacksAcrossProductionMatrix() external {
    string[3] memory artifacts = _borrowArtifacts();
    ProductionStack memory stack = _deployProductionStack(artifacts);
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _deployBorrowCell(stack, i);
      IHooks hooks = IHooks(address(cell.hooks));
      IHooksFactory factory = _factoryFor(stack, cell.options.marketKind);
      assertEq(cell.market.factory(), address(factory), 'composed market factory');
      assertEq(hooks.factory(), address(factory), 'composed hooks factory');
      assertEq(cell.hooks.administrator(), MatrixBorrower, 'composed administrator');
      assertEq(
        factory.getHooksTemplateForInstance(address(cell.hooks)),
        cell.hooksTemplate,
        'composed stored template'
      );
      assertEq(
        factory.getMarketsForHooksInstanceCount(address(cell.hooks)),
        1,
        'composed market count'
      );
      assertTrue(
        stack.archController.isRegisteredMarket(address(cell.market)),
        'composed registration'
      );
      assertTrue(hooks.config().requiredFlags().useOnBorrow(), 'declared borrow requirement');
      assertTrue(hooks.config().requiredFlags().useOnTransfer(), 'declared transfer requirement');
      assertTrue(cell.market.hooks().useOnBorrow(), 'forced borrow dispatch');
      assertTrue(cell.market.hooks().useOnTransfer(), 'forced transfer dispatch');
      assertEq(
        HooksConfig.unwrap(cell.market.hooks()),
        HooksConfig.unwrap(
          hooks.config().requiredFlags().setFlag(Bit_Enabled_Deposit).setHooksAddress(
            address(hooks)
          )
        ),
        'effective flags match declaration'
      );
      assertEq(
        BorrowAmountPolicy(address(hooks)).maximumNormalizedBorrow(address(cell.market)),
        cell.options.maxTotalSupply,
        'borrow default'
      );
      assertEq(
        TransferAmountPolicy(address(hooks)).maximumScaledTransfer(address(cell.market)),
        cell.options.maxTotalSupply,
        'transfer default retained'
      );
      assertEq(
        BorrowAmountPolicy(address(hooks)).lastNormalizedBorrow(address(cell.market)),
        0,
        'no initial borrow'
      );

      bytes memory creation = vm.getCode(artifacts[i % 3]);
      assertEq(
        cell.hooksTemplate.code,
        abi.encodePacked(hex'00', creation),
        'actual stored initcode'
      );
      assertTrue(cell.hooksTemplate.code.length <= 24_576, 'stored initcode limit');
      assertTrue(address(hooks).code.length <= 24_576, 'composed runtime limit');
      assertTrue(
        abi.encodePacked(creation, abi.encode(MatrixBorrower, bytes(''))).length <= 49_152,
        'constructor payload limit'
      );
    }
  }

  function test_fourPolicyBorrowLimitsRetainTransferRulesAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack(_borrowArtifacts());
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _deployBorrowCell(stack, i);
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      // move scaleFactor off RAY. the borrow limit still uses the asset amount, not scaled shares.
      vm.warp(vm.getBlockTimestamp() + 1 days);
      cell.market.updateState();
      assertTrue(cell.market.scaleFactor() > 1e27, 'interest accrued');
      BorrowAmountPolicy feature = BorrowAmountPolicy(address(cell.hooks));
      vm.prank(MatrixBorrower);
      feature.setBorrowAmountLimit(address(cell.market), 100e18);
      _assertRecordedBorrow(stack, cell, 25e18);
      _assertRecordedBorrow(stack, cell, 100e18);

      uint256 marketAssets = stack.asset.balanceOf(address(cell.market));
      uint256 borrowerAssets = stack.asset.balanceOf(MatrixBorrower);
      bytes32 previousState = keccak256(abi.encode(cell.market.previousState()));
      vm.prank(MatrixBorrower);
      vm.expectRevert(BorrowAmountPolicy.BorrowAmountLimitExceeded.selector);
      cell.market.borrow(100e18 + 1);
      assertEq(
        feature.lastNormalizedBorrow(address(cell.market)),
        100e18,
        'rejected borrow not recorded'
      );
      assertEq(stack.asset.balanceOf(address(cell.market)), marketAssets, 'rejected market assets');
      assertEq(stack.asset.balanceOf(MatrixBorrower), borrowerAssets, 'rejected borrower assets');
      assertEq(
        keccak256(abi.encode(cell.market.previousState())),
        previousState,
        'rejected borrow state'
      );
      _assertComposedTransfers(cell);
    }
  }

  function _assertRecordedBorrow(
    ProductionStack memory stack,
    MatrixCell memory cell,
    uint256 amount
  ) private {
    uint256 marketAssets = stack.asset.balanceOf(address(cell.market));
    uint256 borrowerAssets = stack.asset.balanceOf(MatrixBorrower);
    uint256 drawn;
    if (cell.options.marketKind == MatrixMarketKind.Revolving) {
      drawn = IWildcatMarketRevolving(address(cell.market)).drawnAmount();
    }
    vm.expectEmit(true, false, false, true, address(cell.hooks));
    emit BorrowAmountPolicy.BorrowAmountRecorded(address(cell.market), amount);
    _borrow(cell, amount);
    assertEq(
      BorrowAmountPolicy(address(cell.hooks)).lastNormalizedBorrow(address(cell.market)),
      amount,
      'accepted normalized amount'
    );
    assertEq(
      stack.asset.balanceOf(address(cell.market)),
      marketAssets - amount,
      'borrowed market assets'
    );
    assertEq(
      stack.asset.balanceOf(MatrixBorrower),
      borrowerAssets + amount,
      'borrower received assets'
    );
    if (cell.options.marketKind == MatrixMarketKind.Revolving) {
      assertEq(
        IWildcatMarketRevolving(address(cell.market)).drawnAmount(),
        drawn + amount,
        'drawn principal'
      );
    }
  }

  function _assertComposedTransfers(MatrixCell memory cell) private {
    TransferAmountPolicy amountFeature = TransferAmountPolicy(address(cell.hooks));
    RecipientRestrictionPolicy recipientFeature = RecipientRestrictionPolicy(address(cell.hooks));
    vm.startPrank(MatrixBorrower);
    amountFeature.setTransferAmountLimit(address(cell.market), 1e18);
    recipientFeature.setRestrictedRecipient(address(cell.market), MatrixBob);
    vm.stopPrank();

    vm.prank(MatrixAlice);
    vm.expectRevert(RecipientRestrictionPolicy.RecipientRestricted.selector);
    cell.market.transfer(MatrixBob, 1e18);
    assertEq(
      amountFeature.scaledTransferVolume(address(cell.market)),
      0,
      'recipient failure rolls back volume'
    );
    vm.prank(MatrixAlice);
    vm.expectRevert(TransferAmountPolicy.TransferAmountLimitExceeded.selector);
    cell.market.transfer(MatrixCaller, 2e18);
    assertEq(cell.market.scaledBalanceOf(MatrixCaller), 0, 'amount failure rolls back transfer');

    // MatrixCaller has no credentials. forced dispatch must not require transfer credentials.
    vm.prank(MatrixAlice);
    cell.market.transfer(MatrixCaller, 1e18);
    assertTrue(cell.market.scaledBalanceOf(MatrixCaller) > 0, 'accepted transfer');
    assertEq(
      amountFeature.scaledTransferVolume(address(cell.market)),
      cell.market.scaledBalanceOf(MatrixCaller),
      'accepted scaled volume'
    );
  }

  function test_fourPolicyBorrowAuthorityAndMarketsStayIsolated() external {
    ProductionStack memory stack = _deployProductionStack(_borrowArtifacts());
    stack.archController.registerBorrower(MatrixCaller);
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _deployBorrowCell(stack, i);
      MatrixOptions memory siblingOptions = _defaultMatrixOptions(
        cell.options.hooksKind,
        cell.options.marketKind
      );
      siblingOptions.maxTotalSupply *= 2;
      MatrixCell memory sibling = _deployMatrixCell(
        stack,
        siblingOptions,
        MatrixBorrower,
        MatrixBorrower,
        uint96(210 + i),
        EmptyHooksConfig.setHooksAddress(address(cell.hooks)).setFlag(Bit_Enabled_Deposit)
      );
      BorrowAmountPolicy feature = BorrowAmountPolicy(address(cell.hooks));
      assertEq(
        _factoryFor(stack, cell.options.marketKind).getMarketsForHooksInstanceCount(
          address(cell.hooks)
        ),
        2,
        'shared instance'
      );
      assertEq(
        feature.maximumNormalizedBorrow(address(cell.market)),
        cell.options.maxTotalSupply,
        'first creation unchanged'
      );
      assertEq(
        feature.maximumNormalizedBorrow(address(sibling.market)),
        siblingOptions.maxTotalSupply,
        'second creation default'
      );
      MarketState memory state;
      vm.prank(MatrixCaller);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      IHooks(address(cell.hooks)).onBorrow(1, state, '');
      assertEq(
        feature.lastNormalizedBorrow(MatrixCaller),
        0,
        'unknown caller has no feature state'
      );
      vm.prank(MatrixAlice);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      feature.setBorrowAmountLimit(address(cell.market), 1);
      vm.prank(MatrixBorrower);
      vm.expectRevert(BaseHooks.NotHookedMarket.selector);
      feature.setBorrowAmountLimit(MatrixCaller, 1);

      vm.expectEmit(true, false, false, true, address(feature));
      emit BorrowAmountPolicy.BorrowAmountLimitUpdated(address(cell.market), 100e18);
      vm.prank(MatrixBorrower);
      feature.setBorrowAmountLimit(address(cell.market), 100e18);
      vm.prank(MatrixBorrower);
      feature.setBorrowAmountLimit(address(sibling.market), 50e18);
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _deposit(stack, sibling, MatrixAlice, AliceDeposit);
      _assertRecordedBorrow(stack, cell, 100e18);
      assertEq(feature.lastNormalizedBorrow(address(sibling.market)), 0, 'first borrow isolated');
      vm.prank(MatrixBorrower);
      vm.expectRevert(BorrowAmountPolicy.BorrowAmountLimitExceeded.selector);
      sibling.market.borrow(100e18);
      _assertRecordedBorrow(stack, sibling, 50e18);
      assertEq(
        feature.lastNormalizedBorrow(address(cell.market)),
        100e18,
        'second borrow isolated'
      );

      vm.prank(MatrixBorrower);
      cell.hooks.requestAdministratorTransfer(MatrixCaller);
      vm.prank(MatrixCaller);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      feature.setBorrowAmountLimit(address(cell.market), 0);
      vm.prank(MatrixCaller);
      cell.hooks.acceptAdministratorTransfer();
      vm.prank(MatrixBorrower);
      vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
      feature.setBorrowAmountLimit(address(cell.market), 0);
      vm.prank(MatrixCaller);
      feature.setBorrowAmountLimit(address(cell.market), 0);
      vm.prank(MatrixBorrower);
      vm.expectRevert(BorrowAmountPolicy.BorrowAmountLimitExceeded.selector);
      cell.market.borrow(1);
      assertEq(
        feature.maximumNormalizedBorrow(address(sibling.market)),
        50e18,
        'sibling limit retained'
      );
      assertEq(
        feature.lastNormalizedBorrow(address(cell.market)),
        100e18,
        'accepted amount survives authority transfer'
      );
      _assertRecordedBorrow(stack, sibling, 25e18);
    }
  }

  function test_fourPolicyBorrowRollbackAndCoreGuardsAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack(_borrowArtifacts());
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _deployBorrowCell(stack, i);
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _assertRecordedBorrow(stack, cell, 25e18);
      vm.warp(vm.getBlockTimestamp() + 1 days);
      _assertBorrowTransferRollback(stack, cell);

      BorrowAmountPolicy feature = BorrowAmountPolicy(address(cell.hooks));
      vm.prank(MatrixBorrower);
      feature.setBorrowAmountLimit(address(cell.market), 0);
      uint256 tooMuch = cell.market.borrowableAssets() + 1;
      vm.prank(MatrixBorrower);
      vm.expectRevert(IMarketEventsAndErrors.BorrowAmountTooHigh.selector);
      cell.market.borrow(tooMuch);
      _approveBorrower(stack, cell, cell.options.maxTotalSupply);
      _close(cell);
      vm.prank(MatrixBorrower);
      vm.expectRevert(IMarketEventsAndErrors.BorrowFromClosedMarket.selector);
      cell.market.borrow(1);
      assertEq(
        feature.lastNormalizedBorrow(address(cell.market)),
        100e18,
        'core rejection leaves feature state'
      );
    }
  }

  function _assertBorrowTransferRollback(
    ProductionStack memory stack,
    MatrixCell memory cell
  ) private {
    uint256 amount = 100e18;
    bytes32 previousState = keccak256(abi.encode(cell.market.previousState()));
    uint256 marketAssets = stack.asset.balanceOf(address(cell.market));
    uint256 borrowerAssets = stack.asset.balanceOf(MatrixBorrower);
    uint256 drawn;
    if (cell.options.marketKind == MatrixMarketKind.Revolving) {
      drawn = IWildcatMarketRevolving(address(cell.market)).drawnAmount();
    }
    vm.mockCall(
      address(stack.asset),
      abi.encodeWithSelector(stack.asset.transfer.selector, MatrixBorrower, amount),
      abi.encode(false)
    );
    vm.expectCall(
      address(cell.hooks),
      abi.encodeCall(IHooks.onBorrow, (amount, cell.market.currentState(), bytes('')))
    );
    vm.prank(MatrixBorrower);
    vm.expectRevert(LibERC20.TransferFailed.selector);
    cell.market.borrow(amount);
    assertEq(
      BorrowAmountPolicy(address(cell.hooks)).lastNormalizedBorrow(address(cell.market)),
      25e18,
      'downstream failure restores accepted amount'
    );
    assertEq(
      keccak256(abi.encode(cell.market.previousState())),
      previousState,
      'downstream failure restores market state'
    );
    assertEq(
      stack.asset.balanceOf(address(cell.market)),
      marketAssets,
      'downstream failure restores market assets'
    );
    assertEq(
      stack.asset.balanceOf(MatrixBorrower),
      borrowerAssets,
      'downstream failure restores borrower assets'
    );
    if (cell.options.marketKind == MatrixMarketKind.Revolving) {
      assertEq(
        IWildcatMarketRevolving(address(cell.market)).drawnAmount(),
        drawn,
        'downstream failure restores principal'
      );
    }
    vm.clearMockedCalls();
    _assertRecordedBorrow(stack, cell, amount);
  }

  function test_lensDecodesFactoryMarketConfigurationAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack();
    MarketLensCore lens = MarketLensCore(
      _deployCode(
        'src/lens/MarketLensCore.sol:MarketLensCore',
        abi.encode(address(stack.archController), address(stack.standardFactory))
      )
    );
    address[] memory markets = new address[](12);
    MarketHooksData[] memory expectedConfigs = new MarketHooksData[](12);
    for (uint256 i; i < 12; i++) {
      bool gated = i >= 6;
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind(i % 3),
        MatrixMarketKind((i % 6) / 3)
      );
      options.minimumDeposit = uint128((1_111 + i) * 1e18);
      options.transfersDisabled = !gated;
      options.fixedTermDuration = 62 days;
      options.firstWindowDelay = 31 days;
      options.periodDuration = 34 days;
      options.withdrawalWindowDuration = 4 days;
      IHooksFactory factory = _factoryFor(stack, options.marketKind);
      vm.prank(MatrixBorrower);
      address hooks = factory.deployHooksInstance(stack.hooksTemplates[i % 3], '');
      HooksConfig requested = EmptyHooksConfig.setHooksAddress(hooks);
      if (gated) {
        requested = requested.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_QueueWithdrawal
        );
      }
      bytes memory hooksData = _hooksData(options, vm.getBlockTimestamp());
      if (options.hooksKind == MatrixHooksKind.FixedTerm) {
        hooksData = abi.encode(
          uint32(vm.getBlockTimestamp() + options.fixedTermDuration),
          options.minimumDeposit,
          options.transfersDisabled,
          gated,
          !gated
        );
      }
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(400 + i),
        requested,
        hooksData
      );

      // minimumDeposit and transfersDisabled force dispatch without requiring credentials.
      // fixed/periodic queue dispatch is mandatory, even when withdrawalRequiresAccess is false.
      MarketHooksData memory expected;
      expected.hooksAddress = hooks;
      expected.kind = HooksInstanceKind(1 + (i % 3));
      expected.flags.useOnDeposit = true;
      expected.flags.useOnTransfer = true;
      expected.flags.useOnQueueWithdrawal = gated || options.hooksKind != MatrixHooksKind.OpenTerm;
      expected.flags.useOnCloseMarket = options.hooksKind != MatrixHooksKind.OpenTerm;
      expected.flags.useOnSetAnnualInterestAndReserveRatioBips = true;
      expected.flags.useOnExecutePendingAnnualInterestBipsReduction =
        options.hooksKind == MatrixHooksKind.PeriodicTerm;
      expected.depositRequiresAccess = gated;
      expected.transferRequiresAccess = gated;
      expected.withdrawalRequiresAccess = gated;
      expected.minimumDeposit = options.minimumDeposit;
      expected.transfersDisabled = !gated;
      if (options.hooksKind == MatrixHooksKind.FixedTerm) {
        expected.fixedTermEndTime = uint32(cell.deployedAt + 62 days);
        expected.allowClosureBeforeTerm = gated;
        expected.allowTermReduction = !gated;
      } else if (options.hooksKind == MatrixHooksKind.PeriodicTerm) {
        expected.firstWithdrawalWindowStart = uint32(cell.deployedAt + 31 days);
        expected.periodDuration = 34 days;
        expected.withdrawalWindowDuration = 4 days;
        assertEq(PeriodicTermHooks(hooks).templateVersion(), 2, 'periodic ABI revision');
      }
      MarketDataV2_5 memory data = lens.getMarketDataV2(address(cell.market));
      assertEq(abi.encode(data.market.hooksConfig), abi.encode(expected), 'complete hook tuple');
      assertEq(data.market.hooksFactory, address(factory), 'actual market factory');
      assertEq(data.market.hooks.hooksTemplate.hooksTemplate, cell.hooksTemplate, 'template');
      assertEq(data.market.borrower, MatrixBorrower, 'operational borrower');
      assertEq(data.borrowerPrincipal, MatrixBorrower, 'principal');
      assertEq(data.borrowerIdentityRegistry, address(stack.registry), 'identity registry');
      bool revolving = options.marketKind == MatrixMarketKind.Revolving;
      assertEq(data.commitmentFeeBips.isPresent, revolving, 'commitment fee presence');
      assertEq(data.commitmentFeeBips.value, revolving ? 200 : 0, 'commitment fee');
      assertEq(data.drawnAmount.isPresent, revolving, 'drawn amount presence');
      assertEq(data.drawnAmount.value, 0, 'initial drawn amount');
      if (options.hooksKind == MatrixHooksKind.PeriodicTerm) {
        _close(cell);
        data = lens.getMarketDataV2(address(cell.market));
        expected.periodicTermClosed = true;
        assertTrue(data.market.isClosed, 'core closure');
        assertEq(abi.encode(data.market.hooksConfig), abi.encode(expected), 'closed hook tuple');
      }
      // reverse the request order so a factory-order response cannot accidentally pass.
      markets[11 - i] = address(cell.market);
      expectedConfigs[11 - i] = expected;
    }
    MarketDataV2_5[] memory batch = lens.getMarketsDataV2(markets);
    assertEq(batch.length, 12, 'batch length');
    for (uint256 i; i < batch.length; i++) {
      assertEq(batch[i].market.marketToken.token, markets[i], 'batch market order');
      assertEq(
        abi.encode(batch[i].market.hooksConfig),
        abi.encode(expectedConfigs[i]),
        'batch tuple'
      );
    }
  }

  function _assertDiscoveredHooks(
    HooksInstanceData memory actual,
    ProductionStack memory stack,
    MatrixCell memory cell,
    address pullProvider,
    address administrator,
    address pendingAdministrator
  ) private pure {
    HooksInstanceData memory expected;
    expected.hooksAddress = address(cell.hooks);
    expected.administrator = administrator;
    expected.pendingAdministrator = pendingAdministrator;
    expected.name = 'Factory matrix';
    expected.kind = HooksInstanceKind(1 + uint256(cell.options.hooksKind));
    expected.hooksTemplate.hooksTemplate = cell.hooksTemplate;
    expected.hooksTemplate.exists = true;
    expected.hooksTemplate.enabled = true;
    expected.hooksTemplate.index = uint24(uint256(cell.options.hooksKind));
    expected.hooksTemplate.name = cell.options.hooksKind == MatrixHooksKind.OpenTerm
      ? 'Open Term'
      : cell.options.hooksKind == MatrixHooksKind.FixedTerm
      ? 'Fixed Term'
      : 'Periodic Term';
    expected.hooksTemplate.totalMarkets = 1;
    expected.totalMarkets = 1;
    expected.constraints = MarketParameterConstraints(
      0,
      90 days,
      0,
      10_000,
      0,
      10_000,
      0,
      365 days,
      0,
      10_000,
      90 days,
      cell.options.hooksKind == MatrixHooksKind.FixedTerm ? type(uint32).max : uint32(730 days)
    );
    expected.deploymentFlags.optional.useOnDeposit = true;
    expected.deploymentFlags.optional.useOnTransfer = true;
    expected.deploymentFlags.optional.useOnQueueWithdrawal =
      cell.options.hooksKind == MatrixHooksKind.OpenTerm;
    expected.deploymentFlags.required.useOnQueueWithdrawal =
      cell.options.hooksKind != MatrixHooksKind.OpenTerm;
    expected.deploymentFlags.required.useOnCloseMarket =
      cell.options.hooksKind != MatrixHooksKind.OpenTerm;
    expected.deploymentFlags.required.useOnSetAnnualInterestAndReserveRatioBips = true;
    expected.deploymentFlags.required.useOnExecutePendingAnnualInterestBipsReduction =
      cell.options.hooksKind == MatrixHooksKind.PeriodicTerm;
    expected.pushProviders = new RoleProviderData[](1);
    expected.pushProviders[0] = RoleProviderData(
      type(uint32).max,
      address(stack.roleProvider),
      type(uint24).max,
      0,
      false,
      address(0),
      address(0)
    );
    expected.pullProviders = new RoleProviderData[](1);
    expected.pullProviders[0] = RoleProviderData(
      777,
      pullProvider,
      0,
      type(uint24).max,
      false,
      address(0),
      address(0)
    );
    assertEq(abi.encode(actual), abi.encode(expected), 'complete discovered instance');
  }

  function test_lensTracksFactoryInstancesThroughAdministratorTransfer() external {
    ProductionStack memory stack = _deployProductionStack();
    stack.archController.registerBorrower(MatrixAlice);
    MarketLensAggregator lens = MarketLensAggregator(
      _deployCode(
        'src/lens/MarketLensAggregator.sol:MarketLensAggregator',
        abi.encode(address(stack.archController), address(stack.standardFactory))
      )
    );
    MarketLensCore core = MarketLensCore(
      _deployCode(
        'src/lens/MarketLensCore.sol:MarketLensCore',
        abi.encode(address(stack.archController), address(stack.standardFactory))
      )
    );
    MockRoleProvider pullProvider = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    pullProvider.setIsPullProvider(true);
    MatrixCell[6] memory cells;
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        _defaultMatrixOptions(MatrixHooksKind(i % 3), MatrixMarketKind(i / 3)),
        MatrixBorrower,
        MatrixBorrower,
        uint96(420 + i)
      );
      cells[i] = cell;
      IHooksFactory factory = _factoryFor(stack, cell.options.marketKind);
      vm.startPrank(MatrixBorrower);
      cell.hooks.setName('Factory matrix');
      cell.hooks.addRoleProvider(address(pullProvider), 777);
      vm.stopPrank();
      HooksInstanceData[] memory found = lens.getHooksInstancesForBorrower(
        address(factory),
        MatrixBorrower
      );
      assertEq(found.length, 1, 'current administrator index');
      _assertDiscoveredHooks(
        found[0],
        stack,
        cell,
        address(pullProvider),
        MatrixBorrower,
        address(0)
      );
      vm.prank(MatrixBorrower);
      cell.hooks.requestAdministratorTransfer(MatrixAlice);
      found = lens.getHooksInstancesForBorrower(address(factory), MatrixBorrower);
      assertEq(found.length, 1, 'pending transfer keeps old index');
      _assertDiscoveredHooks(
        found[0],
        stack,
        cell,
        address(pullProvider),
        MatrixBorrower,
        MatrixAlice
      );
      assertEq(
        lens.getHooksInstancesForBorrower(address(factory), MatrixAlice).length,
        i % 3,
        'pending index excludes instance'
      );
      vm.prank(MatrixAlice);
      cell.hooks.acceptAdministratorTransfer();
      assertEq(
        lens.getHooksInstancesForBorrower(address(factory), MatrixBorrower).length,
        0,
        'old index cleared'
      );
      found = lens.getHooksInstancesForBorrower(address(factory), MatrixAlice);
      assertEq(found.length, 1 + (i % 3), 'new administrator index');
      _assertDiscoveredHooks(
        found[i % 3],
        stack,
        cell,
        address(pullProvider),
        MatrixAlice,
        address(0)
      );
      MarketDataV2_5 memory data = core.getMarketDataV2(address(cell.market));
      _assertDiscoveredHooks(
        data.market.hooks,
        stack,
        cell,
        address(pullProvider),
        MatrixAlice,
        address(0)
      );
      assertEq(data.market.borrower, MatrixBorrower, 'hook transfer preserves market borrower');
      assertEq(data.borrowerPrincipal, MatrixBorrower, 'hook transfer preserves market principal');
      assertEq(data.market.hooksFactory, address(factory), 'hook transfer preserves factory');
    }
    HooksInstanceData[] memory aggregated = lens.getAggregatedHooksInstancesForBorrower(
      MatrixAlice
    );
    assertEq(aggregated.length, 6, 'both active factories');
    for (uint256 i; i < 6; i++) {
      _assertDiscoveredHooks(
        aggregated[i],
        stack,
        cells[i],
        address(pullProvider),
        MatrixAlice,
        address(0)
      );
    }
    assertEq(
      lens.getAggregatedHooksInstancesForBorrower(MatrixBorrower).length,
      0,
      'former administrator absent'
    );
  }

  function test_wrappersKeepAccessAndBackingAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        _defaultMatrixOptions(MatrixHooksKind(i % 3), MatrixMarketKind(i / 3)),
        MatrixBorrower,
        MatrixBorrower,
        uint96(430 + i)
      );
      Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
        stack.wrapperFactory.createWrapper(address(cell.market))
      );
      assertEq(cell.market.registeredWrapper(), address(wrapper), 'market wrapper registration');
      assertEq(
        stack.wrapperFactory.wrapperForMarket(address(cell.market)),
        address(wrapper),
        'wrapper factory registration'
      );
      assertEq(wrapper.asset(), address(cell.market), 'wrapper holds market tokens');
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      // the exact registered wrapper needs no credential, even with a local deposit block.
      vm.prank(MatrixBorrower);
      cell.hooks.blockFromDeposits(address(wrapper));
      assertTrue(
        BaseHooks(address(cell.hooks)).isMarketTransferRecipientAllowed(
          address(cell.market),
          address(wrapper)
        ),
        'registered wrapper exemption'
      );
      assertTrue(wrapper.maxDeposit(MatrixAlice) >= AliceDeposit, 'wrapper ready');
      vm.startPrank(MatrixAlice);
      cell.market.approve(address(wrapper), AliceDeposit);
      uint256 shares = wrapper.deposit(AliceDeposit, MatrixAlice);
      vm.stopPrank();
      assertEq(shares, AliceDeposit, 'initial scale shares');
      assertEq(cell.market.scaledBalanceOf(address(wrapper)), shares, 'scaled backing');
      assertEq(wrapper.totalSupply(), shares, 'share supply');
      assertFalse(
        cell.hooks.isKnownLenderOnMarket(address(wrapper), address(cell.market)),
        'wrapper exemption does not mark known'
      );

      // redeeming sends market tokens. an uncredentialed recipient gets no wrapper exemption.
      assertFalse(
        BaseHooks(address(cell.hooks)).isMarketTransferRecipientAllowed(
          address(cell.market),
          MatrixBob
        ),
        'unknown recipient denied'
      );
      vm.prank(MatrixAlice);
      vm.expectRevert(LibERC20.TransferFailed.selector);
      wrapper.redeem(shares, MatrixBob, MatrixAlice);
      assertEq(wrapper.balanceOf(MatrixAlice), shares, 'rejected redeem restores shares');
      assertEq(wrapper.totalSupply(), shares, 'rejected redeem restores supply');
      assertEq(
        cell.market.scaledBalanceOf(address(wrapper)),
        shares,
        'rejected redeem keeps backing'
      );
      assertEq(cell.market.scaledBalanceOf(MatrixBob), 0, 'rejected recipient balance');

      _authorize(stack, cell, MatrixBob);
      _deposit(stack, cell, MatrixBob, 1e18);
      vm.prank(MatrixBorrower);
      cell.hooks.blockFromDeposits(MatrixBob);
      assertTrue(
        BaseHooks(address(cell.hooks)).isMarketTransferRecipientAllowed(
          address(cell.market),
          MatrixBob
        ),
        'known recipient survives local block'
      );
      vm.prank(MatrixAlice);
      uint256 assets = wrapper.redeem(shares, MatrixBob, MatrixAlice);
      assertEq(assets, AliceDeposit, 'redeemed market tokens');
      assertEq(wrapper.balanceOf(MatrixAlice), 0, 'shares burned');
      assertEq(wrapper.totalSupply(), 0, 'share supply cleared');
      assertEq(cell.market.scaledBalanceOf(address(wrapper)), 0, 'backing returned');
      assertEq(
        cell.market.scaledBalanceOf(MatrixBob),
        AliceDeposit + 1e18,
        'known recipient balance'
      );
    }
  }

  function test_productionFactoriesDeployCompleteBuiltInMatrix() external {
    ProductionStack memory stack = _deployProductionStack();

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      for (uint256 hooksKind; hooksKind < 3; hooksKind++) {
        MatrixOptions memory options = _defaultMatrixOptions(
          MatrixHooksKind(hooksKind),
          MatrixMarketKind(marketKind)
        );
        MatrixCell memory cell = _deployMatrixCell(
          stack,
          options,
          MatrixBorrower,
          MatrixBorrower,
          uint96(hooksKind + 1)
        );
        IHooksFactory factory = _factoryFor(stack, options.marketKind);
        IHooks hooks = IHooks(address(cell.hooks));

        assertEq(cell.market.factory(), address(factory), 'market factory');
        assertEq(cell.market.borrower(), MatrixBorrower, 'operational borrower');
        assertEq(cell.market.borrowerPrincipal(), MatrixBorrower, 'borrower principal');
        assertEq(hooks.factory(), address(factory), 'hooks factory');
        assertEq(cell.hooks.administrator(), MatrixBorrower, 'hooks administrator');
        assertEq(hooks.version(), _templateVersion(options.hooksKind), 'hooks version');
        assertEq(
          factory.getHooksTemplateForInstance(address(cell.hooks)),
          cell.hooksTemplate,
          'instance template'
        );
        assertEq(factory.getMarketsForHooksInstanceCount(address(cell.hooks)), 1, 'market count');
        assertEq(
          factory.getMarketsForHooksInstance(address(cell.hooks))[0],
          address(cell.market),
          'instance market'
        );
        assertTrue(stack.archController.isRegisteredMarket(address(cell.market)), 'registered');
        assertEq(
          HooksConfig.unwrap(cell.market.hooks()),
          HooksConfig.unwrap(
            hooks.config().optionalFlags().setHooksAddress(address(cell.hooks)).mergeAllFlags(
              hooks.config().requiredFlags()
            )
          ),
          'market hooks'
        );

        if (options.marketKind == MatrixMarketKind.Revolving) {
          assertEq(
            IWildcatMarketRevolving(address(cell.market)).commitmentFeeBips(),
            options.commitmentFeeBips,
            'commitment fee'
          );
        }

        _authorize(stack, cell, MatrixAlice);
        _deposit(stack, cell, MatrixAlice, 1e18);
        assertEq(cell.market.balanceOf(MatrixAlice), 1e18, 'matrix deposit');
      }
    }
  }

  function test_deterministicLifecycleRunsAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack();

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      for (uint256 hooksKind; hooksKind < 3; hooksKind++) {
        _runLifecycle(
          stack,
          _defaultMatrixOptions(MatrixHooksKind(hooksKind), MatrixMarketKind(marketKind)),
          uint96(10 + hooksKind)
        );
      }
    }
  }

  function _runLifecycle(
    ProductionStack memory stack,
    MatrixOptions memory options,
    uint96 nonce
  ) private {
    uint256 aliceStartingAssets = stack.asset.balanceOf(MatrixAlice);
    uint256 bobStartingAssets = stack.asset.balanceOf(MatrixBob);
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    _authorize(stack, cell, MatrixAlice);
    _authorize(stack, cell, MatrixBob);
    _deposit(stack, cell, MatrixAlice, AliceDeposit);
    _deposit(stack, cell, MatrixBob, BobDeposit);
    _approveBorrower(stack, cell, options.maxTotalSupply);

    assertEq(cell.market.balanceOf(MatrixAlice), AliceDeposit, 'alice deposit');
    assertEq(cell.market.balanceOf(MatrixBob), BobDeposit, 'bob deposit');
    assertEq(cell.market.totalSupply(), AliceDeposit + BobDeposit, 'matrix supply');

    uint256 draw = cell.market.borrowableAssets() / 2;
    uint256 borrowerBalanceBefore = stack.asset.balanceOf(MatrixBorrower);
    _borrow(cell, draw);
    assertEq(
      stack.asset.balanceOf(MatrixBorrower) - borrowerBalanceBefore,
      draw,
      'borrow transfer'
    );

    _accrueAndCheck(cell, 10 days);
    _accrueAndCheck(cell, 11 days);
    _repay(cell, draw / 2);
    _accrueAndCheck(cell, 9 days);

    _warpToWithdrawalAccess(cell);
    _repay(cell, draw - draw / 2);
    uint256 aliceWithdrawal = cell.market.balanceOf(MatrixAlice) / 2;
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueWithdrawal(aliceWithdrawal);
    vm.warp(uint256(expiry) + 1);
    cell.market.updateState();
    uint256 aliceBalanceBefore = stack.asset.balanceOf(MatrixAlice);
    uint256 withdrawn = cell.market.executeWithdrawal(MatrixAlice, expiry);
    assertEq(
      stack.asset.balanceOf(MatrixAlice) - aliceBalanceBefore,
      withdrawn,
      'first withdrawal'
    );
    assertTrue(withdrawn + MatrixDust >= aliceWithdrawal, 'first withdrawal underpaid');

    _accrueAndCheck(cell, 5 days);
    _close(cell);
    assertTrue(cell.market.isClosed(), 'market close');

    address[2] memory lenders = [MatrixAlice, MatrixBob];
    uint32[2] memory finalExpiries;
    for (uint256 i; i < lenders.length; i++) {
      if (cell.market.balanceOf(lenders[i]) > 0) {
        vm.prank(lenders[i]);
        finalExpiries[i] = cell.market.queueFullWithdrawal();
      }
    }
    vm.warp(vm.getBlockTimestamp() + 1);
    cell.market.updateState();
    for (uint256 i; i < lenders.length; i++) {
      if (finalExpiries[i] != 0) {
        cell.market.executeWithdrawal(lenders[i], finalExpiries[i]);
      }
    }

    MarketState memory state = cell.market.previousState();
    assertEq(state.scaledTotalSupply, 0, 'final scaled supply');
    assertEq(state.scaledPendingWithdrawals, 0, 'final pending withdrawals');
    assertEq(cell.market.getUnpaidBatchExpiries().length, 0, 'final unpaid batches');
    assertTrue(
      stack.asset.balanceOf(MatrixAlice) - aliceStartingAssets > AliceDeposit,
      'alice yield'
    );
    assertTrue(stack.asset.balanceOf(MatrixBob) - bobStartingAssets > BobDeposit, 'bob yield');
    assertTrue(
      stack.asset.balanceOf(address(cell.market)) <= MatrixDust,
      'assets stranded in market'
    );
  }

  function test_withdrawalGatesHoldAtExactProductionMatrixBoundaries() external {
    ProductionStack memory stack = _deployProductionStack();

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      _assertFixedTermGate(stack, MatrixMarketKind(marketKind), uint96(30 + marketKind));
      _assertPeriodicTermGate(stack, MatrixMarketKind(marketKind), uint96(40 + marketKind));
    }
  }

  function test_periodicAprReductionExecutesAcrossProductionMarkets() external {
    ProductionStack memory stack = _deployProductionStack();

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind.PeriodicTerm,
        MatrixMarketKind(marketKind)
      );
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(50 + marketKind)
      );
      PeriodicTermHooks hooks = PeriodicTermHooks(address(cell.hooks));
      _authorize(stack, cell, MatrixAlice);
      _authorize(stack, cell, MatrixBob);
      _deposit(stack, cell, MatrixAlice, AliceDeposit);
      _deposit(stack, cell, MatrixBob, BobDeposit);

      vm.warp(cell.deployedAt + 10 days);
      vm.prank(MatrixBorrower);
      hooks.proposeAnnualInterestBips(address(cell.market), 800);
      (PendingAprChange memory pending, uint32 responseStart, uint32 responseEnd) = hooks
        .getPendingAprChange(address(cell.market));
      assertEq(pending.annualInterestBips, 800, 'pending APR');
      assertEq(responseStart, cell.deployedAt + options.firstWindowDelay, 'response start');
      assertEq(
        responseEnd,
        cell.deployedAt + options.firstWindowDelay + options.withdrawalWindowDuration,
        'response end'
      );

      vm.prank(MatrixCaller);
      vm.expectRevert(PeriodicTermPolicy.AprChangeNotReady.selector);
      cell.market.executePendingAnnualInterestBipsReduction();

      vm.warp(responseStart);
      vm.prank(MatrixAlice);
      uint32 expiry = cell.market.queueWithdrawal(AliceDeposit / 4);
      vm.warp(uint256(expiry) + 1);
      cell.market.updateState();
      cell.market.executeWithdrawal(MatrixAlice, expiry);

      vm.warp(responseEnd);
      vm.prank(MatrixCaller);
      cell.market.executePendingAnnualInterestBipsReduction();
      assertEq(cell.market.annualInterestBips(), 800, 'executed APR');
      (pending, , ) = hooks.getPendingAprChange(address(cell.market));
      assertEq(pending.proposalTimestamp, 0, 'proposal cleared');
    }
  }

  function test_periodicAprExpiryAndCancellationUseProductionMarketState() external {
    ProductionStack memory stack = _deployProductionStack();
    MatrixOptions memory options = _defaultMatrixOptions(
      MatrixHooksKind.PeriodicTerm,
      MatrixMarketKind.Standard
    );

    MatrixCell memory expired = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      60
    );
    PeriodicTermHooks expiredHooks = PeriodicTermHooks(address(expired.hooks));
    vm.warp(expired.deployedAt + 10 days);
    vm.prank(MatrixBorrower);
    expiredHooks.proposeAnnualInterestBips(address(expired.market), 800);
    (, uint32 responseStart, ) = expiredHooks.getPendingAprChange(address(expired.market));
    vm.warp(
      uint256(responseStart) +
        options.periodDuration *
        expiredHooks.AprReductionProposalValidityPeriods()
    );
    vm.expectRevert(PeriodicTermPolicy.AprReductionProposalExpired.selector);
    expired.market.executePendingAnnualInterestBipsReduction();
    assertEq(expired.market.annualInterestBips(), options.annualInterestBips, 'expired APR');

    MatrixCell memory increased = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      61
    );
    PeriodicTermHooks increasedHooks = PeriodicTermHooks(address(increased.hooks));
    vm.warp(increased.deployedAt + 10 days);
    vm.prank(MatrixBorrower);
    increasedHooks.proposeAnnualInterestBips(address(increased.market), 800);
    vm.prank(MatrixBorrower);
    increased.market.setAnnualInterestAndReserveRatioBips(
      options.annualInterestBips + 100,
      options.reserveRatioBips
    );
    (PendingAprChange memory pending, , ) = increasedHooks.getPendingAprChange(
      address(increased.market)
    );
    assertEq(pending.proposalTimestamp, 0, 'increase cancellation');
    vm.expectRevert(PeriodicTermPolicy.NoPendingAprChange.selector);
    increased.market.executePendingAnnualInterestBipsReduction();

    MatrixCell memory closed = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      62
    );
    PeriodicTermHooks closedHooks = PeriodicTermHooks(address(closed.hooks));
    vm.warp(closed.deployedAt + 10 days);
    vm.prank(MatrixBorrower);
    closedHooks.proposeAnnualInterestBips(address(closed.market), 800);
    _close(closed);
    (pending, , ) = closedHooks.getPendingAprChange(address(closed.market));
    assertEq(pending.proposalTimestamp, 0, 'close cancellation');
  }

  function test_minimumDepositOrderingAndLiveUpdatesUseProductionComposition() external {
    ProductionStack memory stack = _deployProductionStack();
    MatrixOptions memory capacityOptions = _defaultMatrixOptions(
      MatrixHooksKind.OpenTerm,
      MatrixMarketKind.Standard
    );
    capacityOptions.minimumDeposit = MinimumDeposit;
    capacityOptions.maxTotalSupply = 3 * MinimumDeposit - 1;
    MatrixCell memory capacity = _deployMatrixCell(
      stack,
      capacityOptions,
      MatrixBorrower,
      MatrixBorrower,
      70
    );
    _authorize(stack, capacity, MatrixAlice);
    _authorize(stack, capacity, MatrixBob);
    _deposit(stack, capacity, MatrixAlice, MinimumDeposit);
    _deposit(stack, capacity, MatrixBob, MinimumDeposit);
    stack.asset.mint(MatrixAlice, MinimumDeposit);

    vm.prank(MatrixAlice);
    vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
    capacity.market.depositUpTo(MinimumDeposit);
    vm.prank(MatrixAlice);
    vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
    capacity.market.deposit(MinimumDeposit);

    MatrixOptions memory liveOptions = _defaultMatrixOptions(
      MatrixHooksKind.PeriodicTerm,
      MatrixMarketKind.Standard
    );
    liveOptions.minimumDeposit = MinimumDeposit;
    MatrixCell memory live = _deployMatrixCell(
      stack,
      liveOptions,
      MatrixBorrower,
      MatrixBorrower,
      71
    );
    _authorize(stack, live, MatrixAlice);
    _authorize(stack, live, MatrixBob);
    _deposit(stack, live, MatrixAlice, MinimumDeposit);
    PeriodicTermHooks liveHooks = PeriodicTermHooks(address(live.hooks));

    vm.prank(MatrixBorrower);
    liveHooks.setMinimumDeposit(address(live.market), MinimumDeposit * 2);
    _fundAndApprove(stack, live, MatrixBob, MinimumDeposit * 2);
    vm.prank(MatrixBob);
    vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
    live.market.depositUpTo(MinimumDeposit);
    vm.prank(MatrixBob);
    live.market.depositUpTo(MinimumDeposit * 2);

    vm.prank(MatrixBorrower);
    liveHooks.setMinimumDeposit(address(live.market), 0);
    _deposit(stack, live, MatrixAlice, 1e18);
    assertEq(live.market.balanceOf(MatrixAlice), MinimumDeposit + 1e18, 'cleared minimum');

    vm.prank(MatrixAlice);
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    liveHooks.setMinimumDeposit(address(live.market), 1);
  }

  function test_exactMinimumBoundarySurvivesAccruedScaleAcrossProductionHooks() external {
    ProductionStack memory stack = _deployProductionStack();
    uint128 exactMinimum = 100_000e18;

    for (uint256 hooksKind; hooksKind < 3; hooksKind++) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind(hooksKind),
        MatrixMarketKind.Standard
      );
      options.minimumDeposit = exactMinimum;
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(80 + hooksKind)
      );
      _authorize(stack, cell, MatrixAlice);
      _authorize(stack, cell, MatrixBob);
      _deposit(stack, cell, MatrixBob, 500_000e18);
      _approveBorrower(stack, cell, options.maxTotalSupply);
      _borrow(cell, 300_000e18);
      vm.warp(cell.deployedAt + 120 days);
      cell.market.updateState();
      uint256 scaleFactor = cell.market.scaleFactor();
      assertTrue(scaleFactor > 1e27, 'accrued scale factor');

      _deposit(stack, cell, MatrixAlice, exactMinimum);
      assertTrue(cell.market.balanceOf(MatrixAlice) > 0, 'exact minimum');

      uint256 minimumScaled = (uint256(exactMinimum) * 1e27) / scaleFactor;
      uint256 boundary = (minimumScaled * scaleFactor + 1e27 - 1) / 1e27;
      stack.asset.mint(MatrixBob, boundary * 2);
      vm.prank(MatrixBob);
      cell.market.depositUpTo(boundary);
      vm.prank(MatrixBob);
      vm.expectRevert(BaseHooks.DepositBelowMinimum.selector);
      cell.market.depositUpTo(boundary - 1);
    }
  }

  function test_roundingStrandingWindowsCloseAndDrainThroughProductionFactory() external {
    ProductionStack memory stack = _deployProductionStack();
    MatrixOptions memory options = _defaultMatrixOptions(
      MatrixHooksKind.OpenTerm,
      MatrixMarketKind.Standard
    );
    options.reserveRatioBips = 0;

    MatrixCell memory pending = _deployRoundingCell(stack, options, 90);
    uint256 pendingFraction = (pending.market.scaledTotalSupply() * pending.market.scaleFactor()) %
      1e27;
    assertTrue(pendingFraction > 0, 'pending stranding fraction zero');
    assertTrue(pendingFraction < 0.5e27, 'pending stranding fraction high');
    vm.prank(MatrixAlice);
    pending.market.queueFullWithdrawal();
    _close(pending);
    MarketState memory state = pending.market.previousState();
    assertEq(state.scaledPendingWithdrawals, 0, 'pending close stranding');
    assertEq(pending.market.getUnpaidBatchExpiries().length, 0, 'pending close unpaid');

    MatrixCell memory closed = _deployRoundingCell(stack, options, 91);
    _close(closed);
    uint256 closedFraction = (closed.market.scaledTotalSupply() * closed.market.scaleFactor()) %
      1e27;
    assertTrue(closedFraction > 0, 'closed stranding fraction zero');
    assertTrue(closedFraction < 0.5e27, 'closed stranding fraction high');
    vm.prank(MatrixAlice);
    uint32 expiry = closed.market.queueFullWithdrawal();
    vm.warp(vm.getBlockTimestamp() + 2);
    closed.market.updateState();
    assertEq(closed.market.getUnpaidBatchExpiries().length, 0, 'closed batch unpaid');
    uint256 assetsBefore = stack.asset.balanceOf(MatrixAlice);
    uint256 withdrawn = closed.market.executeWithdrawal(MatrixAlice, expiry);
    assertTrue(withdrawn > 0, 'closed withdrawal');
    assertEq(stack.asset.balanceOf(MatrixAlice) - assetsBefore, withdrawn, 'closed payout');
    assertEq(closed.market.balanceOf(MatrixAlice), 0, 'closed lender balance');
  }

  function _deployRoundingCell(
    ProductionStack memory stack,
    MatrixOptions memory options,
    uint96 nonce
  ) private returns (MatrixCell memory cell) {
    cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, nonce);
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 123_457e18);
    _approveBorrower(stack, cell, options.maxTotalSupply);
    _borrow(cell, 100_000e18);
    vm.warp(cell.deployedAt + 37 days);
    cell.market.updateState();
    uint256 debts = cell.market.totalDebts();
    uint256 held = stack.asset.balanceOf(address(cell.market));
    if (debts > held) _repay(cell, debts - held);
  }

  function test_directSanctionsFlowsComposeAcrossProductionMatrix() external {
    ProductionStack memory stack = _deployProductionStack();

    MatrixCell memory open = _deployMatrixCell(
      stack,
      _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard),
      MatrixBorrower,
      MatrixBorrower,
      100
    );
    _authorize(stack, open, MatrixAlice);
    _authorize(stack, open, MatrixBob);
    _deposit(stack, open, MatrixAlice, BobDeposit);
    _deposit(stack, open, MatrixBob, BobDeposit);
    stack.sanctionsList.sanction(MatrixBob);

    vm.prank(MatrixAlice);
    open.market.nukeFromOrbit(MatrixBob);
    assertEq(open.market.balanceOf(MatrixBob), 0, 'sanctioned balance queued');
    uint32 expiry = open.market.previousState().pendingWithdrawalExpiry;
    vm.warp(uint256(expiry) + 1);
    open.market.updateState();
    address escrow = stack.sentinel.getEscrowAddress(
      MatrixBorrower,
      MatrixBob,
      address(stack.asset)
    );
    uint256 bobAssetsBefore = stack.asset.balanceOf(MatrixBob);
    open.market.executeWithdrawal(MatrixBob, expiry);
    assertEq(stack.asset.balanceOf(MatrixBob), bobAssetsBefore, 'sanctioned direct payout');
    uint256 escrowedAssets = stack.asset.balanceOf(escrow);
    assertTrue(escrowedAssets >= BobDeposit, 'escrowed withdrawal');

    vm.prank(MatrixBorrower);
    stack.sentinel.overrideSanction(MatrixBob);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();
    assertEq(stack.asset.balanceOf(MatrixBob), bobAssetsBefore + escrowedAssets, 'escrow release');
    vm.prank(MatrixBorrower);
    stack.sentinel.removeSanctionOverride(MatrixBob);
    stack.sanctionsList.unsanction(MatrixBob);

    MatrixCell memory periodic = _deployMatrixCell(
      stack,
      _defaultMatrixOptions(MatrixHooksKind.PeriodicTerm, MatrixMarketKind.Standard),
      MatrixBorrower,
      MatrixBorrower,
      101
    );
    _authorize(stack, periodic, MatrixBob);
    _deposit(stack, periodic, MatrixBob, BobDeposit);
    stack.sanctionsList.sanction(MatrixBob);
    vm.prank(MatrixCaller);
    vm.expectRevert(PeriodicTermPolicy.WithdrawOutsideWindow.selector);
    periodic.market.nukeFromOrbit(MatrixBob);
    _warpToWithdrawalAccess(periodic);
    vm.prank(MatrixCaller);
    periodic.market.nukeFromOrbit(MatrixBob);
    assertEq(periodic.market.balanceOf(MatrixBob), 0, 'periodic sanction queue');
    stack.sanctionsList.unsanction(MatrixBob);

    MatrixCell memory revolving = _deployMatrixCell(
      stack,
      _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving),
      MatrixBorrower,
      MatrixBorrower,
      102
    );
    _authorize(stack, revolving, MatrixAlice);
    _authorize(stack, revolving, MatrixBob);
    _deposit(stack, revolving, MatrixAlice, BobDeposit);
    _deposit(stack, revolving, MatrixBob, BobDeposit);
    _approveBorrower(stack, revolving, revolving.options.maxTotalSupply);
    _borrow(revolving, 40_000e18);
    stack.sanctionsList.sanction(MatrixBob);
    uint256 drawnBefore = IWildcatMarketRevolving(address(revolving.market)).drawnAmount();
    vm.prank(MatrixCaller);
    revolving.market.nukeFromOrbit(MatrixBob);
    assertEq(
      IWildcatMarketRevolving(address(revolving.market)).drawnAmount(),
      drawnBefore,
      'sanction changed drawn principal'
    );
  }

  function _assertFixedTermGate(
    ProductionStack memory stack,
    MatrixMarketKind marketKind,
    uint96 nonce
  ) private {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.FixedTerm, marketKind);
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 10e18);

    vm.prank(MatrixAlice);
    vm.expectRevert(FixedTermPolicy.WithdrawBeforeTermEnd.selector);
    cell.market.queueFullWithdrawal();

    uint256 termEnd = cell.deployedAt + options.fixedTermDuration;
    vm.warp(termEnd - 1);
    vm.prank(MatrixAlice);
    vm.expectRevert(FixedTermPolicy.WithdrawBeforeTermEnd.selector);
    cell.market.queueFullWithdrawal();

    vm.warp(termEnd);
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueWithdrawal(1e18);
    assertTrue(expiry > termEnd, 'fixed-term boundary');
  }

  function _assertPeriodicTermGate(
    ProductionStack memory stack,
    MatrixMarketKind marketKind,
    uint96 nonce
  ) private {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.PeriodicTerm, marketKind);
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 10e18);
    PeriodicTermHooks hooks = PeriodicTermHooks(address(cell.hooks));

    assertFalse(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic pre-window');
    vm.prank(MatrixAlice);
    vm.expectRevert(PeriodicTermPolicy.WithdrawOutsideWindow.selector);
    cell.market.queueWithdrawal(1e18);

    uint256 windowStart = cell.deployedAt + options.firstWindowDelay;
    vm.warp(windowStart);
    assertTrue(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic window start');
    vm.prank(MatrixAlice);
    cell.market.queueWithdrawal(1e18);

    vm.warp(windowStart + options.withdrawalWindowDuration);
    assertFalse(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic window end');
    vm.prank(MatrixAlice);
    vm.expectRevert(PeriodicTermPolicy.WithdrawOutsideWindow.selector);
    cell.market.queueWithdrawal(1e18);

    vm.warp(windowStart + options.periodDuration);
    assertTrue(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic next window');
    vm.prank(MatrixAlice);
    cell.market.queueWithdrawal(1e18);
  }
}

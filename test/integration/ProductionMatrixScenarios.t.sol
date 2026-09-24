// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

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
import { LibERC20 } from 'src/libraries/LibERC20.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
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

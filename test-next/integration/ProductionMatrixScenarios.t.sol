// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooksFactory } from 'src/IHooksFactory.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

contract ProductionMatrixScenariosTest is ProductionMatrixFixture {
  uint256 internal constant AliceDeposit = 100_000e18;
  uint256 internal constant BobDeposit = 50_000e18;

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
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
    cell.market.queueFullWithdrawal();

    uint256 termEnd = cell.deployedAt + options.fixedTermDuration;
    vm.warp(termEnd - 1);
    vm.prank(MatrixAlice);
    vm.expectRevert(FixedTermHooks.WithdrawBeforeTermEnd.selector);
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
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    cell.market.queueWithdrawal(1e18);

    uint256 windowStart = cell.deployedAt + options.firstWindowDelay;
    vm.warp(windowStart);
    assertTrue(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic window start');
    vm.prank(MatrixAlice);
    cell.market.queueWithdrawal(1e18);

    vm.warp(windowStart + options.withdrawalWindowDuration);
    assertFalse(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic window end');
    vm.prank(MatrixAlice);
    vm.expectRevert(PeriodicTermHooks.WithdrawOutsideWindow.selector);
    cell.market.queueWithdrawal(1e18);

    vm.warp(windowStart + options.periodDuration);
    assertTrue(hooks.isWithdrawalWindowOpen(address(cell.market)), 'periodic next window');
    vm.prank(MatrixAlice);
    cell.market.queueWithdrawal(1e18);
  }
}

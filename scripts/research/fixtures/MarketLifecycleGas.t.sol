// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketGasBase } from './MarketGas.t.sol';

contract MarketLifecycleGasTest is MarketGasBase {
  function _lifecycle(MatrixMarketKind marketKind) internal {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, marketKind);
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 7 days);
    options.repaymentPeriod = 1 days;
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 0);
    string memory group = string.concat(_group(marketKind, options.hooksKind), '-repayment');
    _authorize(stack, cell, MatrixAlice);
    _fundAndApprove(stack, cell, MatrixAlice, 10_000e18);
    _approveBorrower(stack, cell, 10_000e18);

    vm.prank(MatrixAlice);
    cell.market.depositUpTo(1_000e18);
    _record(group, 'deposit-first');
    vm.prank(MatrixBorrower);
    cell.market.borrow(700e18);
    _record(group, 'borrow-first');
    vm.warp(cell.deployedAt + 1 days);
    cell.market.updateState();
    _record(group, 'update-before-date');
    vm.prank(MatrixBorrower);
    cell.market.repay(100e18);
    _record(group, 'repay-before-date');

    vm.warp(options.repaymentDate);
    cell.market.updateState();
    _record(group, 'activate-repayment');
    assertEq(cell.market.reserveRatioBips(), 10_000, 'repayment reserves');
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueWithdrawal(100e18);
    _record(group, 'queue-in-repayment');
    vm.warp(uint256(options.repaymentDate) + 1 hours);
    cell.market.updateState();
    _record(group, 'update-in-penalty');
    vm.prank(MatrixBorrower);
    cell.market.repay(100e18);
    _record(group, 'repay-partial-in-repayment');

    vm.warp(uint256(options.repaymentDate) + options.repaymentPeriod + 1);
    cell.market.updateState();
    _record(group, 'record-deadline-default-and-expiry');
    assertEq(cell.market.defaultedAt(), cell.market.repaymentDeadline(), 'default recorded');
    uint256 owed = cell.market.totalDebts() - cell.market.totalAssets();
    vm.prank(MatrixBorrower);
    cell.market.repay(owed);
    _record(group, 'repay-and-automatically-close');
    assertTrue(cell.market.isClosed(), 'automatic closure');
    cell.market.executeWithdrawal(MatrixAlice, expiry);
    _record(group, 'execute-after-automatic-closure');
    stack.asset.mint(address(cell.market), 1e18);
    vm.prank(MatrixBorrower);
    cell.market.rescueTokens(address(stack.asset));
    _record(group, 'recover-surplus');
    assertEq(cell.market.totalAssets(), cell.market.totalDebts(), 'claims protected');
    _recordState(group, cell);
  }

  function _penalty(MatrixMarketKind marketKind) internal {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, marketKind);
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 0);
    string memory group = string.concat(_group(marketKind, options.hooksKind), '-penalty');
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 1_000e18);
    _approveBorrower(stack, cell, 10_000e18);
    _borrow(cell, 700e18);
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueFullWithdrawal();
    vm.warp(uint256(expiry) + 1);
    cell.market.updateState();
    _record(group, 'expire-underfunded-batch');
    vm.warp(vm.getBlockTimestamp() + 2 days);
    cell.market.updateState();
    _record(group, 'update-in-penalty');
    uint256 owed = cell.market.totalDebts() - cell.market.totalAssets();
    vm.prank(MatrixBorrower);
    cell.market.repay(owed);
    _record(group, 'cure-penalty');
    assertEq(cell.market.defaultedAt(), 0, 'cure before default');
    _recordState(group, cell);
  }

  function test_gas_lifecycleStandard() external {
    _lifecycle(MatrixMarketKind.Standard);
  }

  function test_gas_lifecycleRevolving() external {
    _lifecycle(MatrixMarketKind.Revolving);
  }

  function test_gas_penaltyStandard() external {
    _penalty(MatrixMarketKind.Standard);
  }

  function test_gas_penaltyRevolving() external {
    _penalty(MatrixMarketKind.Revolving);
  }
}

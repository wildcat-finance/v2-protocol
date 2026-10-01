// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketGas.t
// ║  ██▀▀     ▀▀██   Production-matrix operation gas and state-fingerprint fixtures.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SNAPSHOT INTERFACE
// ║  snapshotGasLastFrame(...)
// ║  snapshotValue(...)
// ║
// ║  GAS FIXTURE
// ║  setUp()
// ║
// ║  OPERATION SEQUENCE
// ║  _common(...)
// ║
// ║  MEASUREMENT RECORDS
// ║  _record(...)
// ║  _recordState(...)
// ║  _group(...)
// ║
// ║  STANDARD MARKETS
// ║  test_gas_standardOpen()
// ║  test_gas_standardFixed()
// ║  test_gas_standardPeriodic()
// ║
// ║  REVOLVING MARKETS
// ║  test_gas_revolvingOpen()
// ║  test_gas_revolvingFixed()
// ║  test_gas_revolvingPeriodic()
// ╚═════

import { ProductionMatrixFixture } from 'test/shared/ProductionMatrixFixture.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';

// the pinned forge-std predates this Foundry 1.8.3 cheatcode.
// ┌─ GasSnapshotVm ────────────────────────────────────────────────────────────
interface GasSnapshotVm {
  // ░░▒▒▓▓██ [ SNAPSHOT INTERFACE ] ───────────────────────────────────────────

  // ┌─ snapshotGasLastFrame ─────
  function snapshotGasLastFrame(string calldata group, string calldata name) external returns (uint256);

  // ┌─ snapshotValue ─────
  function snapshotValue(string calldata group, string calldata name, uint256 value) external;
}

// ┌─ MarketGasBase ────────────────────────────────────────────────────────────
abstract contract MarketGasBase is ProductionMatrixFixture {
  ProductionStack internal stack;

  // ░░▒▒▓▓██ [ GAS FIXTURE ] ──────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    stack = _deployProductionStack();
  }

  // ░░▒▒▓▓██ [ OPERATION SEQUENCE ] ───────────────────────────────────────────

  // ┌─ _common ─────
  function _common(MatrixMarketKind marketKind, MatrixHooksKind hooksKind) internal {
    MatrixOptions memory options = _defaultMatrixOptions(hooksKind, marketKind);
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 0);
    string memory group = _group(marketKind, hooksKind);
    _authorize(stack, cell, MatrixAlice);
    _authorize(stack, cell, MatrixBob);
    _fundAndApprove(stack, cell, MatrixAlice, 10_000e18);
    _approveBorrower(stack, cell, 10_000e18);

    vm.prank(MatrixAlice);
    cell.market.depositUpTo(1_000e18);
    _record(group, 'deposit-first');
    assertEq(cell.market.balanceOf(MatrixAlice), 1_000e18, 'first deposit');

    vm.prank(MatrixAlice);
    cell.market.depositUpTo(100e18);
    _record(group, 'deposit-existing-same-timestamp');
    vm.warp(cell.deployedAt + 1 days);
    vm.prank(MatrixAlice);
    cell.market.depositUpTo(100e18);
    _record(group, 'deposit-existing-accrued');

    vm.prank(MatrixBorrower);
    cell.market.borrow(500e18);
    _record(group, 'borrow-first');
    vm.prank(MatrixBorrower);
    cell.market.borrow(100e18);
    _record(group, 'borrow-existing');
    vm.warp(cell.deployedAt + 2 days);
    vm.prank(MatrixBorrower);
    cell.market.repay(100e18);
    _record(group, 'repay-accrued');
    assertEq(stack.asset.balanceOf(address(cell.market)), 700e18, 'net assets');

    vm.prank(MatrixAlice);
    cell.market.transfer(MatrixBob, 10e18);
    _record(group, 'transfer-new-recipient');
    vm.prank(MatrixAlice);
    cell.market.transfer(MatrixBob, 10e18);
    _record(group, 'transfer-existing-recipient');
    vm.prank(MatrixBorrower);
    cell.market.setAnnualInterestAndReserveRatioBips(1_100, 2_000);
    _record(group, 'apr-increase');
    assertEq(cell.market.annualInterestBips(), 1_100, 'APR increased');

    cell.market.updateState();
    _record(group, 'update-same-timestamp');
    vm.warp(cell.deployedAt + 3 days);
    cell.market.updateState();
    _record(group, 'update-accrued');

    if (hooksKind == MatrixHooksKind.FixedTerm) {
      vm.warp(cell.deployedAt + options.fixedTermDuration);
    } else if (hooksKind == MatrixHooksKind.PeriodicTerm) {
      vm.warp(cell.deployedAt + options.firstWindowDelay);
    }
    vm.prank(MatrixAlice);
    uint32 expiry = cell.market.queueWithdrawal(100e18);
    _record(group, 'queue-new-batch');
    vm.prank(MatrixAlice);
    uint32 sameExpiry = cell.market.queueWithdrawal(50e18);
    _record(group, 'queue-existing-batch');
    assertEq(expiry, sameExpiry, 'same batch');
    vm.warp(uint256(expiry) + 1);
    cell.market.updateState();
    _record(group, 'update-batch-expiry');
    uint256 collectible = cell.market.getAvailableWithdrawalAmount(MatrixAlice, expiry);
    uint256 lenderAssets = stack.asset.balanceOf(MatrixAlice);
    cell.market.executeWithdrawal(MatrixAlice, expiry);
    _record(group, 'execute-withdrawal');
    assertTrue(collectible > 0, 'funded withdrawal');
    assertEq(stack.asset.balanceOf(MatrixAlice), lenderAssets + collectible, 'collected');

    if (hooksKind == MatrixHooksKind.PeriodicTerm) {
      PeriodicTermHooks hooks = PeriodicTermHooks(address(cell.hooks));
      vm.warp(cell.deployedAt + options.firstWindowDelay + options.withdrawalWindowDuration);
      vm.prank(MatrixBorrower);
      hooks.proposeAnnualInterestBips(address(cell.market), 800);
      _record(group, 'periodic-propose-apr');
      (,, uint32 responseEnd) = hooks.getPendingAprChange(address(cell.market));
      vm.warp(responseEnd);
      cell.market.executePendingAnnualInterestBipsReduction();
      _record(group, 'periodic-execute-apr');
      assertEq(cell.market.annualInterestBips(), 800, 'periodic APR applied');
    } else {
      vm.prank(MatrixBorrower);
      cell.market.setAnnualInterestAndReserveRatioBips(1_000, 2_000);
      _record(group, 'apr-reduction');
      assertEq(cell.market.annualInterestBips(), 1_000, 'APR reduced');
    }

    vm.prank(MatrixBorrower);
    cell.market.closeMarket();
    _record(group, 'manual-close');
    assertTrue(cell.market.isClosed(), 'closed');
    assertEq(cell.market.totalAssets(), cell.market.totalDebts(), 'all debt covered');
    _recordState(group, cell);
  }

  // ░░▒▒▓▓██ [ MEASUREMENT RECORDS ] ──────────────────────────────────────────

  // ┌─ _record ─────
  function _record(string memory group, string memory name) internal {
    // call immediately after the measured transaction, before assertions or other reads.
    GasSnapshotVm(VmAddress).snapshotGasLastFrame(group, name);
  }

  // ┌─ _recordState ─────
  function _recordState(string memory group, MatrixCell memory cell) internal {
    bytes32 fingerprint = keccak256(
      abi.encode(
        cell.market.previousState(),
        cell.market.totalAssets(),
        cell.market.balanceOf(MatrixAlice),
        cell.market.balanceOf(MatrixBob),
        stack.asset.balanceOf(MatrixAlice),
        stack.asset.balanceOf(MatrixBorrower)
      )
    );
    GasSnapshotVm(VmAddress).snapshotValue(group, 'state-fingerprint', uint256(fingerprint));
  }

  // ┌─ _group ─────
  function _group(MatrixMarketKind marketKind, MatrixHooksKind hooksKind) internal pure returns (string memory) {
    return string.concat(
      marketKind == MatrixMarketKind.Standard ? 'standard-' : 'revolving-',
      hooksKind == MatrixHooksKind.OpenTerm ? 'open' : hooksKind == MatrixHooksKind.FixedTerm ? 'fixed' : 'periodic'
    );
  }
}

// ┌─ MarketGasTest ────────────────────────────────────────────────────────────
contract MarketGasTest is MarketGasBase {
  // ░░▒▒▓▓██ [ STANDARD MARKETS ] ─────────────────────────────────────────────

  // ┌─ test_gas_standardOpen ─────
  function test_gas_standardOpen() external {
    _common(MatrixMarketKind.Standard, MatrixHooksKind.OpenTerm);
  }

  // ┌─ test_gas_standardFixed ─────
  function test_gas_standardFixed() external {
    _common(MatrixMarketKind.Standard, MatrixHooksKind.FixedTerm);
  }

  // ┌─ test_gas_standardPeriodic ─────
  function test_gas_standardPeriodic() external {
    _common(MatrixMarketKind.Standard, MatrixHooksKind.PeriodicTerm);
  }

  // ░░▒▒▓▓██ [ REVOLVING MARKETS ] ────────────────────────────────────────────

  // ┌─ test_gas_revolvingOpen ─────
  function test_gas_revolvingOpen() external {
    _common(MatrixMarketKind.Revolving, MatrixHooksKind.OpenTerm);
  }

  // ┌─ test_gas_revolvingFixed ─────
  function test_gas_revolvingFixed() external {
    _common(MatrixMarketKind.Revolving, MatrixHooksKind.FixedTerm);
  }

  // ┌─ test_gas_revolvingPeriodic ─────
  function test_gas_revolvingPeriodic() external {
    _common(MatrixMarketKind.Revolving, MatrixHooksKind.PeriodicTerm);
  }
}

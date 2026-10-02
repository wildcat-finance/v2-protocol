// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LifecycleAuthority.t
// ║  ██▀▀     ▀▀██   Lifecycle accounting through authority and collection-policy changes.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  AUTHORITY HANDOFF
// ║  test_termsAndDefaultSurviveBorrowerPrincipalAndHookAdminTransfers()
// ║
// ║  COLLECTION CONFIGURATION
// ║  test_queueVetoEndsAtRepaymentAndCollectionCannotBeVetoed()
// ║  test_replacementAprPolicyCannotLowerRepaymentReserve()
// ║  test_allNewModelsRejectEffectiveExecutionHookWithAndWithoutTerms()
// ╚═════

import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { WildcatMarketBase } from 'src/market/WildcatMarketBase.sol';
import {
  HooksConfig,
  Bit_Enabled_Deposit,
  Bit_Enabled_Transfer,
  Bit_Enabled_ExecuteWithdrawal,
  Bit_Enabled_QueueWithdrawal
} from 'src/types/HooksConfig.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';

// ┌─ LifecycleAuthorityTest ───────────────────────────────────────────────────
/// @dev authority changes need the real factory callback and registry, not the small matrix stub.
contract LifecycleAuthorityTest is ProductionMatrixFixture {
  // ░░▒▒▓▓██ [ AUTHORITY HANDOFF ] ────────────────────────────────────────────

  // ┌─ test_termsAndDefaultSurviveBorrowerPrincipalAndHookAdminTransfers ─────
  function test_termsAndDefaultSurviveBorrowerPrincipalAndHookAdminTransfers() external {
    vm.warp(1_800_000_000);
    ProductionStack memory stack = _deployProductionStack();
    address nextBorrower = address(0xB02202);
    stack.archController.registerBorrower(nextBorrower);
    for (uint256 i; i < 6; ++i) {
      MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind(i % 3), MatrixMarketKind(i / 3));
      options.repaymentDate = uint32(vm.getBlockTimestamp() + 90 days);
      options.repaymentPeriod = 0;
      MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(800 + i));
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, 1_000e18);
      _borrow(cell, 800e18);
      vm.warp(uint256(options.repaymentDate) + 1);
      cell.market.updateState();
      assertEq(cell.market.defaultedAt(), options.repaymentDate, 'missed zero-period deadline');

      vm.prank(MatrixBorrower);
      cell.market.requestBorrowerTransfer(nextBorrower);
      vm.prank(nextBorrower);
      cell.market.acceptBorrowerTransfer();
      vm.prank(MatrixBorrower);
      cell.hooks.requestAdministratorTransfer(nextBorrower);
      vm.prank(nextBorrower);
      cell.hooks.acceptAdministratorTransfer();
      assertEq(cell.market.borrower(), nextBorrower, 'new borrower');
      assertEq(cell.market.borrowerPrincipal(), nextBorrower, 'new principal');
      assertEq(cell.hooks.administrator(), nextBorrower, 'new hook administrator');
      assertEq(cell.market.repaymentDate(), options.repaymentDate, 'date immutable');
      assertEq(cell.market.repaymentPeriod(), 0, 'period immutable');
      assertEq(cell.market.repaymentDeadline(), options.repaymentDate, 'deadline immutable');
      assertEq(cell.market.defaultedAt(), options.repaymentDate, 'marker survives transfers');

      cell.operationalBorrower = nextBorrower;
      uint256 due = cell.market.totalDebts() - cell.market.totalAssets();
      _approveBorrower(stack, cell, due);
      _repay(cell, due);
      assertTrue(cell.market.isClosed(), 'new borrower finishes repayment');
      assertEq(cell.market.defaultedAt(), options.repaymentDate, 'marker survives closure');
    }
  }
}

// ┌─ LifecycleCollectionConfigurationTest ─────────────────────────────────────
contract LifecycleCollectionConfigurationTest is MarketFixture {
  error PolicyVeto();

  // ░░▒▒▓▓██ [ COLLECTION CONFIGURATION ] ─────────────────────────────────────

  // ┌─ test_queueVetoEndsAtRepaymentAndCollectionCannotBeVetoed ─────
  function test_queueVetoEndsAtRepaymentAndCollectionCannotBeVetoed() external {
    vm.warp(1_800_000_000);
    for (uint256 model; model < 2; ++model) {
      for (uint256 dated; dated < 2; ++dated) {
        Options memory options = _defaultOptions(HooksKind.OpenTerm);
        options.revolving = model == 1;
        options.requestedHooks = HooksConfig.wrap(
          (1 << Bit_Enabled_Deposit) | (1 << Bit_Enabled_Transfer) | (1 << Bit_Enabled_QueueWithdrawal)
        );
        options.repaymentDate = dated == 0 ? 0 : uint32(vm.getBlockTimestamp() + 1 days);
        Fixture memory fixture = _newMarket(options);
        address lender = address(0xA11CE);
        MockRoleProvider provider = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
        vm.prank(Borrower);
        BaseAccessControls(address(fixture.hooks)).addRoleProvider(address(provider), type(uint32).max);
        vm.prank(address(provider));
        BaseAccessControls(address(fixture.hooks)).grantRole(lender, uint32(vm.getBlockTimestamp()));
        _deposit(fixture, lender, 1_000e18);
        vm.prank(Borrower);
        fixture.market.borrow(800e18);
        bytes memory veto = abi.encodeWithSelector(PolicyVeto.selector);
        if (dated != 0) {
          vm.mockCallRevert(address(fixture.hooks), abi.encodePacked(IHooks.onQueueWithdrawal.selector), veto);
          vm.prank(lender);
          vm.expectRevert(veto);
          fixture.market.queueFullWithdrawal();
          vm.warp(options.repaymentDate);
        }
        vm.prank(lender);
        uint32 expiry = fixture.market.queueFullWithdrawal();
        vm.mockCallRevert(address(fixture.hooks), abi.encodePacked(IHooks.onExecuteWithdrawal.selector), veto);
        fixture.sentinel.setSanctioned(lender, true);
        vm.warp(uint256(expiry) + 1);
        uint256 amount = fixture.market.executeWithdrawal(lender, expiry);
        assertTrue(amount != 0, 'payable claim executes despite policy veto');
        assertEq(fixture.asset.balanceOf(fixture.sentinel.EscrowAddress()), amount, 'sanctions still route collection');
        assertEq(fixture.asset.balanceOf(lender), 0, 'sanctioned lender does not receive cash');
        vm.clearMockedCalls();
      }
    }
  }

  // ┌─ test_replacementAprPolicyCannotLowerRepaymentReserve ─────
  function test_replacementAprPolicyCannotLowerRepaymentReserve() external {
    vm.warp(1_800_000_000);
    for (uint256 model; model < 2; ++model) {
      Options memory options = _defaultOptions(HooksKind.OpenTerm);
      options.revolving = model == 1;
      options.repaymentDate = uint32(vm.getBlockTimestamp() + 1 days);
      IHooks hooks = IHooks(
        _deployCode('test/mocks/AprReplacementHooks.sol:OpenAprReplacementHooks', abi.encode(Borrower, bytes('')))
      );
      Fixture memory fixture = _newMarket(options, hooks);
      _deposit(fixture, address(0xA11CE), 1_000e18);
      vm.prank(Borrower);
      fixture.market.borrow(800e18);
      vm.warp(options.repaymentDate);
      fixture.market.updateState();
      vm.prank(Borrower);
      vm.expectRevert(WildcatMarketBase.RepaymentReserveRequired.selector);
      fixture.market.setAnnualInterestAndReserveRatioBips(900, 10_000);
      assertEq(fixture.market.reserveRatioBips(), 10_000, 'core validates the hook result');
    }
  }

  // ┌─ test_allNewModelsRejectEffectiveExecutionHookWithAndWithoutTerms ─────
  function test_allNewModelsRejectEffectiveExecutionHookWithAndWithoutTerms() external {
    vm.warp(1_800_000_000);
    for (uint256 model; model < 2; ++model) {
      Options memory options = _defaultOptions(HooksKind.OpenTerm);
      options.revolving = model == 1;
      Fixture memory fixture = _newMarket(options);
      HooksConfig config =
        HooksConfig.wrap(HooksConfig.unwrap(fixture.market.hooks()) | (1 << Bit_Enabled_ExecuteWithdrawal));
      string memory artifact = model == 0
        ? 'src/market/WildcatMarket.sol:WildcatMarket'
        : 'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving';
      bytes memory creationCode = vm.getCode(artifact);
      for (uint256 dated; dated < 2; ++dated) {
        options.repaymentDate = dated == 0 ? 0 : uint32(vm.getBlockTimestamp() + 1 days);
        MarketParameters memory parameters = _buildMarketParameters(fixture, options, config);
        fixture.factory.setMarketParameters(parameters);
        vm.expectRevert(WildcatMarketBase.UnsupportedExecuteWithdrawalHook.selector);
        fixture.factory.deployMarket(creationCode);
      }
    }
  }
}

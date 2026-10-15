// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // NukeProtectionTest
//  \ ^ /   Permanent integration protection throughout a market's lifetime.
//    V
//
//  OPERATIONS
//  _featureFactory()
//  _cell(...)
//  test_approvalUsesCurrentArchControllerOwnerAndCannotRevokeProtection()
//  test_registrationRequiresApprovedFactoryOwnMarketAndAuthenticatedContract()
//  test_protectedFeaturesCannotBeNukedAndOrdinarySanctionsStillApplyAcrossMatrix()
//  test_newFactoryCanProtectFundedMarketsMonthsAfterBothDepositEntrypoints()
//  test_wrapperSetupIsAtomicAndTransferDisabledMarketsSkipIt()
//  test_marketsWithoutCompleteWrapperPoliciesRemainDeployable()
//  test_automaticWrapperUsesTheFinalInstalledHooks()
//  test_depositCallbacksRespectApprovalAndRegistrationRollsBackWithDeposit()
//  _assertWrapperLogs(...)
//  deployCell(...)
// ═════

import { IHooksFactory, IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { HooksConfig, EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { NukeProtectionFactoryMock, ProtectedFeatureMock } from '../mocks/NukeProtectionMocks.sol';
import { NukeProtectionCallbackHooks, NukeProtectionCallbackToken } from '../mocks/NukeProtectionMocks.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { Vm } from 'forge-std/Vm.sol';

// ┌─ NukeProtectionTest ───────────────────────────────────────────────────────
contract NukeProtectionTest is ProductionMatrixFixture {
  uint256 internal constant Deposit = 100e18;

  // ┌─ _featureFactory ─────
  function _featureFactory() private returns (NukeProtectionFactoryMock) {
    return NukeProtectionFactoryMock(_deployCode('test/mocks/NukeProtectionMocks.sol:NukeProtectionFactoryMock'));
  }

  // ┌─ _cell ─────
  function _cell(ProductionStack memory stack, uint256 i) private returns (MatrixCell memory) {
    return _deployMatrixCell(
      stack,
      _defaultMatrixOptions(MatrixHooksKind(i % 3), MatrixMarketKind(i / 3)),
      MatrixBorrower,
      MatrixBorrower,
      uint96(900 + i)
    );
  }

  // ┌─ test_approvalUsesCurrentArchControllerOwnerAndCannotRevokeProtection ─────
  function test_approvalUsesCurrentArchControllerOwnerAndCannotRevokeProtection() external {
    ProductionStack memory stack = _deployProductionStack();
    NukeProtectionFactoryMock featureFactory = _featureFactory();
    for (uint256 i; i < 2; i++) {
      MatrixCell memory cell = _cell(stack, i * 3);
      IHooksFactory factory = _factoryFor(stack, MatrixMarketKind(i));
      vm.prank(MatrixBorrower);
      vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);

      vm.expectRevert(IHooksFactoryEventsAndErrors.NukeProtectionRequiresContract.selector);
      factory.setNukeProtectionFactoryApproval(MatrixAlice, true);
      vm.expectRevert(IHooksFactoryEventsAndErrors.NukeProtectionRequiresContract.selector);
      factory.setNukeProtectionFactoryApproval(address(0), true);

      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);
      address instance = featureFactory.createFeature(address(cell.market));
      assertTrue(cell.market.isNukeProtected(instance));
      factory.setNukeProtectionFactoryApproval(address(featureFactory), false);
      assertFalse(factory.isApprovedNukeProtectionFactory(address(featureFactory)));
      assertTrue(cell.market.isNukeProtected(instance), 'approval removal must not revoke protection');
      vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector);
      featureFactory.createFeature(address(cell.market));
      stack.sanctionsList.sanction(instance);
      vm.expectRevert(IMarketEventsAndErrors.CannotNukeProtectedAccount.selector);
      cell.market.nukeFromOrbit(instance);
    }

    stack.archController.transferOwnership(MatrixBob);
    for (uint256 i; i < 2; i++) {
      IHooksFactory factory = _factoryFor(stack, MatrixMarketKind(i));
      vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);
      vm.prank(MatrixBob);
      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);
      assertTrue(factory.isApprovedNukeProtectionFactory(address(featureFactory)));
    }
  }

  // ┌─ test_registrationRequiresApprovedFactoryOwnMarketAndAuthenticatedContract ─────
  function test_registrationRequiresApprovedFactoryOwnMarketAndAuthenticatedContract() external {
    ProductionStack memory stack = _deployProductionStack();
    NukeProtectionFactoryMock featureFactory = _featureFactory();
    MatrixCell memory other = _cell(stack, 3);
    MatrixCell memory cell = _cell(stack, 0);
    address market = address(cell.market);
    address counterfeit = _deployCode('test/mocks/NukeProtectionMocks.sol:ProtectedFeatureMock', abi.encode(market));

    vm.expectRevert(IMarketEventsAndErrors.NotFactory.selector);
    cell.market.registerNukeProtectedAccount(counterfeit);
    vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector);
    stack.standardFactory.registerNukeProtectedAccount(market, counterfeit);
    vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector);
    featureFactory.createFeature(market);

    stack.standardFactory.setNukeProtectionFactoryApproval(address(featureFactory), true);
    vm.expectRevert(NukeProtectionFactoryMock.InvalidFeatureInstance.selector);
    featureFactory.registerInstance(market, counterfeit);
    vm.prank(address(featureFactory));
    vm.expectRevert(IHooksFactoryEventsAndErrors.NukeProtectionMarketNotFound.selector);
    stack.standardFactory.registerNukeProtectedAccount(address(other.market), counterfeit);
    vm.prank(address(featureFactory));
    vm.expectRevert(IHooksFactoryEventsAndErrors.NukeProtectionMarketNotFound.selector);
    stack.standardFactory.registerNukeProtectedAccount(counterfeit, counterfeit);
    vm.prank(address(featureFactory));
    vm.expectRevert(IHooksFactoryEventsAndErrors.NukeProtectionRequiresContract.selector);
    stack.standardFactory.registerNukeProtectedAccount(market, MatrixAlice);

    address instance = featureFactory.createFeature(market);
    assertEq(ProtectedFeatureMock(instance).market(), market);
    assertTrue(cell.market.isNukeProtected(instance));
    assertFalse(other.market.isNukeProtected(instance));
    vm.expectRevert(NukeProtectionFactoryMock.InvalidFeatureInstance.selector);
    featureFactory.registerInstance(address(other.market), instance);
  }

  // ┌─ test_protectedFeaturesCannotBeNukedAndOrdinarySanctionsStillApplyAcrossMatrix ─────
  function test_protectedFeaturesCannotBeNukedAndOrdinarySanctionsStillApplyAcrossMatrix() external {
    ProductionStack memory stack = _deployProductionStack();
    NukeProtectionFactoryMock featureFactory = _featureFactory();
    stack.standardFactory.setNukeProtectionFactoryApproval(address(featureFactory), true);
    stack.revolvingFactory.setNukeProtectionFactoryApproval(address(featureFactory), true);
    for (uint256 i; i < 6; i++) {
      MatrixCell memory cell = _cell(stack, i);
      address instance = featureFactory.createFeature(address(cell.market));
      address wrapper = cell.market.registeredWrapper();
      assertTrue(wrapper != address(0), 'wrapper created with market');
      assertEq(stack.wrapperFactory.wrapperForMarket(address(cell.market)), wrapper);
      assertTrue(cell.market.isNukeProtected(wrapper));
      _authorize(stack, cell, instance);
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, instance, Deposit);
      _deposit(stack, cell, MatrixAlice, Deposit);
      stack.sanctionsList.sanction(instance);
      stack.sanctionsList.sanction(wrapper);
      vm.expectRevert(IMarketEventsAndErrors.CannotNukeProtectedAccount.selector);
      cell.market.nukeFromOrbit(instance);
      vm.expectRevert(IMarketEventsAndErrors.CannotNukeProtectedAccount.selector);
      cell.market.nukeFromOrbit(wrapper);
      assertEq(cell.market.scaledBalanceOf(instance), Deposit);
      _fundAndApprove(stack, cell, instance, Deposit);
      vm.prank(instance);
      vm.expectRevert(IMarketEventsAndErrors.AccountBlocked.selector);
      cell.market.deposit(Deposit);
      vm.prank(instance);
      vm.expectRevert(IMarketEventsAndErrors.AccountBlocked.selector);
      cell.market.queueFullWithdrawal();

      _warpToWithdrawalAccess(cell);
      stack.sanctionsList.sanction(MatrixAlice);
      cell.market.nukeFromOrbit(MatrixAlice);
      assertEq(cell.market.scaledBalanceOf(MatrixAlice), 0, 'ordinary sanctioned lender still quarantined');
      stack.sanctionsList.unsanction(MatrixAlice);
      address laterInstance = featureFactory.createFeature(address(cell.market));
      assertTrue(cell.market.isNukeProtected(laterInstance));
    }
  }

  // ┌─ test_newFactoryCanProtectFundedMarketsMonthsAfterBothDepositEntrypoints ─────
  function test_newFactoryCanProtectFundedMarketsMonthsAfterBothDepositEntrypoints() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 i; i < 4; i++) {
      NukeProtectionFactoryMock featureFactory = _featureFactory();
      IHooksFactory factory = _factoryFor(stack, MatrixMarketKind(i / 2));
      MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind(i / 2));
      options.annualInterestBips = 0;
      options.commitmentFeeBips = 0;
      MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(950 + i));
      address instance = featureFactory.createUnregisteredFeature(address(cell.market));
      _authorize(stack, cell, instance);
      _fundAndApprove(stack, cell, instance, Deposit);
      if (i % 2 == 0) {
        vm.prank(instance);
        cell.market.deposit(Deposit);
      } else {
        vm.prank(instance);
        assertEq(cell.market.depositUpTo(Deposit), Deposit);
      }

      vm.warp(vm.getBlockTimestamp() + 90 days);
      assertFalse(cell.market.isNukeProtected(instance));
      vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector);
      featureFactory.registerInstance(address(cell.market), instance);
      vm.prank(MatrixBorrower);
      vm.expectRevert(IHooksFactoryEventsAndErrors.CallerNotArchControllerOwner.selector);
      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);
      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);
      featureFactory.registerInstance(address(cell.market), instance);
      assertTrue(cell.market.isNukeProtected(instance), 'existing funded instance can gain protection');
      address laterInstance = featureFactory.createFeature(address(cell.market));
      assertTrue(cell.market.isNukeProtected(laterInstance), 'new instance can gain protection');
      assertEq(cell.market.scaledBalanceOf(instance), Deposit, 'registration preserves balance');
      assertEq(cell.market.scaledTotalSupply(), Deposit, 'registration preserves supply');

      factory.setNukeProtectionFactoryApproval(address(featureFactory), false);
      assertTrue(cell.market.isNukeProtected(instance), 'revocation cannot remove existing protection');
      assertTrue(cell.market.isNukeProtected(laterInstance));
      stack.sanctionsList.sanction(instance);
      vm.expectRevert(IMarketEventsAndErrors.CannotNukeProtectedAccount.selector);
      cell.market.nukeFromOrbit(instance);
      stack.sanctionsList.unsanction(instance);
      vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector);
      featureFactory.createFeature(address(cell.market));
      factory.setNukeProtectionFactoryApproval(address(featureFactory), true);
      assertTrue(cell.market.isNukeProtected(featureFactory.createFeature(address(cell.market))));

      vm.prank(instance);
      uint32 expiry = cell.market.queueFullWithdrawal();
      assertEq(cell.market.scaledTotalSupply(), 0);
      vm.warp(uint256(expiry) + 1);
      cell.market.executeWithdrawal(instance, expiry);
      assertTrue(cell.market.isNukeProtected(instance), 'exit cannot remove protection');
      assertTrue(cell.market.isNukeProtected(featureFactory.createFeature(address(cell.market))));
    }
  }

  // ┌─ test_wrapperSetupIsAtomicAndTransferDisabledMarketsSkipIt ─────
  function test_wrapperSetupIsAtomicAndTransferDisabledMarketsSkipIt() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 i; i < 2; i++) {
      IHooksFactory factory = _factoryFor(stack, MatrixMarketKind(i));
      factory.setNukeProtectionFactoryApproval(address(stack.wrapperFactory), false);
      // The whole deployment rolls back, allowing the same CREATE2 salt to be retried.
      vm.expectRevert(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector);
      this.deployCell(stack, i * 3);
      factory.setNukeProtectionFactoryApproval(address(stack.wrapperFactory), true);
      vm.recordLogs();
      MatrixCell memory cell = _cell(stack, i * 3);
      Vm.Log[] memory logs = vm.getRecordedLogs();
      address wrapper = cell.market.registeredWrapper();
      assertTrue(wrapper != address(0));
      assertTrue(factory.isMarket(address(cell.market)));
      assertEq(stack.wrapperFactory.wrapperForMarket(address(cell.market)), wrapper);
      assertTrue(cell.market.isNukeProtected(wrapper));
      _assertWrapperLogs(logs, address(factory), address(cell.market), wrapper, address(stack.wrapperFactory));

      MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind(i));
      options.transfersDisabled = true;
      cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(980 + i));
      assertEq(cell.market.registeredWrapper(), address(0));
      vm.expectRevert(
        abi.encodeWithSelector(Wildcat4626WrapperFactory.MarketTransfersDisabled.selector, address(cell.market))
      );
      stack.wrapperFactory.createWrapper(address(cell.market));
    }
  }

  // ┌─ test_marketsWithoutCompleteWrapperPoliciesRemainDeployable ─────
  function test_marketsWithoutCompleteWrapperPoliciesRemainDeployable() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 kind; kind < 2; kind++) {
      IHooksFactory factory = _factoryFor(stack, MatrixMarketKind(kind));
      for (uint256 policy; policy < 3; policy++) {
        string memory artifact = policy == 0
          ? 'test/mocks/BorrowerAccountMocks.sol:CredentialedBorrowHooksMock'
          : policy == 1
            ? 'test/mocks/NukeProtectionMocks.sol:PartialWrapperPolicyHooksMock'
            : 'test/mocks/NukeProtectionMocks.sol:MalformedWrapperPolicyHooksMock';
        bytes memory initCode = vm.getCode(artifact);
        address template = LibStoredInitCode.deployInitCode(initCode);
        factory.addHooksTemplate(template, 'Custom policy', address(0), address(0), 0, 0, keccak256(initCode));
        stack.hooksTemplates[0] = template;
        MatrixCell memory cell = _deployMatrixCell(
          stack,
          _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind(kind)),
          MatrixBorrower,
          MatrixBorrower,
          uint96(990 + kind * 3 + policy)
        );
        assertTrue(factory.isMarket(address(cell.market)));
        assertTrue(stack.archController.isRegisteredMarket(address(cell.market)));
        assertEq(cell.market.registeredWrapper(), address(0));
        _deposit(stack, cell, MatrixAlice, Deposit);
        assertEq(cell.market.scaledBalanceOf(MatrixAlice), Deposit);
      }
    }
  }

  // ┌─ test_automaticWrapperUsesTheFinalInstalledHooks ─────
  function test_automaticWrapperUsesTheFinalInstalledHooks() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 i; i < 2; i++) {
      IHooksFactory factory = _factoryFor(stack, MatrixMarketKind(i));
      vm.prank(MatrixBorrower);
      address requested = factory.deployHooksInstance(stack.hooksTemplates[0], '');
      vm.prank(MatrixBorrower);
      address installed = factory.deployHooksInstance(stack.hooksTemplates[0], '');
      MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind(i));
      uint96 nonce = uint96(1_000 + i);
      address market = factory.computeMarketAddress(_marketSalt(MatrixBorrower, nonce));
      HooksConfig requestedConfig = EmptyHooksConfig.setHooksAddress(requested);

      // Configure the final hook, then model a creation callback that selects it.
      vm.prank(address(factory));
      HooksConfig installedConfig = IHooks(installed)
        .onCreateMarket(
          MatrixBorrower,
          market,
          _marketInputs(stack, options, EmptyHooksConfig.setHooksAddress(installed)),
          _hooksData(options, vm.getBlockTimestamp())
        );
      vm.mockCall(requested, abi.encodeWithSelector(IHooks.onCreateMarket.selector), abi.encode(installedConfig));
      MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, nonce, requestedConfig);
      assertEq(cell.market.hooks().hooksAddress(), installed);
      address wrapper = cell.market.registeredWrapper();
      assertTrue(wrapper != address(0), 'final hook policy permits wrapping');
      assertTrue(cell.market.isNukeProtected(wrapper));
    }
  }

  // ┌─ test_depositCallbacksRespectApprovalAndRegistrationRollsBackWithDeposit ─────
  function test_depositCallbacksRespectApprovalAndRegistrationRollsBackWithDeposit() external {
    ProductionStack memory stack = _deployProductionStack();
    NukeProtectionFactoryMock featureFactory = _featureFactory();
    NukeProtectionCallbackToken token =
      NukeProtectionCallbackToken(_deployCode('test/mocks/NukeProtectionMocks.sol:NukeProtectionCallbackToken'));
    stack.asset = token;
    bytes memory initCode = vm.getCode('test/mocks/NukeProtectionMocks.sol:NukeProtectionCallbackHooks');
    address template = LibStoredInitCode.deployInitCode(initCode);
    stack.standardFactory
      .addHooksTemplate(template, 'Callback probe', address(0), address(0), 0, 0, keccak256(initCode));
    stack.hooksTemplates[0] = template;
    MatrixCell memory cell = _cell(stack, 0);
    NukeProtectionCallbackHooks hooks = NukeProtectionCallbackHooks(address(cell.hooks));
    address hookInstance = featureFactory.createUnregisteredFeature(address(cell.market));
    address tokenInstance = featureFactory.createUnregisteredFeature(address(cell.market));
    hooks.setProbe(featureFactory, hookInstance);
    token.setProbe(featureFactory, tokenInstance);
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, Deposit);
    assertFalse(hooks.registrationSucceeded(), 'hook cannot bypass factory approval');
    assertEq(
      bytes32(hooks.registrationError()),
      bytes32(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector)
    );
    assertFalse(token.registrationSucceeded(), 'token cannot bypass factory approval');
    assertEq(
      bytes32(token.registrationError()),
      bytes32(IHooksFactoryEventsAndErrors.NotApprovedNukeProtectionFactory.selector)
    );
    assertFalse(cell.market.isNukeProtected(hookInstance));
    assertFalse(cell.market.isNukeProtected(tokenInstance));
    assertEq(cell.market.scaledBalanceOf(MatrixAlice), Deposit);

    stack.standardFactory.setNukeProtectionFactoryApproval(address(featureFactory), true);
    // The exact-deposit capacity check reverts after both callbacks have registered.
    _fundAndApprove(stack, cell, MatrixAlice, uint256(cell.options.maxTotalSupply) + 1);
    vm.prank(MatrixAlice);
    vm.expectRevert(IMarketEventsAndErrors.MaxSupplyExceeded.selector);
    cell.market.deposit(uint256(cell.options.maxTotalSupply) + 1);
    assertFalse(cell.market.isNukeProtected(hookInstance), 'reverted hook registration rolls back');
    assertFalse(cell.market.isNukeProtected(tokenInstance), 'reverted token registration rolls back');
    assertEq(cell.market.scaledTotalSupply(), Deposit);

    _deposit(stack, cell, MatrixAlice, Deposit);
    assertTrue(hooks.registrationSucceeded());
    assertTrue(token.registrationSucceeded());
    assertTrue(cell.market.isNukeProtected(hookInstance));
    assertTrue(cell.market.isNukeProtected(tokenInstance));
    assertEq(cell.market.scaledBalanceOf(MatrixAlice), Deposit * 2, 'callbacks preserve deposit accounting');
    assertEq(cell.market.scaledTotalSupply(), Deposit * 2);
  }

  // ┌─ _assertWrapperLogs ─────
  function _assertWrapperLogs(
    Vm.Log[] memory logs,
    address factory,
    address market,
    address wrapper,
    address wrapperFactory
  )
    private
    pure
  {
    uint256 stage;
    for (uint256 i; i < logs.length; i++) {
      bytes32 topic = logs[i].topics[0];
      if (topic == keccak256('MarketRepaymentTerms(address,uint256,uint256)')) {
        assertEq(logs[i].emitter, factory);
        stage = 1;
      } else if (topic == keccak256('NukeProtectionRegistered(address)')) {
        assertEq(stage, 1, 'market discovery precedes protection');
        assertEq(logs[i].emitter, market);
        assertEq(address(uint160(uint256(logs[i].topics[1]))), wrapper);
        stage = 2;
      } else if (topic == keccak256('NukeProtectionRequested(address,address,address)')) {
        assertEq(stage, 2);
        assertEq(logs[i].emitter, factory);
        assertEq(address(uint160(uint256(logs[i].topics[1]))), market);
        assertEq(address(uint160(uint256(logs[i].topics[2]))), wrapper);
        assertEq(address(uint160(uint256(logs[i].topics[3]))), wrapperFactory);
        stage = 3;
      } else if (topic == keccak256('WrapperRegistered(address)')) {
        assertEq(stage, 3);
        assertEq(logs[i].emitter, market);
        stage = 4;
      } else if (topic == keccak256('WrapperDeployed(address,address)')) {
        assertEq(stage, 4);
        assertEq(logs[i].emitter, wrapperFactory);
        stage = 5;
      }
    }
    assertEq(stage, 5, 'complete wrapper setup event sequence');
  }

  // ┌─ deployCell ─────
  /// @dev an external boundary lets expectRevert cover the entire deployment fixture.
  function deployCell(ProductionStack memory stack, uint256 i) external {
    _cell(stack, i);
  }
}

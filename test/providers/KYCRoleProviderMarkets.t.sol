// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderMarkets.t
//  \ ^ /   End-to-end KYC lifecycle and closed-market slot reclamation on v2.1.
//    V
//
//  MARKET MATRIX
//  test_openTerm_KYCLifecycle()
//  test_fixedTerm_KYCLifecycle()
//  test_closeMarket_ReclaimsSlotForNextMarket()
//  test_deployMarketAndHooks_AndPreAllocationFlows()
//  _setupKYCStack()
//  _checkTemplate(...)
// ═════

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import {
  CreateProviderInputs,
  ExistingProviderInputs,
  NameAndProviderInputs
} from 'src/access/ProviderStructs.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { KYCAttributeInput } from 'src/providers/IKYCRegistry.sol';
import { ClosedMarketClaim, KYCRoleProviderAttachInputs } from 'src/providers/IKYCRoleProviderFactory.sol';
import { KYCRegistry } from 'src/providers/KYCRegistry.sol';
import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';
import { KYCRoleProviderFactory } from 'src/providers/KYCRoleProviderFactory.sol';
import { Bit_Enabled_Deposit, Bit_Enabled_Transfer, EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { Test, MarketInputParameters } from 'test/shared/Test.sol';
import { KYCLifecycleContext, KYCMarketLifecycle } from './KYCMarketLifecycle.sol';

// ┌─ KYCRoleProviderMarketsTest ───────────────────────────────────────────────
contract KYCRoleProviderMarketsTest is Test {
  bytes32 internal constant AttrVerified = bytes32(uint256(1));
  bytes32 internal constant AttrUS = bytes32(uint256(3));

  // ░░▒▒▓▓██ [ MARKET MATRIX ] ────────────────────────────────────────────────

  // ┌─ test_openTerm_KYCLifecycle ─────
  function test_openTerm_KYCLifecycle() external {
    _checkTemplate(hooksTemplate);
  }

  // ┌─ test_fixedTerm_KYCLifecycle ─────
  function test_fixedTerm_KYCLifecycle() external {
    _checkTemplate(fixedTermHooksTemplate);
  }

  // ┌─ test_closeMarket_ReclaimsSlotForNextMarket ─────
  function test_closeMarket_ReclaimsSlotForNextMarket() external {
    (KYCRegistry registry, KYCRoleProviderFactory kycFactory, KYCRoleProvider provider) = _setupKYCStack();
    MockERC20 asset = new MockERC20('Market Asset', 'AST', 18);
    address borrower = address(0xB01);
    address lender = address(0xA11CE);
    kycFactory.setBorrowerAllowance(borrower, 1);

    registry.setAttribute(KYCAttributeInput(lender, AttrVerified, uint40(vm.getBlockTimestamp()), 0, 1));
    asset.mint(lender, 10e18);

    // deploy market 1 and attach KYC (consumes borrower's 1/1 allowance).
    MarketInputParameters memory inputs;
    inputs.asset = address(asset);
    inputs.borrower = borrower;
    inputs.maxTotalSupply = 100e18;
    inputs.withdrawalBatchDuration = 1 hours;
    inputs.hooksTemplate = hooksTemplate;
    deployHooksInstance(inputs, false);
    address hooks1 = inputs.hooksConfig.hooksAddress();
    deployMarket(inputs);
    WildcatMarket market1 = market;

    KYCRoleProviderAttachInputs memory attach1 = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: address(provider),
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.prank(borrower);
    BaseAccessControls(hooks1).createRoleProvider(address(kycFactory), 0, abi.encode(attach1));
    assertEq(kycFactory.usedSlots(borrower), 1);

    vm.startPrank(lender);
    asset.approve(address(market1), 1e18);
    market1.deposit(1e18);
    vm.stopPrank();

    // close market 1 cleanly (deposit covers principal, zero interest).
    vm.prank(borrower);
    market1.closeMarket();
    assertTrue(market1.isClosed());

    // deploy market 2 on a fresh hooks instance; inline-reclaim market 1's slot at cap in one tx.
    MarketInputParameters memory inputs2;
    inputs2.asset = address(asset);
    inputs2.borrower = borrower;
    inputs2.maxTotalSupply = 100e18;
    inputs2.withdrawalBatchDuration = 1 hours;
    inputs2.hooksTemplate = hooksTemplate;
    deployHooksInstance(inputs2, false);
    address hooks2 = inputs2.hooksConfig.hooksAddress();
    deployMarket(inputs2);
    WildcatMarket market2 = market;

    ClosedMarketClaim[] memory claims = new ClosedMarketClaim[](1);
    claims[0] = ClosedMarketClaim({ hooksInstance: hooks1, marketIndex: 0 });
    KYCRoleProviderAttachInputs memory attach2 = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: address(provider),
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: claims
    });
    vm.prank(borrower);
    BaseAccessControls(hooks2).createRoleProvider(address(kycFactory), 0, abi.encode(attach2));

    assertEq(kycFactory.usedSlots(borrower), 1);
    assertTrue(kycFactory.closedMarketReclaimed(address(market1)));
    assertTrue(kycFactory.isHooksAuthorized(hooks2));

    vm.startPrank(lender);
    asset.approve(address(market2), 1e18);
    market2.deposit(1e18);
    vm.stopPrank();
    assertEq(market2.scaledBalanceOf(lender), 1e18);
  }

  // ┌─ test_deployMarketAndHooks_AndPreAllocationFlows ─────
  function test_deployMarketAndHooks_AndPreAllocationFlows() external {
    (KYCRegistry registry, KYCRoleProviderFactory kycFactory, KYCRoleProvider provider) = _setupKYCStack();
    MockERC20 asset = new MockERC20('Market Asset', 'AST', 18);
    address borrower = address(0xB07);
    address lender = address(0xA11CE);
    archController.registerBorrower(borrower);
    kycFactory.setBorrowerAllowance(borrower, 2);
    registry.setAttribute(KYCAttributeInput(lender, AttrVerified, uint40(vm.getBlockTimestamp()), 0, 1));
    asset.mint(lender, 10e18);

    // Flow 1: deployMarketAndHooks with pre-deployed provider in `existingProviders`, then authorizeHooks.
    ExistingProviderInputs[] memory existing = new ExistingProviderInputs[](1);
    existing[0] = ExistingProviderInputs({ providerAddress: address(provider), timeToLive: 0 });
    bytes memory templateArgs = abi.encode(
      NameAndProviderInputs({
        name: 'KYC Open Hooks',
        existingProviders: existing,
        roleProviderFactory: address(0),
        newProviderInputs: new CreateProviderInputs[](0)
      })
    );
    DeployMarketInputs memory deployInputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: 'KYC ',
      symbolPrefix: 'KYC',
      maxTotalSupply: 100e18,
      annualInterestBips: 0,
      delinquencyFeeBips: 0,
      withdrawalBatchDuration: 1 hours,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: EmptyHooksConfig.setFlag(Bit_Enabled_Deposit)
    });

    vm.prank(borrower);
    (address marketAddr, address hooksAddr) = hooksFactory.deployMarketAndHooks(
      hooksTemplate, templateArgs, deployInputs, '', bytes32(uint256(1)), address(0), 0
    );

    // fail-closed before authorizeHooks.
    vm.startPrank(lender);
    asset.approve(marketAddr, 2e18);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    WildcatMarket(marketAddr).deposit(1e18);
    vm.stopPrank();

    vm.prank(borrower);
    kycFactory.authorizeHooks(address(hooksFactory), hooksAddr, 1);

    vm.prank(lender);
    WildcatMarket(marketAddr).deposit(1e18);
    assertEq(WildcatMarket(marketAddr).scaledBalanceOf(lender), 1e18);

    // Flow 2: deployHooksInstance -> pre-allocate 1 slot via createRoleProvider -> deployMarket (live at block 0).
    vm.prank(borrower);
    address hooks2 = hooksFactory.deployHooksInstance(hooksTemplate, '');

    KYCRoleProviderAttachInputs memory attach2 = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: address(provider),
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.prank(borrower);
    BaseAccessControls(hooks2).createRoleProvider(address(kycFactory), 0, abi.encode(attach2));
    assertEq(kycFactory.usedSlots(borrower), 2);

    deployInputs.hooks = EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setHooksAddress(hooks2);
    vm.prank(borrower);
    address market2Addr = hooksFactory.deployMarket(deployInputs, '', bytes32(uint256(2)), address(0), 0);

    vm.startPrank(lender);
    asset.approve(market2Addr, 1e18);
    WildcatMarket(market2Addr).deposit(1e18);
    vm.stopPrank();
    assertEq(WildcatMarket(market2Addr).scaledBalanceOf(lender), 1e18);
  }

  // ┌─ _setupKYCStack ─────
  function _setupKYCStack()
    internal
    returns (KYCRegistry registry, KYCRoleProviderFactory kycFactory, KYCRoleProvider provider)
  {
    address[] memory keepers = new address[](1);
    keepers[0] = address(this);
    registry = new KYCRegistry(address(this), keepers);

    address[] memory factories = new address[](1);
    factories[0] = address(hooksFactory);
    kycFactory = new KYCRoleProviderFactory(address(this), registry, factories);

    bytes32[] memory req = new bytes32[](1);
    req[0] = AttrVerified;
    bytes32[] memory forb = new bytes32[](1);
    forb[0] = AttrUS;
    provider = KYCRoleProvider(kycFactory.deployRoleProvider('Non-US KYC', req, forb));
  }

  // ┌─ _checkTemplate ─────
  function _checkTemplate(address template) internal {
    (KYCRegistry registry, KYCRoleProviderFactory kycFactory, KYCRoleProvider provider) = _setupKYCStack();
    MockERC20 asset = new MockERC20('Market Asset', 'AST', 18);
    uint32[2] memory ttls = [uint32(0), uint32(1 hours)];
    for (uint256 i; i < ttls.length; ++i) {
      MarketInputParameters memory inputs;
      inputs.asset = address(asset);
      inputs.borrower = address(uint160(0xB01 + i));
      inputs.maxTotalSupply = 100e18;
      inputs.withdrawalBatchDuration = 1 hours;
      inputs.hooksTemplate = template;
      inputs.fixedTermEndTime = uint32(vm.getBlockTimestamp() + 2 days);
      kycFactory.setBorrowerAllowance(inputs.borrower, 1);

      deployHooksInstance(inputs, false);
      inputs.hooksConfig = inputs.hooksConfig.setFlag(Bit_Enabled_Transfer);
      deployMarket(inputs);

      KYCMarketLifecycle.checkAccess(
        vm,
        KYCLifecycleContext({
          registry: registry,
          kycFactory: kycFactory,
          provider: provider,
          hooksFactory: address(hooksFactory),
          market: market,
          hookAdmin: inputs.borrower,
          verifiedAttr: AttrVerified,
          ttl: ttls[i]
        })
      );
      if (template == fixedTermHooksTemplate) vm.warp(inputs.fixedTermEndTime);
      KYCMarketLifecycle.claimAfterRemoval(vm, market);
    }
  }
}

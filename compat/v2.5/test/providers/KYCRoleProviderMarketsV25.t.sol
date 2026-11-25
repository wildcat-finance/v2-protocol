// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderMarketsV25.t
//  \ ^ /   Canonical IR-built KYC artifacts on standard and revolving v2.5.
//    V
//
//  MARKET MATRIX
//  test_standardMarkets_KYCLifecycle()
//  test_revolvingMarkets_KYCLifecycle()
//  test_scheduledClosure_ReclaimCommitsClosedState()
//  _deployKYCStack(...)
//  _checkFactory(...)
// ═════

import { IKYCRegistry } from 'src/providers/IKYCRegistry.sol';
import { IKYCRoleProvider } from 'src/providers/IKYCRoleProvider.sol';
import {
  ClosedMarketClaim,
  IKYCRoleProviderFactory,
  KYCRoleProviderAttachInputs
} from 'src/providers/IKYCRoleProviderFactory.sol';
import { ProductionMatrixFixture } from 'test/shared/ProductionMatrixFixture.sol';
import { KYCLifecycleContext, KYCMarketLifecycle } from 'test/providers/KYCMarketLifecycle.sol';

// ┌─ KYCRoleProviderMarketsV25Test ────────────────────────────────────────────
contract KYCRoleProviderMarketsV25Test is ProductionMatrixFixture {
  bytes32 internal constant AttrVerified = bytes32(uint256(1));
  bytes32 internal constant AttrUS = bytes32(uint256(3));

  // ░░▒▒▓▓██ [ MARKET MATRIX ] ────────────────────────────────────────────────

  // ┌─ test_standardMarkets_KYCLifecycle ─────
  function test_standardMarkets_KYCLifecycle() external {
    _checkFactory(MatrixMarketKind.Standard);
  }

  // ┌─ test_revolvingMarkets_KYCLifecycle ─────
  function test_revolvingMarkets_KYCLifecycle() external {
    _checkFactory(MatrixMarketKind.Revolving);
  }

  // ┌─ test_scheduledClosure_ReclaimCommitsClosedState ─────
  function test_scheduledClosure_ReclaimCommitsClosedState() external {
    ProductionStack memory stack = _deployProductionStack();
    address activeHooksFactory = address(stack.standardFactory);
    (, IKYCRoleProviderFactory kycFactory, IKYCRoleProvider provider) = _deployKYCStack(activeHooksFactory);

    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard);
    options.annualInterestBips = 1_000;
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 10 days);
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, 99);

    // fund market and cover scheduled interest so it projects closed at `repaymentDate`.
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 10e18);
    _approveBorrower(stack, cell, 1e18);
    _repay(cell, 1e18);

    KYCRoleProviderAttachInputs memory attach = KYCRoleProviderAttachInputs({
      hooksFactory: activeHooksFactory,
      provider: address(provider),
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.prank(MatrixBorrower);
    cell.hooks.createRoleProvider(address(kycFactory), 0, abi.encode(attach));
    assertEq(kycFactory.usedSlots(MatrixBorrower), 1, 'slot charged');

    vm.warp(options.repaymentDate);
    assertFalse(cell.market.previousState().isClosed, 'not committed yet');
    assertTrue(cell.market.isClosed(), 'projected closed');

    // reclaiming calls `updateState()`, permanently committing closure and returning the slot.
    kycFactory.reclaimClosedMarket(address(cell.hooks), 0);
    assertTrue(cell.market.previousState().isClosed, 'closure committed');
    assertEq(kycFactory.usedSlots(MatrixBorrower), 0, 'slot returned');

    // closure persists even after 30 days of elapsed time.
    vm.warp(uint256(options.repaymentDate) + 30 days);
    assertTrue(cell.market.isClosed(), 'stays closed');
  }

  // ┌─ _deployKYCStack ─────
  function _deployKYCStack(address activeHooksFactory)
    internal
    returns (IKYCRegistry registry, IKYCRoleProviderFactory kycFactory, IKYCRoleProvider provider)
  {
    string memory registryArtifact = vm.envString('KYC_V25_TEST_REGISTRY_ARTIFACT');
    string memory factoryArtifact = vm.envString('KYC_V25_TEST_FACTORY_ARTIFACT');
    string memory providerArtifact = vm.envString('KYC_V25_TEST_PROVIDER_ARTIFACT');

    address[] memory keepers = new address[](1);
    keepers[0] = address(this);
    registry = IKYCRegistry(_deployCode(registryArtifact, abi.encode(address(this), keepers)));
    KYCMarketLifecycle.assertRuntimeMatchesArtifact(vm, address(registry), registryArtifact, new address[](0));

    address[] memory factories = new address[](1);
    factories[0] = activeHooksFactory;
    kycFactory =
      IKYCRoleProviderFactory(_deployCode(factoryArtifact, abi.encode(address(this), address(registry), factories)));
    address[] memory factoryImmutables = new address[](1);
    factoryImmutables[0] = address(registry);
    KYCMarketLifecycle.assertRuntimeMatchesArtifact(vm, address(kycFactory), factoryArtifact, factoryImmutables);
    kycFactory.setBorrowerAllowance(MatrixBorrower, 10);

    bytes32[] memory req = new bytes32[](1);
    req[0] = AttrVerified;
    bytes32[] memory forb = new bytes32[](1);
    forb[0] = AttrUS;
    provider = IKYCRoleProvider(kycFactory.deployRoleProvider('Non-US KYC', req, forb));
    address[] memory providerImmutables = new address[](2);
    providerImmutables[0] = address(registry);
    providerImmutables[1] = address(kycFactory);
    KYCMarketLifecycle.assertRuntimeMatchesArtifact(vm, address(provider), providerArtifact, providerImmutables);
  }

  // ┌─ _checkFactory ─────
  function _checkFactory(MatrixMarketKind kind) internal {
    ProductionStack memory stack = _deployProductionStack();
    address activeHooksFactory = kind == MatrixMarketKind.Standard
      ? address(stack.standardFactory)
      : address(stack.revolvingFactory);

    (IKYCRegistry registry, IKYCRoleProviderFactory kycFactory, IKYCRoleProvider provider) =
      _deployKYCStack(activeHooksFactory);

    uint32[2] memory ttls = [uint32(0), uint32(1 hours)];
    for (uint256 i; i <= uint256(MatrixHooksKind.PeriodicTerm); ++i) {
      MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind(i), kind);
      options.annualInterestBips = 0;
      options.commitmentFeeBips = 0;
      for (uint256 j; j < ttls.length; ++j) {
        MatrixCell memory cell =
          _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(i * ttls.length + j));
        KYCMarketLifecycle.checkAccess(
          vm,
          KYCLifecycleContext({
            registry: registry,
            kycFactory: kycFactory,
            provider: provider,
            hooksFactory: activeHooksFactory,
            market: cell.market,
            hookAdmin: MatrixBorrower,
            verifiedAttr: AttrVerified,
            ttl: ttls[j]
          })
        );
        _warpToWithdrawalAccess(cell);
        KYCMarketLifecycle.claimAfterRemoval(vm, cell.market);
      }
    }
  }
}

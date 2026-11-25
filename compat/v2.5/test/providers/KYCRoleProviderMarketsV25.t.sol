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
//  _checkFactory(...)
// ═════

import { IKYCRegistry } from 'src/providers/IKYCRegistry.sol';
import { IKYCRoleProvider } from 'src/providers/IKYCRoleProvider.sol';
import { IKYCRoleProviderFactory } from 'src/providers/IKYCRoleProviderFactory.sol';
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

  // ┌─ _checkFactory ─────
  function _checkFactory(MatrixMarketKind kind) internal {
    ProductionStack memory stack = _deployProductionStack();
    address activeHooksFactory = kind == MatrixMarketKind.Standard
      ? address(stack.standardFactory)
      : address(stack.revolvingFactory);

    string memory registryArtifact = vm.envString('KYC_V25_TEST_REGISTRY_ARTIFACT');
    string memory factoryArtifact = vm.envString('KYC_V25_TEST_FACTORY_ARTIFACT');
    string memory providerArtifact = vm.envString('KYC_V25_TEST_PROVIDER_ARTIFACT');

    address[] memory keepers = new address[](1);
    keepers[0] = address(this);
    IKYCRegistry registry = IKYCRegistry(_deployCode(registryArtifact, abi.encode(address(this), keepers)));
    assertEq(address(registry).codehash, keccak256(vm.getDeployedCode(registryArtifact)), 'registry runtime');

    address[] memory factories = new address[](1);
    factories[0] = activeHooksFactory;
    IKYCRoleProviderFactory kycFactory =
      IKYCRoleProviderFactory(_deployCode(factoryArtifact, abi.encode(address(this), address(registry), factories)));
    assertEq(address(kycFactory).codehash, keccak256(vm.getDeployedCode(factoryArtifact)), 'factory runtime');
    kycFactory.setBorrowerAllowance(MatrixBorrower, 10);

    bytes32[] memory req = new bytes32[](1);
    req[0] = AttrVerified;
    bytes32[] memory forb = new bytes32[](1);
    forb[0] = AttrUS;
    IKYCRoleProvider provider = IKYCRoleProvider(kycFactory.deployRoleProvider('Non-US KYC', req, forb));
    assertEq(address(provider).codehash, keccak256(vm.getDeployedCode(providerArtifact)), 'provider runtime');

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

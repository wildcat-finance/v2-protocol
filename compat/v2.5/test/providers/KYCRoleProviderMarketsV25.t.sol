// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderMarketsV25.t
//  \ ^ /   Legacy KYC provider bytecode on standard and revolving v2.5 markets.
//    V
//
//  MARKET MATRIX
//  test_standardMarkets_KYCLifecycle()
//  test_revolvingMarkets_KYCLifecycle()
//  _checkFactory(...)
// ═════

import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';
import { ProductionMatrixFixture } from 'test/shared/ProductionMatrixFixture.sol';
import { KYCMarketLifecycle } from 'test/providers/KYCMarketLifecycle.sol';

// ┌─ KYCRoleProviderMarketsV25Test ────────────────────────────────────────────
contract KYCRoleProviderMarketsV25Test is ProductionMatrixFixture {
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
    string memory artifact = vm.envString('KYC_V25_TEST_PROVIDER_ARTIFACT');
    KYCRoleProvider provider = KYCRoleProvider(_deployCode(artifact, abi.encode(address(this))));
    assertEq(address(provider).codehash, keccak256(vm.getDeployedCode(artifact)), 'legacy provider runtime');

    uint32[2] memory ttls = [uint32(0), uint32(1 hours)];
    for (uint256 i; i <= uint256(MatrixHooksKind.PeriodicTerm); ++i) {
      MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind(i), kind);
      options.annualInterestBips = 0;
      options.commitmentFeeBips = 0;
      for (uint256 j; j < ttls.length; ++j) {
        MatrixCell memory cell =
          _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(i * ttls.length + j));
        KYCMarketLifecycle.checkAccess(vm, provider, cell.market, MatrixBorrower, ttls[j]);
        _warpToWithdrawalAccess(cell);
        KYCMarketLifecycle.claimAfterRemoval(vm, cell.market);
      }
    }
  }
}

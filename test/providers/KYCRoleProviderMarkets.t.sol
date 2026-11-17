// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderMarkets.t
//  \ ^ /   KYC deposits and withdrawals on legacy open- and fixed-term markets.
//    V
//
//  MARKET MATRIX
//  test_openTerm_KYCLifecycle()
//  test_fixedTerm_KYCLifecycle()
//  _checkTemplate(...)
// ═════

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Test, MarketInputParameters } from 'test/shared/Test.sol';
import { KYCMarketLifecycle } from './KYCMarketLifecycle.sol';

// ┌─ KYCRoleProviderMarketsTest ───────────────────────────────────────────────
contract KYCRoleProviderMarketsTest is Test {
  // ░░▒▒▓▓██ [ MARKET MATRIX ] ────────────────────────────────────────────────

  // ┌─ test_openTerm_KYCLifecycle ─────
  function test_openTerm_KYCLifecycle() external {
    _checkTemplate(hooksTemplate);
  }

  // ┌─ test_fixedTerm_KYCLifecycle ─────
  function test_fixedTerm_KYCLifecycle() external {
    _checkTemplate(fixedTermHooksTemplate);
  }

  // ┌─ _checkTemplate ─────
  function _checkTemplate(address template) internal {
    KYCRoleProvider provider = new KYCRoleProvider(address(this));
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
      deployHooksInstance(inputs, false);
      inputs.hooksConfig = inputs.hooksConfig.setFlag(Bit_Enabled_Transfer);
      deployMarket(inputs);

      KYCMarketLifecycle.checkAccess(vm, provider, market, inputs.borrower, ttls[i]);
      if (template == fixedTermHooksTemplate) vm.warp(inputs.fixedTermEndTime);
      KYCMarketLifecycle.claimAfterRemoval(vm, market);
    }
  }
}

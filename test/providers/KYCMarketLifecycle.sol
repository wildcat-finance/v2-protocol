// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCMarketLifecycle
//  \ ^ /   Deposits, transfers, and withdrawals before and after KYC removal.
//    V
//
//  MARKET ACCESS
//  checkAccess(...)
//
//  WITHDRAWAL
//  claimAfterRemoval(...)
// ═════

import { Vm } from 'forge-std/Vm.sol';
import { Address } from 'openzeppelin/contracts/utils/Address.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';

// ┌─ KYCMarketLifecycle ───────────────────────────────────────────────────────
library KYCMarketLifecycle {
  address private constant Lender = address(0xA11CE);
  address private constant Recipient = address(0xB0B);

  // ░░▒▒▓▓██ [ MARKET ACCESS ] ────────────────────────────────────────────────

  // ┌─ checkAccess ─────
  /// @dev the balance checks assume a fresh gated market with no accrued interest or commitment fees.
  function checkAccess(Vm vm, KYCRoleProvider provider, WildcatMarket market, address hookAdmin, uint32 ttl) internal {
    BaseAccessControls hooks = BaseAccessControls(market.hooks().hooksAddress());
    MockERC20 asset = MockERC20(market.asset());
    uint256 approvedAt = vm.getBlockTimestamp();
    asset.mint(Lender, 6e18);
    vm.prank(Lender);
    asset.approve(address(market), 6e18);

    provider.addMember(Lender);
    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.deposit(3e18);
    vm.assertEq(asset.balanceOf(address(market)), 0, 'untrusted provider moved assets');
    vm.assertEq(market.scaledBalanceOf(Lender), 0, 'untrusted provider minted shares');

    vm.prank(hookAdmin);
    hooks.addRoleProvider(address(provider), ttl);
    bytes memory payload = abi.encode(address(market));
    vm.expectCall(address(provider), abi.encodeCall(IRoleProvider.validateCredential, (Lender, payload)));
    vm.prank(Lender);
    Address.functionCall(
      address(market), abi.encodePacked(abi.encodeCall(market.deposit, (3e18)), address(provider), payload)
    );
    vm.assertEq(asset.balanceOf(address(market)), 3e18, 'deposit assets');
    vm.assertEq(market.scaledBalanceOf(Lender), 3e18, 'deposit shares');

    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.transfer(Recipient, 1e18);
    provider.addMember(Recipient);
    vm.expectCall(address(provider), abi.encodeCall(IRoleProvider.getCredential, (Recipient)));
    vm.prank(Lender);
    market.transfer(Recipient, 1e18);
    vm.assertTrue(hooks.isKnownLenderOnMarket(Recipient, address(market)), 'approved recipient is known');

    provider.removeMember(Recipient);
    provider.removeMember(Lender);

    // a positive TTL includes the expiry timestamp on both hook generations.
    if (ttl != 0) {
      vm.warp(approvedAt + ttl);
      vm.prank(Lender);
      market.deposit(1e18);
    }
    vm.warp(approvedAt + ttl + 1);
    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.deposit(1e18);

    provider.addMember(Lender);
    vm.prank(Lender);
    market.deposit(1e18);
    provider.removeMember(Lender);

    // the first transfer made the recipient a known lender on this market.
    vm.prank(Lender);
    market.transfer(Recipient, 1e18);
    vm.assertEq(market.scaledBalanceOf(Recipient), 2e18, 'known recipient shares');
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL ] ───────────────────────────────────────────────────

  // ┌─ claimAfterRemoval ─────
  /// @dev for fixed terms, wait until maturity. for periodic terms, wait for an open withdrawal window.
  function claimAfterRemoval(Vm vm, WildcatMarket market) internal {
    MockERC20 asset = MockERC20(market.asset());
    uint256 balanceBefore = asset.balanceOf(Recipient);
    vm.prank(Recipient);
    uint32 expiry = market.queueFullWithdrawal();
    vm.assertEq(market.scaledBalanceOf(Recipient), 0, 'queued shares');

    vm.warp(uint256(expiry) + 1);
    vm.assertEq(market.executeWithdrawal(Recipient, expiry), 2e18, 'withdrawal paid');
    vm.assertEq(asset.balanceOf(Recipient) - balanceBefore, 2e18, 'underlying received');
  }
}

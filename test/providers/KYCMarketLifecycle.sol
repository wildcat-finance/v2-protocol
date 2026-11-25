// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCMarketLifecycle
//  \ ^ /   Deposits, transfers, and withdrawals before and after KYC removal.
//    V
//
//  MARKET ACCESS
//  checkAccess(...)
//  _attachProvider(...)
//
//  WITHDRAWAL
//  claimAfterRemoval(...)
//
//  ARTIFACTS
//  assertRuntimeMatchesArtifact(...)
//  _maskImmutableRefs(...)
// ═════

import { Vm } from 'forge-std/Vm.sol';
import { Address } from 'openzeppelin/contracts/utils/Address.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { IKYCRegistry, KYCAttributeInput } from 'src/providers/IKYCRegistry.sol';
import { IKYCRoleProvider } from 'src/providers/IKYCRoleProvider.sol';
import {
  ClosedMarketClaim,
  IKYCRoleProviderFactory,
  KYCRoleProviderAttachInputs
} from 'src/providers/IKYCRoleProviderFactory.sol';

/// @notice compiler-reported immutable reference offset inside `deployedBytecode.immutableReferences`.
/// @dev field order matches Foundry's alphabetical JSON ABI decoding (`length`, `start`).
struct ImmutableRef {
  uint256 length;
  uint256 start;
}

/// @notice shared inputs for running the KYC lifecycle against a deployed market.
struct KYCLifecycleContext {
  IKYCRegistry registry;
  IKYCRoleProviderFactory kycFactory;
  IKYCRoleProvider provider;
  address hooksFactory;
  WildcatMarket market;
  address hookAdmin;
  bytes32 verifiedAttr;
  uint32 ttl;
}

// ┌─ KYCMarketLifecycle ───────────────────────────────────────────────────────
library KYCMarketLifecycle {
  address private constant Lender = address(0xA11CE);
  address private constant Recipient = address(0xB0B);

  // ░░▒▒▓▓██ [ MARKET ACCESS ] ────────────────────────────────────────────────

  // ┌─ checkAccess ─────
  /// @dev balance checks assume a fresh gated market with no accrued interest or commitment fees.
  function checkAccess(Vm vm, KYCLifecycleContext memory ctx) internal {
    BaseAccessControls hooks = BaseAccessControls(ctx.market.hooks().hooksAddress());
    MockERC20 asset = MockERC20(ctx.market.asset());
    uint40 approvedAt = uint40(vm.getBlockTimestamp());
    asset.mint(Lender, 6e18);
    vm.prank(Lender);
    asset.approve(address(ctx.market), 6e18);

    ctx.registry.setAttribute(KYCAttributeInput(Lender, ctx.verifiedAttr, approvedAt, 0, 1));
    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    ctx.market.deposit(3e18);
    vm.assertEq(asset.balanceOf(address(ctx.market)), 0, 'untrusted provider moved assets');
    vm.assertEq(ctx.market.scaledBalanceOf(Lender), 0, 'untrusted provider minted shares');

    _attachProvider(vm, hooks, ctx);

    bytes memory payload = abi.encode(address(ctx.market));
    vm.expectCall(address(ctx.provider), abi.encodeCall(IRoleProvider.validateCredential, (Lender, payload)));
    vm.prank(Lender);
    Address.functionCall(
      address(ctx.market), abi.encodePacked(abi.encodeCall(ctx.market.deposit, (3e18)), address(ctx.provider), payload)
    );
    vm.assertEq(asset.balanceOf(address(ctx.market)), 3e18, 'deposit assets');
    vm.assertEq(ctx.market.scaledBalanceOf(Lender), 3e18, 'deposit shares');

    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    ctx.market.transfer(Recipient, 1e18);

    ctx.registry.setAttribute(KYCAttributeInput(Recipient, ctx.verifiedAttr, approvedAt, 0, 1));
    vm.expectCall(address(ctx.provider), abi.encodeCall(IRoleProvider.getCredential, (Recipient)));
    vm.prank(Lender);
    ctx.market.transfer(Recipient, 1e18);
    vm.assertTrue(hooks.isKnownLenderOnMarket(Recipient, address(ctx.market)), 'approved recipient is known');

    ctx.registry.removeAttribute(Recipient, ctx.verifiedAttr);
    ctx.registry.removeAttribute(Lender, ctx.verifiedAttr);

    // a positive TTL includes the expiry timestamp on both hook generations.
    if (ctx.ttl != 0) {
      vm.warp(approvedAt + ctx.ttl);
      vm.prank(Lender);
      ctx.market.deposit(1e18);
    }
    vm.warp(approvedAt + ctx.ttl + 1);
    vm.prank(Lender);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    ctx.market.deposit(1e18);

    ctx.registry.setAttribute(KYCAttributeInput(Lender, ctx.verifiedAttr, uint40(vm.getBlockTimestamp()), 0, 2));
    vm.prank(Lender);
    ctx.market.deposit(1e18);
    ctx.registry.removeAttribute(Lender, ctx.verifiedAttr);

    // the first transfer made the recipient a known lender on this market.
    vm.prank(Lender);
    ctx.market.transfer(Recipient, 1e18);
    vm.assertEq(ctx.market.scaledBalanceOf(Recipient), 2e18, 'known recipient shares');
  }

  // ┌─ _attachProvider ─────
  function _attachProvider(Vm vm, BaseAccessControls hooks, KYCLifecycleContext memory ctx) internal {
    KYCRoleProviderAttachInputs memory attachInputs = KYCRoleProviderAttachInputs({
      hooksFactory: ctx.hooksFactory,
      provider: address(ctx.provider),
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.prank(ctx.hookAdmin);
    hooks.createRoleProvider(address(ctx.kycFactory), ctx.ttl, abi.encode(attachInputs));
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

  // ░░▒▒▓▓██ [ ARTIFACTS ] ────────────────────────────────────────────────────

  // ┌─ assertRuntimeMatchesArtifact ─────
  /// @dev verify `target`'s runtime code matches `artifact`'s template everywhere outside the
  ///      compiler-reported `immutableReferences`, and that those slots match `expectedImmutables`.
  function assertRuntimeMatchesArtifact(
    Vm vm,
    address target,
    string memory artifact,
    address[] memory expectedImmutables
  )
    internal
    view
  {
    bytes memory template = vm.getDeployedCode(artifact);
    bytes memory deployed = target.code;
    vm.assertEq(deployed.length, template.length, 'runtime length');

    if (expectedImmutables.length == 0) {
      vm.assertEq(keccak256(deployed), keccak256(template), 'runtime codehash');
      return;
    }

    string memory json = vm.readFile(artifact);
    string[] memory keys = vm.parseJsonKeys(json, '.deployedBytecode.immutableReferences');
    vm.assertEq(keys.length, expectedImmutables.length, 'immutable count');

    bool[] memory matched = new bool[](expectedImmutables.length);
    for (uint256 k; k < keys.length; ++k) {
      string memory path = string.concat(".deployedBytecode.immutableReferences['", keys[k], "']");
      ImmutableRef[] memory refs = abi.decode(vm.parseJson(json, path), (ImmutableRef[]));
      _maskImmutableRefs(vm, template, deployed, refs, expectedImmutables, matched);
    }

    for (uint256 e; e < matched.length; ++e) {
      vm.assertTrue(matched[e], 'missing expected immutable');
    }
    vm.assertEq(keccak256(deployed), keccak256(template), 'masked runtime codehash');
  }

  // ┌─ _maskImmutableRefs ─────
  function _maskImmutableRefs(
    Vm vm,
    bytes memory template,
    bytes memory deployed,
    ImmutableRef[] memory refs,
    address[] memory expectedImmutables,
    bool[] memory matched
  )
    private
    pure
  {
    vm.assertTrue(refs.length != 0, 'empty immutable refs');

    bytes32 expectedWord;
    for (uint256 r; r < refs.length; ++r) {
      uint256 start = refs[r].start;
      vm.assertEq(refs[r].length, 32, 'immutable length');

      bytes32 templateWord;
      bytes32 deployedWord;
      assembly ('memory-safe') {
        templateWord := mload(add(add(template, 32), start))
        deployedWord := mload(add(add(deployed, 32), start))
        mstore(add(add(deployed, 32), start), 0)
      }
      vm.assertEq(templateWord, bytes32(0), 'template immutable placeholder');

      if (r == 0) {
        expectedWord = deployedWord;
        bool found;
        for (uint256 e; e < expectedImmutables.length; ++e) {
          if (!matched[e] && deployedWord == bytes32(uint256(uint160(expectedImmutables[e])))) {
            matched[e] = true;
            found = true;
            break;
          }
        }
        vm.assertTrue(found, 'unexpected immutable value');
      } else {
        vm.assertEq(deployedWord, expectedWord, 'inconsistent immutable occurrences');
      }
    }
  }
}

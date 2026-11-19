// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProvider.t
//  \ ^ /   Enrollment timestamps, credential lookups, and administrator transfers.
//    V
//
//  FIXTURE
//  setUp()
//
//  MEMBERSHIP
//  test_credentials_FollowMembershipAtQueryTime(...)
//  test_membership_InvalidChangesRevert()
//  test_batches_AreAtomic()
//
//  PROVIDER AUTHORITY
//  test_membership_OnlyAdministratorCanWrite()
//  test_handoff_OnlyAcceptanceMovesListAuthority()
//  test_handoff_CancelAndInvalidTargets()
//
//  CREDENTIAL TIMESTAMPS
//  test_credentials_TimestampDoesNotWrap()
// ═════

import { Test } from 'forge-std/Test.sol';
import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';

// ┌─ KYCRoleProviderTest ──────────────────────────────────────────────────────
contract KYCRoleProviderTest is Test {
  address internal constant Operator = address(0xA11);
  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);
  uint32 internal constant Start = 1_760_000_000;

  KYCRoleProvider internal provider;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(Start);
    provider = new KYCRoleProvider(Operator);
  }

  // ░░▒▒▓▓██ [ MEMBERSHIP ] ───────────────────────────────────────────────────

  // ┌─ test_credentials_FollowMembershipAtQueryTime ─────
  function test_credentials_FollowMembershipAtQueryTime(address wallet, bytes calldata data) external {
    vm.assume(wallet != address(0));
    IRoleProvider reader = provider;
    assertTrue(reader.isPullProvider());
    assertFalse(provider.isMember(wallet));
    assertEq(provider.addedAt(wallet), 0);
    assertEq(reader.getCredential(wallet), 0);
    assertEq(reader.validateCredential(wallet, data), 0);

    vm.expectEmit(true, true, false, true, address(provider));
    emit KYCRoleProvider.MemberAdded(Operator, wallet);
    vm.prank(Operator);
    provider.addMember(wallet);
    assertTrue(provider.isMember(wallet));
    assertEq(provider.addedAt(wallet), Start);
    assertEq(reader.getCredential(wallet), Start);

    vm.warp(Start + 90 days);
    assertEq(reader.getCredential(wallet), Start + 90 days);
    assertEq(reader.validateCredential(wallet, data), Start + 90 days);
    assertEq(provider.addedAt(wallet), Start);

    vm.expectEmit(true, true, false, true, address(provider));
    emit KYCRoleProvider.MemberRemoved(Operator, wallet);
    vm.prank(Operator);
    provider.removeMember(wallet);
    assertFalse(provider.isMember(wallet));
    assertEq(provider.addedAt(wallet), 0);
    assertEq(reader.getCredential(wallet), 0);
    assertEq(reader.validateCredential(wallet, data), 0);

    vm.prank(Operator);
    provider.addMember(wallet);
    assertEq(provider.addedAt(wallet), Start + 90 days);
    assertEq(reader.getCredential(wallet), Start + 90 days);
  }

  // ┌─ test_membership_InvalidChangesRevert ─────
  function test_membership_InvalidChangesRevert() external {
    vm.startPrank(Operator);
    vm.expectRevert(KYCRoleProvider.InvalidMember.selector);
    provider.addMember(address(0));
    vm.expectRevert(KYCRoleProvider.MemberNotFound.selector);
    provider.removeMember(Alice);
    provider.addMember(Alice);
    vm.warp(Start + 1);
    vm.expectRevert(KYCRoleProvider.MemberAlreadyExists.selector);
    provider.addMember(Alice);
    vm.stopPrank();
    assertFalse(provider.isMember(address(0)));
    assertEq(provider.addedAt(Alice), Start);
  }

  // ┌─ test_batches_AreAtomic ─────
  function test_batches_AreAtomic() external {
    address[] memory wallets = new address[](2);
    wallets[0] = Alice;
    wallets[1] = Alice;
    vm.startPrank(Operator);
    vm.expectRevert(KYCRoleProvider.MemberAlreadyExists.selector);
    provider.addMembers(wallets);
    assertEq(provider.addedAt(Alice), 0);

    wallets[1] = Bob;
    provider.addMembers(wallets);
    assertEq(provider.addedAt(Alice), Start);
    assertEq(provider.addedAt(Bob), Start);

    vm.warp(Start + 1);
    wallets[1] = Alice;
    vm.expectRevert(KYCRoleProvider.MemberNotFound.selector);
    provider.removeMembers(wallets);
    assertEq(provider.addedAt(Alice), Start);
    wallets[1] = Bob;
    provider.removeMembers(wallets);
    vm.stopPrank();
    assertEq(provider.addedAt(Alice), 0);
    assertEq(provider.addedAt(Bob), 0);
  }

  // ░░▒▒▓▓██ [ PROVIDER AUTHORITY ] ───────────────────────────────────────────

  // ┌─ test_membership_OnlyAdministratorCanWrite ─────
  function test_membership_OnlyAdministratorCanWrite() external {
    address[] memory wallets = new address[](1);
    wallets[0] = Alice;
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.addMember(Alice);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.addMembers(wallets);
    vm.prank(Operator);
    provider.addMember(Alice);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMembers(wallets);
    assertTrue(provider.isMember(Alice));
  }

  // ┌─ test_handoff_OnlyAcceptanceMovesListAuthority ─────
  function test_handoff_OnlyAcceptanceMovesListAuthority() external {
    vm.startPrank(Operator);
    provider.addMember(Alice);
    provider.requestAdministratorTransfer(Alice);
    provider.requestAdministratorTransfer(Bob);
    vm.stopPrank();
    assertEq(provider.administrator(), Operator);
    assertEq(provider.pendingAdministrator(), Bob);
    vm.prank(Alice);
    vm.expectRevert(IManagedRoleProvider.NotPendingAdministrator.selector);
    provider.acceptAdministratorTransfer();
    vm.startPrank(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);
    provider.acceptAdministratorTransfer();
    vm.stopPrank();
    assertEq(provider.administrator(), Bob);
    assertEq(provider.pendingAdministrator(), address(0));
    assertTrue(provider.isMember(Alice));
    vm.prank(Operator);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);
    vm.prank(Bob);
    provider.removeMember(Alice);
  }

  // ┌─ test_handoff_CancelAndInvalidTargets ─────
  function test_handoff_CancelAndInvalidTargets() external {
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    new KYCRoleProvider(address(0));
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.requestAdministratorTransfer(Bob);
    vm.startPrank(Operator);
    vm.expectRevert(IManagedRoleProvider.NoPendingAdministratorTransfer.selector);
    provider.cancelAdministratorTransfer();
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    provider.requestAdministratorTransfer(address(0));
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    provider.requestAdministratorTransfer(Operator);
    provider.requestAdministratorTransfer(Bob);
    vm.stopPrank();
    vm.prank(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.cancelAdministratorTransfer();
    vm.prank(Operator);
    provider.cancelAdministratorTransfer();
    vm.prank(Bob);
    vm.expectRevert(IManagedRoleProvider.NotPendingAdministrator.selector);
    provider.acceptAdministratorTransfer();
    assertEq(provider.administrator(), Operator);
    assertEq(provider.pendingAdministrator(), address(0));
  }

  // ░░▒▒▓▓██ [ CREDENTIAL TIMESTAMPS ] ────────────────────────────────────────

  // ┌─ test_credentials_TimestampDoesNotWrap ─────
  function test_credentials_TimestampDoesNotWrap() external {
    vm.prank(Operator);
    provider.addMember(Alice);
    vm.warp(type(uint32).max);
    assertEq(provider.getCredential(Alice), type(uint32).max);
    vm.warp(uint256(type(uint32).max) + 1);
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    provider.getCredential(Alice);
    assertEq(provider.getCredential(Bob), 0);
    vm.prank(Operator);
    provider.addMember(Bob);
    assertEq(provider.addedAt(Bob), uint256(type(uint32).max) + 1);
  }
}

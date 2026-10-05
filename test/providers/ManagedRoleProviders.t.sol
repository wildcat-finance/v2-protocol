// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ManagedRoleProviders.t
//  \ ^ /   Managed provider authority, membership, and hook integration.
//    V
//
//  FIXTURE
//  setUp()
//  _deployManaged(...)
//  _deployAccessList(...)
//  _singleMember(...)
//
//  PROVIDER AUTHORITY
//  test_managedProviderMatrix_RejectsZeroAdministrator()
//  test_managedProviderMatrix_RequestReplaceAndCancelTransfer()
//  test_managedProviderMatrix_TransferErrors()
//  test_managedProviderMatrix_AcceptMovesAuthorityAndPreservesConfiguration()
//  _mutateManaged(...)
//  _assertManagedConfiguration(...)
//
//  ACCESS LIST MEMBERSHIP
//  test_accessList_ConstructorAndCredentialsTrackMembership()
//  test_accessList_ConstructorRejectsInvalidInitialMembers()
//  test_accessList_ProviderInstancesKeepIndependentMembership()
//  test_accessList_SingleMemberUpdatesEmitAndAffectCredentials()
//  test_accessList_BatchUpdatesAreAtomic()
//  test_accessList_MemberUpdateErrorsAndAuthority()
//  test_accessList_PaginationClampsAndRejectsInvalidRanges()
//
//  HOOK ACCESS FIXTURES
//  _newHookFixture(...)
//  _deployHooks(...)
//  _deposit(...)
//  _expectDepositDenied(...)
//  _queueWithdrawal(...)
//
//  ACCESS LIST HOOK INTEGRATION
//  test_accessListHook_MembershipRemovalRespectsConfiguredTtl()
//  test_accessListHook_LocalBlockAndAttachmentSurviveProviderUpdates()
// ═════

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { AccessListRoleProvider } from 'src/providers/AccessListRoleProvider.sol';
import { IAccessListRoleProvider } from 'src/providers/IAccessListRoleProvider.sol';
import { encodeHooksConfig } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { RoleProvider } from 'src/types/RoleProvider.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ ManagedRoleProvidersTest ─────────────────────────────────────────────────
contract ManagedRoleProvidersTest is TestKernel {
  enum ManagedProviderKind {
    AccessList
  }

  struct HookFixture {
    OpenTermHooks hooks;
    address market;
    address provider;
  }

  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);
  address internal constant Carol = address(0xCA201);

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(1_714_737_030);
  }

  // ┌─ _deployManaged ─────
  function _deployManaged(ManagedProviderKind, address administrator) internal returns (IManagedRoleProvider provider) {
    return IManagedRoleProvider(address(_deployAccessList(administrator, _singleMember(Alice))));
  }

  // ┌─ _deployAccessList ─────
  function _deployAccessList(
    address administrator,
    address[] memory initialMembers
  )
    internal
    returns (AccessListRoleProvider provider)
  {
    provider = AccessListRoleProvider(
      _deployCode(
        'src/providers/AccessListRoleProvider.sol:AccessListRoleProvider', abi.encode(administrator, initialMembers)
      )
    );
  }

  // ┌─ _singleMember ─────
  function _singleMember(address account) internal pure returns (address[] memory members) {
    members = new address[](1);
    members[0] = account;
  }

  // ░░▒▒▓▓██ [ PROVIDER AUTHORITY ] ───────────────────────────────────────────

  // ┌─ test_managedProviderMatrix_RejectsZeroAdministrator ─────
  function test_managedProviderMatrix_RejectsZeroAdministrator() external {
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    _deployAccessList(address(0), new address[](0));
  }

  // ┌─ test_managedProviderMatrix_RequestReplaceAndCancelTransfer ─────
  function test_managedProviderMatrix_RequestReplaceAndCancelTransfer() external {
    for (uint8 i; i <= uint8(ManagedProviderKind.AccessList); i++) {
      IManagedRoleProvider provider = _deployManaged(ManagedProviderKind(i), address(this));

      vm.expectEmit(address(provider));
      emit IManagedRoleProvider.AdministratorTransferRequested(address(this), address(0), Bob);
      provider.requestAdministratorTransfer(Bob);

      vm.expectEmit(address(provider));
      emit IManagedRoleProvider.AdministratorTransferRequested(address(this), Bob, Carol);
      provider.requestAdministratorTransfer(Carol);
      assertEq(provider.pendingAdministrator(), Carol, 'replacement pending administrator');

      vm.expectEmit(address(provider));
      emit IManagedRoleProvider.AdministratorTransferCancelled(address(this), Carol);
      provider.cancelAdministratorTransfer();
      assertEq(provider.pendingAdministrator(), address(0), 'cleared pending administrator');

      vm.expectRevert(IManagedRoleProvider.NoPendingAdministratorTransfer.selector);
      provider.cancelAdministratorTransfer();
    }
  }

  // ┌─ test_managedProviderMatrix_TransferErrors ─────
  function test_managedProviderMatrix_TransferErrors() external {
    for (uint8 i; i <= uint8(ManagedProviderKind.AccessList); i++) {
      IManagedRoleProvider provider = _deployManaged(ManagedProviderKind(i), address(this));

      vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
      provider.requestAdministratorTransfer(address(0));
      vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
      provider.requestAdministratorTransfer(address(this));

      vm.prank(Bob);
      vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
      provider.requestAdministratorTransfer(Carol);

      vm.prank(Bob);
      vm.expectRevert(IManagedRoleProvider.NotPendingAdministrator.selector);
      provider.acceptAdministratorTransfer();
    }
  }

  // ┌─ test_managedProviderMatrix_AcceptMovesAuthorityAndPreservesConfiguration ─────
  function test_managedProviderMatrix_AcceptMovesAuthorityAndPreservesConfiguration() external {
    for (uint8 i; i <= uint8(ManagedProviderKind.AccessList); i++) {
      ManagedProviderKind kind = ManagedProviderKind(i);
      IManagedRoleProvider provider = _deployManaged(kind, address(this));
      provider.requestAdministratorTransfer(Bob);

      vm.prank(Bob);
      vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
      _mutateManaged(kind, provider);

      vm.expectEmit(address(provider));
      emit IManagedRoleProvider.AdministratorTransferred(address(this), Bob);
      vm.prank(Bob);
      provider.acceptAdministratorTransfer();

      assertEq(provider.administrator(), Bob, 'administrator');
      assertEq(provider.pendingAdministrator(), address(0), 'pending administrator');
      _assertManagedConfiguration(kind, provider, true);

      vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
      _mutateManaged(kind, provider);
      vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
      provider.requestAdministratorTransfer(Carol);

      vm.prank(Bob);
      _mutateManaged(kind, provider);
      _assertManagedConfiguration(kind, provider, false);
    }
  }

  // ┌─ _mutateManaged ─────
  function _mutateManaged(ManagedProviderKind, IManagedRoleProvider provider) internal {
    AccessListRoleProvider(address(provider)).addMember(Carol);
  }

  // ┌─ _assertManagedConfiguration ─────
  function _assertManagedConfiguration(
    ManagedProviderKind,
    IManagedRoleProvider provider,
    bool initialConfiguration
  )
    internal
    view
  {
    AccessListRoleProvider accessList = AccessListRoleProvider(address(provider));
    assertTrue(accessList.isMember(Alice), 'initial member');
    assertEq(accessList.isMember(Carol), !initialConfiguration, 'new member');
  }

  // ░░▒▒▓▓██ [ ACCESS LIST MEMBERSHIP ] ───────────────────────────────────────

  // ┌─ test_accessList_ConstructorAndCredentialsTrackMembership ─────
  function test_accessList_ConstructorAndCredentialsTrackMembership() external {
    AccessListRoleProvider provider = _deployAccessList(address(this), _singleMember(Alice));

    assertEq(provider.administrator(), address(this), 'administrator');
    assertEq(provider.pendingAdministrator(), address(0), 'pending administrator');
    assertTrue(provider.isPullProvider(), 'pull provider');
    assertTrue(provider.isMember(Alice), 'initial member');
    assertEq(provider.getMembersCount(), 1, 'member count');
    assertEq(provider.getMembers()[0], Alice, 'member');
    assertEq(provider.getCredential(Alice), uint32(getTimestamp()), 'pull credential');
    assertEq(provider.validateCredential(Alice, hex'1234'), uint32(getTimestamp()), 'validated');
    assertEq(provider.getCredential(Bob), 0, 'non-member pull credential');
    assertEq(provider.validateCredential(Bob, hex'1234'), 0, 'non-member validated credential');

    vm.warp(vm.getBlockTimestamp() + 1 days);
    assertEq(provider.getCredential(Alice), uint32(getTimestamp()), 'refreshed timestamp');
    provider.removeMember(Alice);
    assertEq(provider.getCredential(Alice), 0, 'removed credential');
    provider.addMember(Alice);
    assertEq(provider.getCredential(Alice), uint32(getTimestamp()), 'restored credential');
  }

  // ┌─ test_accessList_ConstructorRejectsInvalidInitialMembers ─────
  function test_accessList_ConstructorRejectsInvalidInitialMembers() external {
    address[] memory invalidMembers = new address[](1);
    vm.expectRevert(IAccessListRoleProvider.InvalidMember.selector);
    _deployAccessList(address(this), invalidMembers);

    address[] memory duplicateMembers = new address[](2);
    duplicateMembers[0] = Alice;
    duplicateMembers[1] = Alice;
    vm.expectRevert(IAccessListRoleProvider.MemberAlreadyExists.selector);
    _deployAccessList(address(this), duplicateMembers);
  }

  // ┌─ test_accessList_ProviderInstancesKeepIndependentMembership ─────
  function test_accessList_ProviderInstancesKeepIndependentMembership() external {
    AccessListRoleProvider first = _deployAccessList(address(this), _singleMember(Alice));
    AccessListRoleProvider second = _deployAccessList(address(this), _singleMember(Bob));
    first.removeMember(Alice);

    assertFalse(first.isMember(Alice), 'first alice');
    assertFalse(first.isMember(Bob), 'first bob');
    assertFalse(second.isMember(Alice), 'second alice');
    assertTrue(second.isMember(Bob), 'second bob');
  }

  // ┌─ test_accessList_SingleMemberUpdatesEmitAndAffectCredentials ─────
  function test_accessList_SingleMemberUpdatesEmitAndAffectCredentials() external {
    AccessListRoleProvider provider = _deployAccessList(address(this), _singleMember(Alice));

    vm.expectEmit(address(provider));
    emit IAccessListRoleProvider.MemberAdded(address(this), Bob);
    provider.addMember(Bob);
    assertTrue(provider.isMember(Bob), 'member after add');
    assertEq(provider.getCredential(Bob), uint32(getTimestamp()), 'credential after add');
    assertEq(provider.getMembersCount(), 2, 'count after add');

    vm.expectEmit(address(provider));
    emit IAccessListRoleProvider.MemberRemoved(address(this), Bob);
    provider.removeMember(Bob);
    assertFalse(provider.isMember(Bob), 'member after remove');
    assertEq(provider.getCredential(Bob), 0, 'credential after remove');
    assertEq(provider.getMembersCount(), 1, 'count after remove');
  }

  // ┌─ test_accessList_BatchUpdatesAreAtomic ─────
  function test_accessList_BatchUpdatesAreAtomic() external {
    AccessListRoleProvider provider = _deployAccessList(address(this), _singleMember(Alice));
    address[] memory accounts = new address[](2);
    accounts[0] = Bob;
    accounts[1] = Carol;

    provider.addMembers(accounts);
    assertTrue(provider.isMember(Bob), 'bob member');
    assertTrue(provider.isMember(Carol), 'carol member');
    assertEq(provider.getMembersCount(), 3, 'count after add');

    provider.removeMembers(accounts);
    assertFalse(provider.isMember(Bob), 'bob removed');
    assertFalse(provider.isMember(Carol), 'carol removed');
    assertEq(provider.getMembersCount(), 1, 'count after remove');

    accounts[0] = Bob;
    accounts[1] = address(0);
    vm.expectRevert(IAccessListRoleProvider.InvalidMember.selector);
    provider.addMembers(accounts);
    assertFalse(provider.isMember(Bob), 'partial add rolled back');
  }

  // ┌─ test_accessList_MemberUpdateErrorsAndAuthority ─────
  function test_accessList_MemberUpdateErrorsAndAuthority() external {
    AccessListRoleProvider provider = _deployAccessList(address(this), _singleMember(Alice));

    vm.expectRevert(IAccessListRoleProvider.InvalidMember.selector);
    provider.addMember(address(0));
    vm.expectRevert(IAccessListRoleProvider.MemberAlreadyExists.selector);
    provider.addMember(Alice);
    vm.expectRevert(IAccessListRoleProvider.MemberNotFound.selector);
    provider.removeMember(Bob);

    vm.startPrank(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.addMember(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);
    vm.stopPrank();
  }

  // ┌─ test_accessList_PaginationClampsAndRejectsInvalidRanges ─────
  function test_accessList_PaginationClampsAndRejectsInvalidRanges() external {
    AccessListRoleProvider provider = _deployAccessList(address(this), _singleMember(Alice));
    provider.addMember(Bob);
    provider.addMember(Carol);

    address[] memory members = provider.getMembers(1, 3);
    assertEq(members.length, 2, 'page length');
    assertEq(members[0], Bob, 'page 0');
    assertEq(members[1], Carol, 'page 1');
    assertEq(provider.getMembers(3, 10).length, 0, 'empty page');
    assertEq(provider.getMembers(10, 20).length, 0, 'past-end page');

    vm.expectRevert(IAccessListRoleProvider.InvalidPaginationRange.selector);
    provider.getMembers(2, 1);
  }

  // ░░▒▒▓▓██ [ HOOK ACCESS FIXTURES ] ─────────────────────────────────────────

  // ┌─ _newHookFixture ─────
  function _newHookFixture(
    address provider,
    uint32 timeToLive,
    uint160 marketSalt
  )
    internal
    returns (HookFixture memory fixture)
  {
    fixture.market = address(uint160(0xC000) + marketSalt);
    fixture.hooks = _deployHooks(fixture.market);
    fixture.provider = provider;
    fixture.hooks.addRoleProvider(provider, timeToLive);
  }

  // ┌─ _deployHooks ─────
  function _deployHooks(address market) internal returns (OpenTermHooks hooks) {
    hooks =
      OpenTermHooks(_deployCode('src/access/OpenTermHooks.sol:OpenTermHooks', abi.encode(address(this), bytes(''))));

    DeployMarketInputs memory parameters;
    parameters.hooks = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: false,
      useOnExecuteWithdrawal: false,
      useOnTransfer: false,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false,
      useOnSetProtocolFeeBips: false
    });
    hooks.onCreateMarket(address(this), market, parameters, '');
  }

  // ┌─ _deposit ─────
  function _deposit(HookFixture memory fixture, address lender, bytes memory hooksData) internal {
    MarketState memory state;
    vm.prank(fixture.market);
    fixture.hooks.onDeposit(lender, 1, state, hooksData);
  }

  // ┌─ _expectDepositDenied ─────
  function _expectDepositDenied(HookFixture memory fixture, address lender, bytes memory hooksData) internal {
    MarketState memory state;
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    vm.prank(fixture.market);
    fixture.hooks.onDeposit(lender, 1, state, hooksData);
  }

  // ┌─ _queueWithdrawal ─────
  function _queueWithdrawal(HookFixture memory fixture, address lender, bytes memory hooksData) internal {
    MarketState memory state;
    vm.prank(fixture.market);
    fixture.hooks.onQueueWithdrawal(lender, 0, 1, state, hooksData);
  }

  // ░░▒▒▓▓██ [ ACCESS LIST HOOK INTEGRATION ] ─────────────────────────────────

  // ┌─ test_accessListHook_MembershipRemovalRespectsConfiguredTtl ─────
  function test_accessListHook_MembershipRemovalRespectsConfiguredTtl() external {
    AccessListRoleProvider zeroTtlProvider = _deployAccessList(address(this), _singleMember(Alice));
    HookFixture memory zeroTtl = _newHookFixture(address(zeroTtlProvider), 0, 1);
    _deposit(zeroTtl, Alice, '');
    zeroTtlProvider.removeMember(Alice);
    _expectDepositDenied(zeroTtl, Alice, '');

    AccessListRoleProvider cachedProvider = _deployAccessList(address(this), _singleMember(Alice));
    HookFixture memory cached = _newHookFixture(address(cachedProvider), 1, 2);
    _deposit(cached, Alice, '');
    cachedProvider.removeMember(Alice);
    _deposit(cached, Alice, '');
    vm.warp(vm.getBlockTimestamp() + 2);
    _expectDepositDenied(cached, Alice, '');
  }

  // ┌─ test_accessListHook_LocalBlockAndAttachmentSurviveProviderUpdates ─────
  function test_accessListHook_LocalBlockAndAttachmentSurviveProviderUpdates() external {
    AccessListRoleProvider provider = _deployAccessList(address(this), _singleMember(Alice));
    HookFixture memory fixture = _newHookFixture(address(provider), 0, 3);
    RoleProvider attachment = fixture.hooks.getRoleProvider(address(provider));

    fixture.hooks.blockFromDeposits(Alice);
    _queueWithdrawal(fixture, Alice, '');
    LenderStatus memory status = fixture.hooks.getPreviousLenderStatus(Alice);
    assertTrue(status.isBlockedFromDeposits, 'local block');
    assertEq(status.lastProvider, address(provider), 'credential provider');

    provider.requestAdministratorTransfer(Bob);
    vm.prank(Bob);
    provider.acceptAdministratorTransfer();
    assertTrue(provider.isMember(Alice), 'membership preserved');
    assertEq(
      RoleProvider.unwrap(fixture.hooks.getRoleProvider(address(provider))),
      RoleProvider.unwrap(attachment),
      'hook attachment'
    );

    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);
    vm.prank(Bob);
    provider.removeMember(Alice);
    assertFalse(provider.isMember(Alice), 'new administrator authority');
  }
}

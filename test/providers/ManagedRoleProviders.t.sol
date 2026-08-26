// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { AccessListRoleProvider } from 'src/providers/AccessListRoleProvider.sol';
import { IAccessListRoleProvider } from 'src/providers/IAccessListRoleProvider.sol';
import { IMerkleRoleProvider } from 'src/providers/IMerkleRoleProvider.sol';
import { MerkleRoleProvider } from 'src/providers/MerkleRoleProvider.sol';
import { encodeHooksConfig } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { RoleProvider } from 'src/types/RoleProvider.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract ManagedRoleProvidersTest is TestKernel {
  enum ManagedProviderKind {
    AccessList,
    Merkle
  }

  struct HookFixture {
    OpenTermHooks hooks;
    address market;
    address provider;
  }

  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);
  address internal constant Carol = address(0xCA201);

  function setUp() external {
    vm.warp(1_714_737_030);
  }

  // ========================================================================== //
  //                            Fixture construction                            //
  // ========================================================================== //

  function _singleMember(address account) internal pure returns (address[] memory members) {
    members = new address[](1);
    members[0] = account;
  }

  function _deployAccessList(
    address administrator,
    address[] memory initialMembers
  ) internal returns (AccessListRoleProvider provider) {
    provider = AccessListRoleProvider(
      _deployCode(
        'src/providers/AccessListRoleProvider.sol:AccessListRoleProvider',
        abi.encode(administrator, initialMembers)
      )
    );
  }

  function _deployMerkle(
    address administrator,
    bytes32 root
  ) internal returns (MerkleRoleProvider provider) {
    provider = MerkleRoleProvider(
      _deployCode(
        'src/providers/MerkleRoleProvider.sol:MerkleRoleProvider',
        abi.encode(administrator, root)
      )
    );
  }

  function _deployManaged(
    ManagedProviderKind kind,
    address administrator
  ) internal returns (IManagedRoleProvider provider) {
    if (kind == ManagedProviderKind.AccessList) {
      return IManagedRoleProvider(address(_deployAccessList(administrator, _singleMember(Alice))));
    }
    return IManagedRoleProvider(address(_deployMerkle(administrator, _leaf(Alice))));
  }

  function _mutateManaged(ManagedProviderKind kind, IManagedRoleProvider provider) internal {
    if (kind == ManagedProviderKind.AccessList) {
      AccessListRoleProvider(address(provider)).addMember(Carol);
    } else {
      MerkleRoleProvider(address(provider)).updateRoot(_leaf(Carol));
    }
  }

  function _assertManagedConfiguration(
    ManagedProviderKind kind,
    IManagedRoleProvider provider,
    bool initialConfiguration
  ) internal view {
    if (kind == ManagedProviderKind.AccessList) {
      AccessListRoleProvider accessList = AccessListRoleProvider(address(provider));
      assertTrue(accessList.isMember(Alice), 'initial member');
      assertEq(accessList.isMember(Carol), !initialConfiguration, 'new member');
    } else {
      bytes32 expectedRoot = initialConfiguration ? _leaf(Alice) : _leaf(Carol);
      assertEq(MerkleRoleProvider(address(provider)).root(), expectedRoot, 'root');
    }
  }

  function _deployHooks(address market) internal returns (OpenTermHooks hooks) {
    hooks = OpenTermHooks(
      _deployCode(
        'src/access/OpenTermHooks.sol:OpenTermHooks',
        abi.encode(address(this), bytes(''))
      )
    );

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

  function _newHookFixture(
    address provider,
    uint32 timeToLive,
    uint160 marketSalt
  ) internal returns (HookFixture memory fixture) {
    fixture.market = address(uint160(0xC000) + marketSalt);
    fixture.hooks = _deployHooks(fixture.market);
    fixture.provider = provider;
    fixture.hooks.addRoleProvider(provider, timeToLive);
  }

  function _deposit(HookFixture memory fixture, address lender, bytes memory hooksData) internal {
    MarketState memory state;
    vm.prank(fixture.market);
    fixture.hooks.onDeposit(lender, 1, state, hooksData);
  }

  function _expectDepositDenied(
    HookFixture memory fixture,
    address lender,
    bytes memory hooksData
  ) internal {
    MarketState memory state;
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    vm.prank(fixture.market);
    fixture.hooks.onDeposit(lender, 1, state, hooksData);
  }

  function _queueWithdrawal(
    HookFixture memory fixture,
    address lender,
    bytes memory hooksData
  ) internal {
    MarketState memory state;
    vm.prank(fixture.market);
    fixture.hooks.onQueueWithdrawal(lender, 0, 1, state, hooksData);
  }

  function _merkleHooksData(
    address provider,
    bytes32[] memory proof
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(provider, abi.encode(proof));
  }

  // ========================================================================== //
  //                    Shared managed-provider administration                  //
  // ========================================================================== //

  function test_managedProviderMatrix_RejectsZeroAdministrator() external {
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    _deployAccessList(address(0), new address[](0));

    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    _deployMerkle(address(0), bytes32(0));
  }

  function test_managedProviderMatrix_RequestReplaceAndCancelTransfer() external {
    for (uint8 i; i <= uint8(ManagedProviderKind.Merkle); i++) {
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

  function test_managedProviderMatrix_TransferErrors() external {
    for (uint8 i; i <= uint8(ManagedProviderKind.Merkle); i++) {
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

  function test_managedProviderMatrix_AcceptMovesAuthorityAndPreservesConfiguration() external {
    for (uint8 i; i <= uint8(ManagedProviderKind.Merkle); i++) {
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

  // ========================================================================== //
  //                           Access-list behavior                             //
  // ========================================================================== //

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

    vm.warp(block.timestamp + 1 days);
    assertEq(provider.getCredential(Alice), uint32(getTimestamp()), 'refreshed timestamp');
    provider.removeMember(Alice);
    assertEq(provider.getCredential(Alice), 0, 'removed credential');
    provider.addMember(Alice);
    assertEq(provider.getCredential(Alice), uint32(getTimestamp()), 'restored credential');
  }

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

  function test_accessList_ProviderInstancesKeepIndependentMembership() external {
    AccessListRoleProvider first = _deployAccessList(address(this), _singleMember(Alice));
    AccessListRoleProvider second = _deployAccessList(address(this), _singleMember(Bob));
    first.removeMember(Alice);

    assertFalse(first.isMember(Alice), 'first alice');
    assertFalse(first.isMember(Bob), 'first bob');
    assertFalse(second.isMember(Alice), 'second alice');
    assertTrue(second.isMember(Bob), 'second bob');
  }

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
    vm.warp(block.timestamp + 2);
    _expectDepositDenied(cached, Alice, '');
  }

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

  // ========================================================================== //
  //                              Merkle behavior                               //
  // ========================================================================== //

  function test_merkle_ConstructorAndMembershipSurface() external {
    bytes32 sibling = _leaf(Carol);
    bytes32 root = _hashPair(_leaf(Alice), sibling);
    MerkleRoleProvider provider = _deployMerkle(address(this), root);
    bytes32[] memory proof = new bytes32[](1);
    proof[0] = sibling;

    assertEq(provider.administrator(), address(this), 'administrator');
    assertEq(provider.pendingAdministrator(), address(0), 'pending administrator');
    assertFalse(provider.isPullProvider(), 'push provider');
    assertEq(provider.root(), root, 'root');
    assertEq(provider.getCredential(Alice), 0, 'pull credential');
    assertTrue(provider.isMember(Alice, proof), 'member');
    assertFalse(provider.isMember(Bob, proof), 'non-member');
  }

  function testFuzz_merkleGeneratedProofValidatesOnlyItsAccount(
    address account,
    bytes32[] calldata proof
  ) external {
    vm.assume(proof.length <= 64);
    MerkleRoleProvider provider = _deployMerkle(address(this), _rootFor(account, proof));
    address differentAccount = address(uint160(account) ^ uint160(1));

    assertEq(
      provider.validateCredential(account, abi.encode(proof)),
      uint32(getTimestamp()),
      'member credential'
    );
    assertEq(
      provider.validateCredential(differentAccount, abi.encode(proof)),
      0,
      'different account credential'
    );
  }

  function testFuzz_merkleMalformedCredentialDataFailsClosed(bytes calldata data) external {
    MerkleRoleProvider provider = _deployMerkle(address(this), _leaf(Alice));
    assertEq(provider.validateCredential(Bob, data), 0, 'credential');
  }

  function test_merkle_NonCanonicalCredentialEncodingsFailClosed() external {
    bytes32 sibling = _leaf(Carol);
    MerkleRoleProvider provider = _deployMerkle(address(this), _hashPair(_leaf(Alice), sibling));
    bytes32[] memory proof = new bytes32[](1);
    proof[0] = sibling;

    assertEq(provider.validateCredential(Alice, hex'01'), 0, 'short');
    assertEq(
      provider.validateCredential(Alice, abi.encodePacked(uint256(1), uint256(0))),
      0,
      'offset'
    );
    assertEq(
      provider.validateCredential(Alice, abi.encodePacked(type(uint256).max - 31, uint256(0))),
      0,
      'oversized offset'
    );
    assertEq(
      _deployMerkle(address(this), _leaf(Alice)).validateCredential(
        Alice,
        abi.encodePacked(uint256(0), uint256(0))
      ),
      0,
      'noncanonical empty proof'
    );
    assertEq(
      provider.validateCredential(Alice, abi.encodePacked(abi.encode(proof), bytes32(uint256(1)))),
      0,
      'trailing data'
    );
    assertEq(
      provider.validateCredential(
        Alice,
        abi.encodePacked(uint256(0x20), uint256(2), bytes32(uint256(sibling)))
      ),
      0,
      'oversized proof length'
    );
  }

  function test_merkle_SingleLeafAcceptsCanonicalEmptyProof() external {
    MerkleRoleProvider provider = _deployMerkle(address(this), _leaf(Alice));
    bytes32[] memory proof = new bytes32[](0);

    assertTrue(provider.isMember(Alice, proof), 'member');
    assertEq(
      provider.validateCredential(Alice, abi.encode(proof)),
      uint32(getTimestamp()),
      'credential'
    );
  }

  function test_merkle_RootUpdatesEmitAndRequireAdministrator() external {
    bytes32 oldRoot = _leaf(Alice);
    bytes32 newRoot = _leaf(Bob);
    MerkleRoleProvider provider = _deployMerkle(address(this), oldRoot);

    vm.prank(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.updateRoot(newRoot);

    vm.expectEmit(address(provider));
    emit IMerkleRoleProvider.RootUpdated(address(this), oldRoot, newRoot);
    provider.updateRoot(newRoot);
    assertEq(provider.root(), newRoot, 'root');
  }

  function test_merkleHook_ValidProofAllowsMemberAndRejectsNonmember() external {
    bytes32 sibling = _leaf(Carol);
    bytes32[] memory proof = new bytes32[](1);
    proof[0] = sibling;
    MerkleRoleProvider provider = _deployMerkle(address(this), _hashPair(_leaf(Alice), sibling));
    HookFixture memory fixture = _newHookFixture(address(provider), 0, 4);
    bytes memory hooksData = _merkleHooksData(address(provider), proof);

    _deposit(fixture, Alice, hooksData);
    _expectDepositDenied(fixture, Bob, hooksData);
  }

  function test_merkleHook_RootUpdateRespectsPositiveTtl() external {
    bytes32 sibling = _leaf(Carol);
    bytes32[] memory proof = new bytes32[](1);
    proof[0] = sibling;
    MerkleRoleProvider provider = _deployMerkle(address(this), _hashPair(_leaf(Alice), sibling));
    HookFixture memory fixture = _newHookFixture(address(provider), 1, 5);
    bytes memory hooksData = _merkleHooksData(address(provider), proof);
    _deposit(fixture, Alice, hooksData);

    provider.updateRoot(_hashPair(_leaf(Bob), sibling));
    _deposit(fixture, Alice, hooksData);
    vm.warp(block.timestamp + 2);
    _expectDepositDenied(fixture, Alice, hooksData);
  }

  function test_merkleHook_ZeroTtlUsesSameBlockCredentialThenRequiresFreshProof() external {
    bytes32 sibling = _leaf(Carol);
    bytes32[] memory proof = new bytes32[](1);
    proof[0] = sibling;
    MerkleRoleProvider provider = _deployMerkle(address(this), _hashPair(_leaf(Alice), sibling));
    HookFixture memory fixture = _newHookFixture(address(provider), 0, 6);
    bytes memory hooksData = _merkleHooksData(address(provider), proof);
    _deposit(fixture, Alice, hooksData);

    provider.updateRoot(_hashPair(_leaf(Bob), sibling));
    _deposit(fixture, Alice, '');
    vm.warp(block.timestamp + 1);
    _expectDepositDenied(fixture, Alice, hooksData);
  }

  function test_merkleHook_MalformedDataFailsClosed() external {
    MerkleRoleProvider provider = _deployMerkle(address(this), _leaf(Alice));
    HookFixture memory fixture = _newHookFixture(address(provider), 0, 7);

    _expectDepositDenied(fixture, Alice, abi.encodePacked(address(provider), hex'01'));
    _expectDepositDenied(
      fixture,
      Alice,
      abi.encodePacked(address(provider), uint256(1), uint256(0))
    );
    _expectDepositDenied(
      fixture,
      Alice,
      abi.encodePacked(address(provider), uint256(0x20), uint256(2), bytes32(uint256(1)))
    );
  }

  function test_merkleHook_EmptyProofTracksSingleLeafRootUpdates() external {
    bytes32[] memory emptyProof = new bytes32[](0);
    MerkleRoleProvider provider = _deployMerkle(address(this), _leaf(Alice));
    HookFixture memory fixture = _newHookFixture(address(provider), 0, 8);

    _deposit(fixture, Alice, _merkleHooksData(address(provider), emptyProof));
    provider.updateRoot(_leaf(Bob));
    _deposit(fixture, Bob, _merkleHooksData(address(provider), emptyProof));
  }

  // ========================================================================== //
  //                                Merkle math                                 //
  // ========================================================================== //

  function _leaf(address account) internal pure returns (bytes32) {
    return keccak256(abi.encode(account));
  }

  function _hashPair(bytes32 left, bytes32 right) internal pure returns (bytes32) {
    return
      left < right
        ? keccak256(abi.encodePacked(left, right))
        : keccak256(abi.encodePacked(right, left));
  }

  function _rootFor(
    address account,
    bytes32[] calldata proof
  ) internal pure returns (bytes32 root) {
    root = _leaf(account);
    for (uint256 i; i < proof.length; i++) {
      root = _hashPair(root, proof[i]);
    }
  }
}

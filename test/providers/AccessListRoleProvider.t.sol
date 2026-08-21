// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/providers/AccessListRoleProvider.sol';
import 'src/providers/AccessListRoleProviderFactory.sol';

contract AccessListRoleProviderTest is Test {
  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);
  address internal constant Carol = address(0xCA201);

  AccessListRoleProvider internal provider;

  function setUp() external {
    vm.warp(1_714_737_030);
    address[] memory initialMembers = new address[](1);
    initialMembers[0] = Alice;
    provider = new AccessListRoleProvider(address(this), initialMembers);
  }

  function test_constructor() external view {
    assertEq(provider.administrator(), address(this), 'administrator');
    assertEq(provider.pendingAdministrator(), address(0), 'pending administrator');
    assertTrue(provider.isPullProvider(), 'pull provider');
    assertTrue(provider.isMember(Alice), 'alice member');
    assertEq(provider.getMembersCount(), 1, 'member count');

    address[] memory members = provider.getMembers();
    assertEq(members.length, 1, 'members length');
    assertEq(members[0], Alice, 'members[0]');
  }

  function test_constructor_InvalidAdministrator() external {
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    new AccessListRoleProvider(address(0), new address[](0));
  }

  function test_constructor_InvalidInitialMember() external {
    address[] memory initialMembers = new address[](1);
    vm.expectRevert(IAccessListRoleProvider.InvalidMember.selector);
    new AccessListRoleProvider(address(this), initialMembers);
  }

  function test_constructor_DuplicateInitialMember() external {
    address[] memory initialMembers = new address[](2);
    initialMembers[0] = Alice;
    initialMembers[1] = Alice;
    vm.expectRevert(IAccessListRoleProvider.MemberAlreadyExists.selector);
    new AccessListRoleProvider(address(this), initialMembers);
  }

  function test_getCredential_TracksCurrentMembership() external {
    assertEq(provider.getCredential(Alice), block.timestamp, 'initial timestamp');
    assertEq(provider.getCredential(Bob), 0, 'unlisted timestamp');

    vm.warp(block.timestamp + 1 days);
    assertEq(provider.getCredential(Alice), block.timestamp, 'refreshed timestamp');

    provider.removeMember(Alice);
    assertEq(provider.getCredential(Alice), 0, 'removed timestamp');

    provider.addMember(Alice);
    assertEq(provider.getCredential(Alice), block.timestamp, 're-added timestamp');
  }

  function test_validateCredential_UsesMembership() external view {
    assertEq(provider.validateCredential(Alice, hex'1234'), block.timestamp, 'member');
    assertEq(provider.validateCredential(Bob, hex'1234'), 0, 'non-member');
  }

  function test_providerInstancesKeepSeparateLists() external {
    address[] memory initialMembers = new address[](1);
    initialMembers[0] = Bob;
    AccessListRoleProvider otherProvider = new AccessListRoleProvider(
      address(this),
      initialMembers
    );

    provider.removeMember(Alice);

    assertFalse(provider.isMember(Alice), 'first alice');
    assertFalse(provider.isMember(Bob), 'first bob');
    assertFalse(otherProvider.isMember(Alice), 'second alice');
    assertTrue(otherProvider.isMember(Bob), 'second bob');
  }

  function test_addAndRemoveMember() external {
    vm.expectEmit(address(provider));
    emit IAccessListRoleProvider.MemberAdded(address(this), Bob);
    provider.addMember(Bob);

    assertTrue(provider.isMember(Bob), 'member after add');
    assertEq(provider.getMembersCount(), 2, 'count after add');

    vm.expectEmit(address(provider));
    emit IAccessListRoleProvider.MemberRemoved(address(this), Bob);
    provider.removeMember(Bob);

    assertFalse(provider.isMember(Bob), 'member after remove');
    assertEq(provider.getMembersCount(), 1, 'count after remove');
  }

  function test_addAndRemoveMembers() external {
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
  }

  function test_batchUpdateIsAtomic() external {
    address[] memory accounts = new address[](2);
    accounts[0] = Bob;
    accounts[1] = address(0);

    vm.expectRevert(IAccessListRoleProvider.InvalidMember.selector);
    provider.addMembers(accounts);
    assertFalse(provider.isMember(Bob), 'partial add');
  }

  function test_memberUpdateErrors() external {
    vm.expectRevert(IAccessListRoleProvider.InvalidMember.selector);
    provider.addMember(address(0));

    vm.expectRevert(IAccessListRoleProvider.MemberAlreadyExists.selector);
    provider.addMember(Alice);

    vm.expectRevert(IAccessListRoleProvider.MemberNotFound.selector);
    provider.removeMember(Bob);
  }

  function test_memberUpdatesRequireAdministrator() external {
    vm.startPrank(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.addMember(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);
    vm.stopPrank();
  }

  function test_getMembers_Pagination() external {
    provider.addMember(Bob);
    provider.addMember(Carol);

    address[] memory members = provider.getMembers(1, 3);
    assertEq(members.length, 2, 'page length');
    assertEq(members[0], Bob, 'page[0]');
    assertEq(members[1], Carol, 'page[1]');

    assertEq(provider.getMembers(3, 10).length, 0, 'empty page');
    assertEq(provider.getMembers(10, 20).length, 0, 'past end');

    vm.expectRevert(IAccessListRoleProvider.InvalidPaginationRange.selector);
    provider.getMembers(2, 1);
  }

  function test_requestAdministratorTransfer_ReplacesPending() external {
    vm.expectEmit(address(provider));
    emit IManagedRoleProvider.AdministratorTransferRequested(address(this), address(0), Bob);
    provider.requestAdministratorTransfer(Bob);

    vm.expectEmit(address(provider));
    emit IManagedRoleProvider.AdministratorTransferRequested(address(this), Bob, Carol);
    provider.requestAdministratorTransfer(Carol);

    assertEq(provider.administrator(), address(this), 'administrator');
    assertEq(provider.pendingAdministrator(), Carol, 'pending administrator');
  }

  function test_cancelAdministratorTransfer() external {
    provider.requestAdministratorTransfer(Bob);

    vm.expectEmit(address(provider));
    emit IManagedRoleProvider.AdministratorTransferCancelled(address(this), Bob);
    provider.cancelAdministratorTransfer();

    assertEq(provider.pendingAdministrator(), address(0), 'pending administrator');

    vm.expectRevert(IManagedRoleProvider.NoPendingAdministratorTransfer.selector);
    provider.cancelAdministratorTransfer();
  }

  function test_acceptAdministratorTransfer_PreservesMembership() external {
    provider.requestAdministratorTransfer(Bob);

    vm.prank(Bob);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.addMember(Carol);

    vm.prank(Bob);
    vm.expectEmit(address(provider));
    emit IManagedRoleProvider.AdministratorTransferred(address(this), Bob);
    provider.acceptAdministratorTransfer();

    assertEq(provider.administrator(), Bob, 'administrator');
    assertEq(provider.pendingAdministrator(), address(0), 'pending administrator');
    assertTrue(provider.isMember(Alice), 'membership');

    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Alice);

    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.requestAdministratorTransfer(Carol);

    vm.prank(Bob);
    provider.removeMember(Alice);
    assertFalse(provider.isMember(Alice), 'member removed by new administrator');
  }

  function test_administratorTransferErrors() external {
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

contract AccessListRoleProviderFactoryCaller {
  function createRoleProvider(
    AccessListRoleProviderFactory factory,
    bytes calldata data
  ) external returns (address) {
    return factory.createRoleProvider(data);
  }
}

contract AccessListRoleProviderFactoryTest is Test {
  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);

  AccessListRoleProviderFactory internal factory;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new AccessListRoleProviderFactory();
  }

  function _inputs(
    address administrator,
    bytes32 salt
  ) internal pure returns (AccessListRoleProviderFactoryInputs memory inputs) {
    inputs.administrator = administrator;
    inputs.salt = salt;
    inputs.initialMembers = new address[](1);
    inputs.initialMembers[0] = Alice;
  }

  function test_createAccessListRoleProvider() external {
    AccessListRoleProviderFactoryInputs memory inputs = _inputs(address(this), bytes32('salt'));
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createAccessListRoleProvider(inputs);

    assertEq(actual, expected, 'provider');
    assertEq(AccessListRoleProvider(actual).administrator(), address(this), 'administrator');
    assertTrue(AccessListRoleProvider(actual).isMember(Alice), 'initial member');
  }

  function test_createRoleProvider_GenericInterface() external {
    AccessListRoleProviderFactoryInputs memory inputs = _inputs(Bob, bytes32('generic'));
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(abi.encode(inputs));

    assertEq(actual, expected, 'provider');
    assertEq(AccessListRoleProvider(actual).administrator(), Bob, 'administrator');
  }

  function test_createRoleProvider_GenericInterface_EmptyMembersAndTrailingData() external {
    AccessListRoleProviderFactoryInputs memory inputs;
    inputs.administrator = Bob;
    inputs.salt = bytes32('generic-trailing');
    inputs.initialMembers = new address[](0);
    address expected = factory.computeRoleProviderAddress(address(this), inputs);
    address actual = factory.createRoleProvider(bytes.concat(abi.encode(inputs), hex'deadbeef'));

    assertEq(actual, expected, 'provider');
    assertEq(AccessListRoleProvider(actual).getMembersCount(), 0, 'members');
  }

  function test_createRoleProvider_GenericInterface_MultipleMembers() external {
    AccessListRoleProviderFactoryInputs memory inputs;
    inputs.administrator = Bob;
    inputs.salt = bytes32('generic-multiple');
    inputs.initialMembers = new address[](3);
    inputs.initialMembers[0] = Alice;
    inputs.initialMembers[1] = address(0xBEEF);
    inputs.initialMembers[2] = address(0xCAFE);
    address provider = factory.createRoleProvider(abi.encode(inputs));

    assertEq(AccessListRoleProvider(provider).getMembers(), inputs.initialMembers, 'members');
  }

  function test_deploymentEvent() external {
    AccessListRoleProviderFactoryInputs memory inputs;
    inputs.administrator = address(this);
    inputs.salt = bytes32('event');
    inputs.initialMembers = new address[](0);
    address expected = factory.computeRoleProviderAddress(address(this), inputs);

    vm.expectEmit(address(factory));
    emit IAccessListRoleProviderFactory.AccessListRoleProviderDeployed(
      expected,
      address(this),
      address(this),
      inputs.salt,
      inputs.initialMembers
    );
    factory.createAccessListRoleProvider(inputs);
  }

  function test_saltIsNamespacedByCaller() external {
    AccessListRoleProviderFactoryInputs memory inputs = _inputs(address(this), bytes32('shared'));
    AccessListRoleProviderFactoryCaller caller = new AccessListRoleProviderFactoryCaller();

    address first = factory.createRoleProvider(abi.encode(inputs));
    address second = caller.createRoleProvider(factory, abi.encode(inputs));

    assertNotEq(first, second, 'provider addresses');
    assertEq(
      second,
      factory.computeRoleProviderAddress(address(caller), inputs),
      'namespaced address'
    );
  }

  function test_duplicateDeploymentReverts() external {
    AccessListRoleProviderFactoryInputs memory inputs = _inputs(address(this), bytes32('duplicate'));
    factory.createAccessListRoleProvider(inputs);

    vm.expectRevert(IAccessListRoleProviderFactory.RoleProviderAlreadyExists.selector);
    factory.createAccessListRoleProvider(inputs);
  }

  function test_malformedInitializationReverts() external {
    vm.expectRevert();
    factory.createRoleProvider(hex'1234');

    AccessListRoleProviderFactoryInputs memory inputs = _inputs(Bob, bytes32('malformed'));

    bytes memory dirtyAdministrator = abi.encode(inputs);
    assembly {
      mstore(
        add(dirtyAdministrator, 0x40),
        or(mload(add(dirtyAdministrator, 0x40)), shl(160, 1))
      )
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyAdministrator);

    bytes memory dirtyMember = abi.encode(inputs);
    assembly {
      mstore(add(dirtyMember, 0xc0), or(mload(add(dirtyMember, 0xc0)), shl(160, 1)))
    }
    vm.expectRevert();
    factory.createRoleProvider(dirtyMember);

    bytes memory invalidTupleOffset = abi.encode(inputs);
    assembly {
      mstore(add(invalidTupleOffset, 0x20), 0x40)
    }
    vm.expectRevert();
    factory.createRoleProvider(invalidTupleOffset);

    bytes memory invalidMembersOffset = abi.encode(inputs);
    assembly {
      mstore(add(invalidMembersOffset, 0x60), 0x80)
    }
    vm.expectRevert();
    factory.createRoleProvider(invalidMembersOffset);

    bytes memory missingMember = abi.encode(inputs);
    assembly {
      mstore(missingMember, sub(mload(missingMember), 0x20))
    }
    vm.expectRevert();
    factory.createRoleProvider(missingMember);
  }

  function test_invalidInitializationReverts() external {
    AccessListRoleProviderFactoryInputs memory inputs = _inputs(address(0), bytes32('invalid'));
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    factory.createAccessListRoleProvider(inputs);
  }
}

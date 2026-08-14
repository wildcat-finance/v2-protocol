// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/providers/AccessListRoleProvider.sol';
import 'src/providers/AccessListRoleProviderFactory.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import 'src/access/ProviderStructs.sol';
import 'src/types/LenderStatus.sol';
import 'src/types/RoleProvider.sol';
import { MockOpenTermHooks } from '../shared/mocks/MockOpenTermHooks.sol';
import { MockFixedTermHooks } from '../shared/mocks/MockFixedTermHooks.sol';

contract AccessListRoleProviderIntegrationTest is Test {
  address internal constant Lender = address(0x1EAD);
  address internal constant NewAdministrator = address(0xA11CE);

  AccessListRoleProviderFactory internal factory;
  MockOpenTermHooks internal openTermHooks;
  MockFixedTermHooks internal fixedTermHooks;

  function setUp() external {
    vm.warp(1_714_737_030);
    factory = new AccessListRoleProviderFactory();
    openTermHooks = new MockOpenTermHooks(address(this));
    fixedTermHooks = new MockFixedTermHooks(address(this));
  }

  function _deployAndAttachProvider(
    uint32 timeToLive,
    bytes32 salt
  ) internal returns (AccessListRoleProvider provider) {
    AccessListRoleProviderFactoryInputs memory inputs;
    inputs.administrator = address(this);
    inputs.salt = salt;
    inputs.initialMembers = new address[](1);
    inputs.initialMembers[0] = Lender;

    address providerAddress = factory.computeRoleProviderAddress(address(openTermHooks), inputs);
    openTermHooks.createRoleProvider(address(factory), timeToLive, abi.encode(inputs));
    fixedTermHooks.addRoleProvider(providerAddress, timeToLive);
    provider = AccessListRoleProvider(providerAddress);
  }

  function _validateOnBothHooks(
    bool expectedValid,
    bool expectedUpdate
  ) internal {
    (bool valid, bool wasUpdated) = openTermHooks.tryValidateAccess(Lender, '');
    assertEq(valid, expectedValid, 'open valid');
    assertEq(wasUpdated, expectedUpdate, 'open updated');

    (valid, wasUpdated) = fixedTermHooks.tryValidateAccess(Lender, '');
    assertEq(valid, expectedValid, 'fixed valid');
    assertEq(wasUpdated, expectedUpdate, 'fixed updated');
  }

  function test_factoryCalledByHookAssignsIntendedAdministrator() external {
    AccessListRoleProvider provider = _deployAndAttachProvider(0, bytes32('administrator'));

    assertEq(provider.administrator(), address(this), 'provider administrator');
    assertTrue(provider.isMember(Lender), 'member');
    assertFalse(openTermHooks.getRoleProvider(address(provider)).isNull(), 'open attachment');
    assertFalse(fixedTermHooks.getRoleProvider(address(provider)).isNull(), 'fixed attachment');
  }

  function test_hookConstructorCreatesAndAttachesProvider() external {
    AccessListRoleProviderFactoryInputs memory providerInputs;
    providerInputs.administrator = address(this);
    providerInputs.salt = bytes32('constructor');
    providerInputs.initialMembers = new address[](1);
    providerInputs.initialMembers[0] = Lender;

    NameAndProviderInputs memory hookInputs;
    hookInputs.roleProviderFactory = address(factory);
    hookInputs.newProviderInputs = new CreateProviderInputs[](1);
    hookInputs.newProviderInputs[0] = CreateProviderInputs({
      timeToLive: 0,
      providerFactoryCalldata: abi.encode(providerInputs)
    });

    OpenTermHooks hooks = new OpenTermHooks(address(this), abi.encode(hookInputs));
    address expectedProvider = factory.computeRoleProviderAddress(address(hooks), providerInputs);

    RoleProvider[] memory providers = hooks.getPullProviders();
    assertEq(providers.length, 1, 'provider count');
    assertEq(providers[0].providerAddress(), expectedProvider, 'provider address');
    assertEq(
      AccessListRoleProvider(expectedProvider).administrator(),
      address(this),
      'provider administrator'
    );
    assertTrue(AccessListRoleProvider(expectedProvider).isMember(Lender), 'initial member');
  }

  function test_zeroTtlRemovalAppliesToBothHooksInSameBlock() external {
    AccessListRoleProvider provider = _deployAndAttachProvider(0, bytes32('zero ttl'));
    _validateOnBothHooks(true, true);

    provider.removeMember(Lender);

    LenderStatus memory openStatus = openTermHooks.getLenderStatus(Lender);
    LenderStatus memory fixedStatus = fixedTermHooks.getLenderStatus(Lender);
    assertEq(openStatus.lastProvider, address(0), 'open view status');
    assertEq(fixedStatus.lastProvider, address(0), 'fixed view status');
    _validateOnBothHooks(false, true);

    vm.warp(block.timestamp + 1);
    _validateOnBothHooks(false, false);
  }

  function test_positiveTtlDelaysRemovalUntilCacheExpires() external {
    uint32 timeToLive = 1 days;
    AccessListRoleProvider provider = _deployAndAttachProvider(
      timeToLive,
      bytes32('positive ttl')
    );
    _validateOnBothHooks(true, true);

    provider.removeMember(Lender);
    _validateOnBothHooks(true, false);

    vm.warp(block.timestamp + timeToLive + 1);
    _validateOnBothHooks(false, true);
  }

  function test_providerGrantDoesNotClearHookLocalBlock() external {
    _deployAndAttachProvider(0, bytes32('local block'));
    openTermHooks.blockFromDeposits(Lender);

    (bool valid, bool wasUpdated) = openTermHooks.tryValidateAccess(Lender, '');
    assertTrue(valid, 'credential valid');
    assertTrue(wasUpdated, 'credential updated');

    LenderStatus memory status = openTermHooks.getPreviousLenderStatus(Lender);
    assertTrue(status.isBlockedFromDeposits, 'open local block');
    assertFalse(
      fixedTermHooks.getPreviousLenderStatus(Lender).isBlockedFromDeposits,
      'fixed local block'
    );
  }

  function test_providerTransferPreservesMembershipAndAttachments() external {
    AccessListRoleProvider provider = _deployAndAttachProvider(0, bytes32('transfer'));
    RoleProvider openAttachment = openTermHooks.getRoleProvider(address(provider));
    RoleProvider fixedAttachment = fixedTermHooks.getRoleProvider(address(provider));

    provider.requestAdministratorTransfer(NewAdministrator);
    vm.prank(NewAdministrator);
    provider.acceptAdministratorTransfer();

    assertTrue(provider.isMember(Lender), 'member');
    assertEq(
      RoleProvider.unwrap(openTermHooks.getRoleProvider(address(provider))),
      RoleProvider.unwrap(openAttachment),
      'open attachment'
    );
    assertEq(
      RoleProvider.unwrap(fixedTermHooks.getRoleProvider(address(provider))),
      RoleProvider.unwrap(fixedAttachment),
      'fixed attachment'
    );

    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    provider.removeMember(Lender);

    vm.prank(NewAdministrator);
    provider.removeMember(Lender);
    assertFalse(provider.isMember(Lender), 'member removed');
  }
}

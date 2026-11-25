// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProvider.t
//  \ ^ /   Policy evaluation, fail-closed forbidden keys, and hooks gating.
//    V
//
//  FIXTURE
//  setUp()
//
//  CONSTRUCTION AND METADATA
//  test_constructor_InvalidInputsRevert()
//  test_metadata_GettersMatchDeployment()
//
//  POLICY AND CREDENTIALS
//  test_credentials_RequireAuthorizedHooksAndPolicy(bytes)
//  test_policy_ExpiredForbiddenAttributeStaysBlocked()
//  test_policy_RequiredExpiryAndReissue()
//  test_credentials_TimestampDoesNotWrap()
// ═════

import { Test } from 'forge-std/Test.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { IKYCRegistry, KYCAttributeInput } from 'src/providers/IKYCRegistry.sol';
import { IKYCRoleProvider } from 'src/providers/IKYCRoleProvider.sol';
import { IKYCRoleProviderFactory } from 'src/providers/IKYCRoleProviderFactory.sol';
import { KYCRegistry } from 'src/providers/KYCRegistry.sol';
import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';
import { KYCRoleProviderFactory } from 'src/providers/KYCRoleProviderFactory.sol';

// ┌─ MockHooksFactoryForProvider ──────────────────────────────────────────────
contract MockHooksFactoryForProvider {
  mapping(address => bool) public isHooksInstance;
  mapping(address => address[]) internal _markets;

  function registerHooks(address hooks) external {
    isHooksInstance[hooks] = true;
  }

  function addMarket(address hooks, address market) external {
    _markets[hooks].push(market);
  }

  function getMarketsForHooksInstanceCount(address hooks) external view returns (uint256) {
    return _markets[hooks].length;
  }

  function getMarketsForHooksInstance(
    address hooks,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory arr)
  {
    address[] storage list = _markets[hooks];
    if (end > list.length) end = list.length;
    arr = new address[](end - start);
    for (uint256 i; i < arr.length; ++i) {
      arr[i] = list[start + i];
    }
  }
}

// ┌─ MockHooksStub ────────────────────────────────────────────────────────────
contract MockHooksStub {
  address public borrower;

  constructor(address borrower_) {
    borrower = borrower_;
  }
}

// ┌─ KYCRoleProviderTest ──────────────────────────────────────────────────────
contract KYCRoleProviderTest is Test {
  address internal constant Admin = address(0xAD1);
  address internal constant Keeper = address(0xBEEF);
  address internal constant Borrower = address(0xB01);
  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);

  bytes32 internal constant AttrVerified = bytes32(uint256(1));
  bytes32 internal constant AttrAccredited = bytes32(uint256(2));
  bytes32 internal constant AttrUS = bytes32(uint256(3));

  uint40 internal constant Start = 1_760_000_000;

  KYCRegistry internal registry;
  KYCRoleProviderFactory internal factory;
  MockHooksFactoryForProvider internal hooksFactory;
  MockHooksStub internal authorizedHooks;
  MockHooksStub internal unauthorizedHooks;
  KYCRoleProvider internal nonUSProvider;
  KYCRoleProvider internal usAccreditedProvider;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(Start);
    address[] memory keepers = new address[](1);
    keepers[0] = Keeper;
    registry = new KYCRegistry(Admin, keepers);

    hooksFactory = new MockHooksFactoryForProvider();
    address[] memory factories = new address[](1);
    factories[0] = address(hooksFactory);
    factory = new KYCRoleProviderFactory(Admin, registry, factories);

    authorizedHooks = new MockHooksStub(Borrower);
    unauthorizedHooks = new MockHooksStub(Borrower);
    hooksFactory.registerHooks(address(authorizedHooks));
    hooksFactory.registerHooks(address(unauthorizedHooks));

    // Soma emits positive flags only (`Institutional`, `Accredited`, `US`); Non-US requires verified + !US.
    bytes32[] memory nonUSReq = new bytes32[](1);
    nonUSReq[0] = AttrVerified;
    bytes32[] memory nonUSForb = new bytes32[](1);
    nonUSForb[0] = AttrUS;

    bytes32[] memory usAccReq = new bytes32[](3);
    usAccReq[0] = AttrVerified;
    usAccReq[1] = AttrAccredited;
    usAccReq[2] = AttrUS;
    bytes32[] memory emptyForb = new bytes32[](0);

    vm.startPrank(Admin);
    nonUSProvider = KYCRoleProvider(factory.deployRoleProvider('Non-US KYC', nonUSReq, nonUSForb));
    usAccreditedProvider = KYCRoleProvider(factory.deployRoleProvider('US Accredited', usAccReq, emptyForb));
    factory.setBorrowerAllowance(Borrower, 2);
    vm.stopPrank();

    vm.prank(Borrower);
    factory.authorizeHooks(address(hooksFactory), address(authorizedHooks), 1);
  }

  // ░░▒▒▓▓██ [ CONSTRUCTION AND METADATA ] ────────────────────────────────────

  // ┌─ test_constructor_InvalidInputsRevert ─────
  function test_constructor_InvalidInputsRevert() external {
    bytes32[] memory req = new bytes32[](1);
    req[0] = AttrVerified;
    bytes32[] memory empty = new bytes32[](0);

    vm.expectRevert(IKYCRoleProvider.InvalidRegistry.selector);
    new KYCRoleProvider(IKYCRegistry(address(0)), factory, 'x', req, empty);

    vm.expectRevert(IKYCRoleProvider.InvalidFactory.selector);
    new KYCRoleProvider(registry, IKYCRoleProviderFactory(address(0)), 'x', req, empty);

    vm.expectRevert(IKYCRoleProvider.EmptyRequiredAttributes.selector);
    new KYCRoleProvider(registry, factory, 'x', empty, empty);
  }

  // ┌─ test_metadata_GettersMatchDeployment ─────
  function test_metadata_GettersMatchDeployment() external view {
    assertTrue(nonUSProvider.isPullProvider());
    assertEq(address(nonUSProvider.registry()), address(registry));
    assertEq(address(nonUSProvider.factory()), address(factory));
    assertEq(nonUSProvider.name(), 'Non-US KYC');

    bytes32[] memory req = nonUSProvider.requiredAttributes();
    bytes32[] memory forb = nonUSProvider.forbiddenAttributes();
    assertEq(req.length, 1);
    assertEq(req[0], AttrVerified);
    assertEq(forb.length, 1);
    assertEq(forb[0], AttrUS);
  }

  // ░░▒▒▓▓██ [ POLICY AND CREDENTIALS ] ───────────────────────────────────────

  // ┌─ test_credentials_RequireAuthorizedHooksAndPolicy ─────
  function test_credentials_RequireAuthorizedHooksAndPolicy(bytes calldata payload) external {
    vm.prank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrVerified, Start, 0, 1));

    assertTrue(nonUSProvider.meetsPolicy(Alice));
    assertFalse(usAccreditedProvider.meetsPolicy(Alice));

    // direct EOA or unauthorized hooks instance gets zero even when the wallet meets policy.
    assertEq(nonUSProvider.getCredential(Alice), 0);
    vm.prank(address(unauthorizedHooks));
    assertEq(nonUSProvider.getCredential(Alice), 0);
    vm.prank(address(unauthorizedHooks));
    assertEq(nonUSProvider.validateCredential(Alice, payload), 0);

    // authorized hooks instance gets current block timestamp for eligible wallets.
    vm.warp(Start + 5 days);
    vm.startPrank(address(authorizedHooks));
    assertEq(IRoleProvider(nonUSProvider).getCredential(Alice), Start + 5 days);
    assertEq(IRoleProvider(nonUSProvider).validateCredential(Alice, payload), Start + 5 days);
    assertEq(IRoleProvider(usAccreditedProvider).getCredential(Alice), 0);
    vm.stopPrank();
  }

  // ┌─ test_policy_ExpiredForbiddenAttributeStaysBlocked ─────
  function test_policy_ExpiredForbiddenAttributeStaysBlocked() external {
    vm.startPrank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrVerified, Start, Start + 365 days, 1));
    registry.setAttribute(KYCAttributeInput(Alice, AttrUS, Start, Start + 30 days, 2));
    vm.stopPrank();

    assertFalse(nonUSProvider.meetsPolicy(Alice));

    // US flag expires before base verification; Non-US policy stays blocked until keeper removes it.
    vm.warp(Start + 31 days);
    assertFalse(nonUSProvider.meetsPolicy(Alice));
    vm.prank(address(authorizedHooks));
    assertEq(nonUSProvider.getCredential(Alice), 0);

    vm.prank(Keeper);
    registry.removeAttribute(Alice, AttrUS);
    assertTrue(nonUSProvider.meetsPolicy(Alice));
    vm.prank(address(authorizedHooks));
    assertEq(nonUSProvider.getCredential(Alice), Start + 31 days);
  }

  // ┌─ test_policy_RequiredExpiryAndReissue ─────
  function test_policy_RequiredExpiryAndReissue() external {
    vm.startPrank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrVerified, Start, Start + 365 days, 1));
    registry.setAttribute(KYCAttributeInput(Alice, AttrUS, Start, 0, 2));
    registry.setAttribute(KYCAttributeInput(Alice, AttrAccredited, Start, Start + 90 days, 2));
    vm.stopPrank();

    vm.warp(Start + 90 days);
    vm.prank(address(authorizedHooks));
    assertEq(usAccreditedProvider.getCredential(Alice), Start + 90 days);

    vm.warp(Start + 90 days + 1);
    vm.prank(address(authorizedHooks));
    assertEq(usAccreditedProvider.getCredential(Alice), 0);

    // keeper re-issues accredited attribute -> credentials resume immediately.
    vm.prank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrAccredited, Start + 90 days + 1, Start + 180 days, 2));
    vm.prank(address(authorizedHooks));
    assertEq(usAccreditedProvider.getCredential(Alice), Start + 90 days + 1);
  }

  // ┌─ test_credentials_TimestampDoesNotWrap ─────
  function test_credentials_TimestampDoesNotWrap() external {
    vm.prank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrVerified, Start, 0, 1));

    vm.warp(type(uint32).max);
    vm.prank(address(authorizedHooks));
    assertEq(nonUSProvider.getCredential(Alice), type(uint32).max);

    vm.warp(uint256(type(uint32).max) + 1);
    vm.prank(address(authorizedHooks));
    vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
    nonUSProvider.getCredential(Alice);

    // ineligible wallet and unauthorized hooks still return zero cleanly past uint32 max.
    vm.prank(address(authorizedHooks));
    assertEq(nonUSProvider.getCredential(Bob), 0);
    vm.prank(address(unauthorizedHooks));
    assertEq(nonUSProvider.getCredential(Alice), 0);
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderFactory.t
//  \ ^ /   Policy catalog, borrower allowances, hooks auth, and slot reclamation.
//    V
//
//  FIXTURE
//  setUp()
//  _deployPolicy(...)
//
//  CONFIGURATION AND POLICY CATALOG
//  test_constructor_InvalidInputsRevert()
//  test_deployRoleProvider_ValidationAndDeduplication()
//  test_setProviderAttachmentEnabled_GatesOnlyNewAttachments()
//  test_setHooksFactory_RemovalIsNotRetroactive()
//
//  ALLOWANCES AND HOOKS AUTHORIZATION
//  test_authorizeHooks_ForwardAllowanceAndLiveOverflowFreeze()
//  test_createRoleProvider_OneTxAttachAndZeroSlotSecondPolicy()
//  test_reduceUnusedSlots_RefundsAndClearsEmptyHooks()
//  test_hooksTransfer_CannotSpendPreviousBorrowersAllowance()
//  test_migrateHooksBorrower_SelfServiceAndAdminWithActiveSlots()
//
//  CLOSED MARKET RECLAMATION
//  test_firstAuthorization_ReclaimsPreClosedMarkets()
//  test_reclaimClosedMarket_PerMarketWithoutHookRetirement()
//  test_reclaimClosedMarket_CommitsProjectedClosureViaUpdateState()
//  test_reclaimClosedMarket_GuardsAndToggle()
//  test_inlineReclaim_AuthorizeAndAttachAtCap()
//  test_batchReclaimAndFourArgAuthorizeHooks()
//  test_slotConservation_MultiBorrowerFuzz(uint8[24],uint8[24])
// ═════

import { Test } from 'forge-std/Test.sol';
import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import {
  ClosedMarketClaim,
  HooksAuthorization,
  IKYCRoleProviderFactory,
  KYCRoleProviderAttachInputs
} from 'src/providers/IKYCRoleProviderFactory.sol';
import { KYCRegistry } from 'src/providers/KYCRegistry.sol';
import { KYCRoleProviderFactory } from 'src/providers/KYCRoleProviderFactory.sol';

// ┌─ MockMarketForFactory ─────────────────────────────────────────────────────
contract MockMarketForFactory {
  bool public isClosed;
  bool public projectedClosure;
  uint256 public updateStateCalls;

  function close() external {
    isClosed = true;
  }

  function setProjectedClosure(bool projected) external {
    projectedClosure = projected;
  }

  function updateState() external {
    ++updateStateCalls;
    if (projectedClosure) {
      isClosed = true;
      projectedClosure = false;
    }
  }
}

// ┌─ MockHooksForFactory ──────────────────────────────────────────────────────
contract MockHooksForFactory {
  address public borrower;

  constructor(address borrower_) {
    borrower = borrower_;
  }

  function setBorrower(address newBorrower) external {
    borrower = newBorrower;
  }

  function callCreateRoleProvider(
    KYCRoleProviderFactory kycFactory,
    bytes calldata data
  )
    external
    returns (address)
  {
    return kycFactory.createRoleProvider(data);
  }
}

// ┌─ MockHooksFactoryForEntitlements ──────────────────────────────────────────
contract MockHooksFactoryForEntitlements {
  mapping(address => bool) public isHooksInstance;
  mapping(address => address[]) internal _markets;

  function createHooks(address borrower) external returns (MockHooksForFactory hooks) {
    hooks = new MockHooksForFactory(borrower);
    isHooksInstance[address(hooks)] = true;
  }

  function createMarket(address hooks) external returns (MockMarketForFactory market) {
    market = new MockMarketForFactory();
    _markets[hooks].push(address(market));
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

// ┌─ KYCRoleProviderFactoryTest ───────────────────────────────────────────────
contract KYCRoleProviderFactoryTest is Test {
  address internal constant Admin = address(0xAD1);
  address internal constant Keeper = address(0xBEEF);
  address internal constant BorrowerA = address(0xB0A);
  address internal constant BorrowerB = address(0xB0B);
  address internal constant Stranger = address(0xDEAD);

  bytes32 internal constant AttrVerified = bytes32(uint256(1));
  bytes32 internal constant AttrAccredited = bytes32(uint256(2));
  bytes32 internal constant AttrUS = bytes32(uint256(3));

  KYCRegistry internal registry;
  KYCRoleProviderFactory internal factory;
  MockHooksFactoryForEntitlements internal hooksFactory;
  MockHooksFactoryForEntitlements internal hooksFactoryV25;
  address internal providerA;
  address internal providerB;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    address[] memory keepers = new address[](1);
    keepers[0] = Keeper;
    registry = new KYCRegistry(Admin, keepers);

    hooksFactory = new MockHooksFactoryForEntitlements();
    hooksFactoryV25 = new MockHooksFactoryForEntitlements();
    address[] memory factories = new address[](2);
    factories[0] = address(hooksFactory);
    factories[1] = address(hooksFactoryV25);
    factory = new KYCRoleProviderFactory(Admin, registry, factories);

    providerA = _deployPolicy('Non-US', AttrVerified, AttrUS);
    providerB = _deployPolicy('Verified', AttrVerified, bytes32(0));
  }

  // ┌─ _deployPolicy ─────
  function _deployPolicy(string memory label, bytes32 reqKey, bytes32 forbKey) internal returns (address) {
    bytes32[] memory req = new bytes32[](1);
    req[0] = reqKey;
    bytes32[] memory forb = forbKey == bytes32(0) ? new bytes32[](0) : new bytes32[](1);
    if (forbKey != bytes32(0)) forb[0] = forbKey;

    vm.prank(Admin);
    return factory.deployRoleProvider(label, req, forb);
  }

  // ░░▒▒▓▓██ [ CONFIGURATION AND POLICY CATALOG ] ─────────────────────────────

  // ┌─ test_constructor_InvalidInputsRevert ─────
  function test_constructor_InvalidInputsRevert() external {
    address[] memory empty = new address[](0);
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    new KYCRoleProviderFactory(address(0), registry, empty);

    vm.expectRevert(IKYCRoleProviderFactory.InvalidRegistry.selector);
    new KYCRoleProviderFactory(Admin, KYCRegistry(address(0)), empty);

    address[] memory bad = new address[](1);
    bad[0] = address(0);
    vm.expectRevert(IKYCRoleProviderFactory.InvalidHooksFactory.selector);
    new KYCRoleProviderFactory(Admin, registry, bad);

    assertTrue(factory.slotReclamationEnabled());
    assertTrue(factory.isApprovedHooksFactory(address(hooksFactory)));
    assertEq(factory.getApprovedHooksFactories().length, 2);
  }

  // ┌─ test_deployRoleProvider_ValidationAndDeduplication ─────
  function test_deployRoleProvider_ValidationAndDeduplication() external {
    bytes32[] memory empty = new bytes32[](0);
    bytes32[] memory one = new bytes32[](1);
    one[0] = AttrVerified;

    vm.prank(BorrowerA);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    factory.deployRoleProvider('x', one, empty);

    vm.startPrank(Admin);
    vm.expectRevert(IKYCRoleProviderFactory.InvalidPolicy.selector);
    factory.deployRoleProvider('empty', empty, empty);

    bytes32[] memory zeroReq = new bytes32[](1);
    zeroReq[0] = bytes32(0);
    vm.expectRevert(IKYCRoleProviderFactory.InvalidPolicy.selector);
    factory.deployRoleProvider('zero', zeroReq, empty);

    bytes32[] memory unsorted = new bytes32[](2);
    unsorted[0] = AttrUS;
    unsorted[1] = AttrAccredited;
    vm.expectRevert(IKYCRoleProviderFactory.InvalidPolicy.selector);
    factory.deployRoleProvider('unsorted', unsorted, empty);

    bytes32[] memory dup = new bytes32[](2);
    dup[0] = AttrVerified;
    dup[1] = AttrVerified;
    vm.expectRevert(IKYCRoleProviderFactory.InvalidPolicy.selector);
    factory.deployRoleProvider('dup', dup, empty);

    bytes32[] memory overlap = new bytes32[](1);
    overlap[0] = AttrVerified;
    vm.expectRevert(IKYCRoleProviderFactory.InvalidPolicy.selector);
    factory.deployRoleProvider('overlap', one, overlap);

    // identical policy with a different name still collides on policyHash.
    vm.expectRevert(IKYCRoleProviderFactory.PolicyAlreadyDeployed.selector);
    factory.deployRoleProvider('Renamed Duplicate', one, empty);
    vm.stopPrank();

    assertEq(factory.getRoleProvidersCount(), 2);
    assertEq(factory.getRoleProviders().length, 2);
    assertEq(factory.getRoleProviders(0, 1)[0], providerA);
    assertEq(factory.getRoleProviders(1, 5)[0], providerB);
    assertEq(factory.getRoleProviders(3, 5).length, 0);
    assertTrue(factory.isRoleProvider(providerA));

    vm.expectRevert(IKYCRoleProviderFactory.InvalidPaginationRange.selector);
    factory.getRoleProviders(2, 1);
  }

  // ┌─ test_setProviderAttachmentEnabled_GatesOnlyNewAttachments ─────
  function test_setProviderAttachmentEnabled_GatesOnlyNewAttachments() external {
    MockHooksForFactory hooks = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(hooks));

    vm.startPrank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 2);
    vm.expectRevert(IKYCRoleProviderFactory.UnknownRoleProvider.selector);
    factory.setProviderAttachmentEnabled(Stranger, false);
    factory.setProviderAttachmentEnabled(providerA, false);
    vm.stopPrank();

    assertFalse(factory.isProviderAttachmentEnabled(providerA));

    KYCRoleProviderAttachInputs memory inputs = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerA,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });

    vm.expectRevert(IKYCRoleProviderFactory.ProviderAttachmentDisabled.selector);
    hooks.callCreateRoleProvider(factory, abi.encode(inputs));

    // re-enable -> succeeds; disabling again afterward leaves live authorized hooks intact.
    vm.prank(Admin);
    factory.setProviderAttachmentEnabled(providerA, true);
    assertEq(hooks.callCreateRoleProvider(factory, abi.encode(inputs)), providerA);

    vm.prank(Admin);
    factory.setProviderAttachmentEnabled(providerA, false);
    assertTrue(factory.isHooksAuthorized(address(hooks)));
  }

  // ┌─ test_setHooksFactory_RemovalIsNotRetroactive ─────
  function test_setHooksFactory_RemovalIsNotRetroactive() external {
    MockHooksForFactory hooks1 = hooksFactory.createHooks(BorrowerA);
    MockHooksForFactory hooks2 = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(hooks1));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 3);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 1);

    vm.prank(Admin);
    factory.setHooksFactory(address(hooksFactory), false);
    assertFalse(factory.isApprovedHooksFactory(address(hooksFactory)));

    // existing authorized hook stays live and can attach a 2nd provider at delta == 0.
    assertTrue(factory.isHooksAuthorized(address(hooks1)));
    KYCRoleProviderAttachInputs memory attachSecond = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerB,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    assertEq(hooks1.callCreateRoleProvider(factory, abi.encode(attachSecond)), providerB);

    // new authorizations and slot expansions on the removed factory revert.
    vm.startPrank(BorrowerA);
    vm.expectRevert(IKYCRoleProviderFactory.InvalidHooksFactory.selector);
    factory.authorizeHooks(address(hooksFactory), address(hooks2), 1);

    vm.expectRevert(IKYCRoleProviderFactory.InvalidHooksFactory.selector);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 2);
    vm.stopPrank();
  }

  // ░░▒▒▓▓██ [ ALLOWANCES AND HOOKS AUTHORIZATION ] ───────────────────────────

  // ┌─ test_authorizeHooks_ForwardAllowanceAndLiveOverflowFreeze ─────
  function test_authorizeHooks_ForwardAllowanceAndLiveOverflowFreeze() external {
    MockHooksForFactory hooks1 = hooksFactory.createHooks(BorrowerA);
    MockHooksForFactory hooks2 = hooksFactory.createHooks(BorrowerA);
    MockHooksForFactory fakeHooks = new MockHooksForFactory(BorrowerA);

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 2);

    vm.startPrank(BorrowerA);
    vm.expectRevert(IKYCRoleProviderFactory.TargetCannotBeZero.selector);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 0);

    vm.expectRevert(IKYCRoleProviderFactory.InvalidHooksInstance.selector);
    factory.authorizeHooks(address(hooksFactory), address(fakeHooks), 1);

    vm.expectRevert(IKYCRoleProviderFactory.InsufficientAllowance.selector);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 3);

    // pre-allocate 1 slot on hooks1, deploy 1 market -> authorized.
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 1);
    vm.stopPrank();

    hooksFactory.createMarket(address(hooks1));
    assertTrue(factory.isHooksAuthorized(address(hooks1)));
    assertEq(factory.usedSlots(BorrowerA), 1);

    // sneaking a 2nd unapproved market onto hooks1 immediately freezes authorization.
    hooksFactory.createMarket(address(hooks1));
    assertFalse(factory.isHooksAuthorized(address(hooks1)));

    vm.startPrank(BorrowerA);
    vm.expectRevert(IKYCRoleProviderFactory.TargetBelowCurrentMarkets.selector);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 1);

    // paying for the 2nd market restores authorization immediately.
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 2);
    vm.stopPrank();

    assertTrue(factory.isHooksAuthorized(address(hooks1)));
    assertEq(factory.usedSlots(BorrowerA), 2);

    // lowering borrowerAllowance below usedSlots never breaks live hooks, only blocks new slots.
    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 1);
    assertTrue(factory.isHooksAuthorized(address(hooks1)));

    vm.prank(BorrowerA);
    vm.expectRevert(IKYCRoleProviderFactory.InsufficientAllowance.selector);
    factory.authorizeHooks(address(hooksFactory), address(hooks2), 1);
  }

  // ┌─ test_createRoleProvider_OneTxAttachAndZeroSlotSecondPolicy ─────
  function test_createRoleProvider_OneTxAttachAndZeroSlotSecondPolicy() external {
    MockHooksForFactory hooks = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(hooks));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 1);

    KYCRoleProviderAttachInputs memory first = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerA,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    assertEq(hooks.callCreateRoleProvider(factory, abi.encode(first)), providerA);
    assertEq(factory.usedSlots(BorrowerA), 1);
    assertEq(factory.getBorrowerAuthorizedHooksCount(BorrowerA), 1);
    assertEq(factory.getBorrowerAuthorizedHooks(BorrowerA, 0, 5)[0], address(hooks));

    // attaching a 2nd policy to the same hooks instance consumes 0 slots and succeeds even at cap.
    KYCRoleProviderAttachInputs memory second = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerB,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    assertEq(hooks.callCreateRoleProvider(factory, abi.encode(second)), providerB);
    assertEq(factory.usedSlots(BorrowerA), 1);

    // factory mismatch or unknown provider reverts.
    KYCRoleProviderAttachInputs memory wrongFactory = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactoryV25),
      provider: providerB,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.expectRevert(IKYCRoleProviderFactory.HooksFactoryMismatch.selector);
    hooks.callCreateRoleProvider(factory, abi.encode(wrongFactory));

    KYCRoleProviderAttachInputs memory unknown = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: Stranger,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.expectRevert(IKYCRoleProviderFactory.UnknownRoleProvider.selector);
    hooks.callCreateRoleProvider(factory, abi.encode(unknown));
  }

  // ┌─ test_reduceUnusedSlots_RefundsAndClearsEmptyHooks ─────
  function test_reduceUnusedSlots_RefundsAndClearsEmptyHooks() external {
    MockHooksForFactory emptyHooks = hooksFactory.createHooks(BorrowerA);
    MockHooksForFactory activeHooks = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(activeHooks));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 5);

    vm.startPrank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(emptyHooks), 2);
    factory.authorizeHooks(address(hooksFactory), address(activeHooks), 3);
    assertEq(factory.usedSlots(BorrowerA), 5);

    // cannot reduce below deployed markets (1) or equal/above approved count (3).
    vm.expectRevert(IKYCRoleProviderFactory.InvalidSlotReduction.selector);
    factory.reduceUnusedSlots(address(activeHooks), 0);
    vm.expectRevert(IKYCRoleProviderFactory.InvalidSlotReduction.selector);
    factory.reduceUnusedSlots(address(activeHooks), 3);

    factory.reduceUnusedSlots(address(activeHooks), 1);
    assertEq(factory.usedSlots(BorrowerA), 3);
    assertTrue(factory.isHooksAuthorized(address(activeHooks)));

    // reducing an empty hooks instance to 0 refunds all slots and removes its record cleanly.
    factory.reduceUnusedSlots(address(emptyHooks), 0);
    vm.stopPrank();

    assertEq(factory.usedSlots(BorrowerA), 1);
    assertFalse(factory.isHooksAuthorized(address(emptyHooks)));
    assertEq(factory.getBorrowerAuthorizedHooksCount(BorrowerA), 1);

    // can cleanly re-authorize emptyHooks later.
    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(emptyHooks), 1);
    assertEq(factory.usedSlots(BorrowerA), 2);
    assertTrue(factory.isHooksAuthorized(address(emptyHooks)));
  }

  // ┌─ test_hooksTransfer_CannotSpendPreviousBorrowersAllowance ─────
  function test_hooksTransfer_CannotSpendPreviousBorrowersAllowance() external {
    MockHooksForFactory hooks = hooksFactoryV25.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactoryV25.createMarket(address(hooks));

    vm.startPrank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 3);
    factory.setBorrowerAllowance(BorrowerB, 3);
    vm.stopPrank();

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactoryV25), address(hooks), 1);

    // simulate v2.5 hooks administrator transfer from BorrowerA -> BorrowerB.
    hooks.setBorrower(BorrowerB);

    // live market still works, and attaching another policy at delta == 0 still works.
    assertTrue(factory.isHooksAuthorized(address(hooks)));
    KYCRoleProviderAttachInputs memory attach = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactoryV25),
      provider: providerB,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    assertEq(hooks.callCreateRoleProvider(factory, abi.encode(attach)), providerB);

    // BorrowerB cannot expand approvedMarketCount using BorrowerA's allowance.
    hooksFactoryV25.createMarket(address(hooks));
    KYCRoleProviderAttachInputs memory expand = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactoryV25),
      provider: providerB,
      targetApprovedMarketCount: 2,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.expectRevert(IKYCRoleProviderFactory.HooksBorrowerMismatch.selector);
    hooks.callCreateRoleProvider(factory, abi.encode(expand));

    // closing m1 before migration credits BorrowerA (the pinned allowance payer), never BorrowerB.
    m1.close();
    factory.reclaimClosedMarket(address(hooks), 0);
    assertEq(factory.usedSlots(BorrowerA), 0);
    assertEq(factory.usedSlots(BorrowerB), 0);

    // BorrowerB self-migrates hooks borrower (0 active slots moved), unblocking expansion on BorrowerB's allowance.
    vm.prank(BorrowerB);
    factory.migrateHooksBorrower(address(hooks));
    assertEq(factory.getHooksAuthorization(address(hooks)).borrower, BorrowerB);
    assertEq(factory.getBorrowerAuthorizedHooksCount(BorrowerA), 0);
    assertEq(factory.getBorrowerAuthorizedHooksCount(BorrowerB), 1);

    assertEq(hooks.callCreateRoleProvider(factory, abi.encode(expand)), providerB);
    assertEq(factory.usedSlots(BorrowerA), 0);
    assertEq(factory.usedSlots(BorrowerB), 1);
    assertTrue(factory.isHooksAuthorized(address(hooks)));
  }

  // ┌─ test_migrateHooksBorrower_SelfServiceAndAdminWithActiveSlots ─────
  function test_migrateHooksBorrower_SelfServiceAndAdminWithActiveSlots() external {
    MockHooksForFactory hooks = hooksFactoryV25.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactoryV25.createMarket(address(hooks));
    MockMarketForFactory m2 = hooksFactoryV25.createMarket(address(hooks));

    vm.startPrank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 3);
    factory.setBorrowerAllowance(BorrowerB, 1);
    vm.stopPrank();

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactoryV25), address(hooks), 2);

    // unchanged borrower reverts.
    vm.prank(Admin);
    vm.expectRevert(IKYCRoleProviderFactory.BorrowerUnchanged.selector);
    factory.migrateHooksBorrower(address(hooks));

    // rotate hooks admin to BorrowerB; stranger and old borrower cannot migrate.
    hooks.setBorrower(BorrowerB);
    vm.prank(Stranger);
    vm.expectRevert(IKYCRoleProviderFactory.CallerNotHooksBorrowerOrAdmin.selector);
    factory.migrateHooksBorrower(address(hooks));
    vm.prank(BorrowerA);
    vm.expectRevert(IKYCRoleProviderFactory.CallerNotHooksBorrowerOrAdmin.selector);
    factory.migrateHooksBorrower(address(hooks));

    // 2 active slots exceed BorrowerB's allowance of 1 -> reverts.
    vm.prank(BorrowerB);
    vm.expectRevert(IKYCRoleProviderFactory.InsufficientAllowance.selector);
    factory.migrateHooksBorrower(address(hooks));

    // close & reclaim m1 under BorrowerA -> 1 active slot remains; now BorrowerB can self-migrate.
    m1.close();
    factory.reclaimClosedMarket(address(hooks), 0);
    assertEq(factory.usedSlots(BorrowerA), 1);
    assertEq(factory.getHooksAuthorization(address(hooks)).reclaimedMarketCount, 1);

    vm.prank(BorrowerB);
    factory.migrateHooksBorrower(address(hooks));
    assertEq(factory.usedSlots(BorrowerA), 0);
    assertEq(factory.usedSlots(BorrowerB), 1);

    // closing m2 now credits BorrowerB cleanly without underflow.
    m2.close();
    factory.reclaimClosedMarket(address(hooks), 1);
    assertEq(factory.usedSlots(BorrowerB), 0);
    assertEq(factory.getHooksAuthorization(address(hooks)).reclaimedMarketCount, 2);
  }

  // ░░▒▒▓▓██ [ CLOSED MARKET RECLAMATION ] ────────────────────────────────────

  // ┌─ test_firstAuthorization_ReclaimsPreClosedMarkets ─────
  function test_firstAuthorization_ReclaimsPreClosedMarkets() external {
    MockHooksForFactory hooks = hooksFactory.createHooks(BorrowerA);
    MockMarketForFactory m0 = hooksFactory.createMarket(address(hooks));
    MockMarketForFactory m1 = hooksFactory.createMarket(address(hooks));
    hooksFactory.createMarket(address(hooks)); // m2 stays open

    m0.close();
    m1.close();

    // borrower has allowance 1, hooks has 3 historical markets (2 closed, 1 open).
    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 1);

    ClosedMarketClaim[] memory claims = new ClosedMarketClaim[](2);
    claims[0] = ClosedMarketClaim({ hooksInstance: address(hooks), marketIndex: 0 });
    claims[1] = ClosedMarketClaim({ hooksInstance: address(hooks), marketIndex: 1 });

    // disabled reclamation blocks pre-closed offset.
    vm.prank(Admin);
    factory.setSlotReclamationEnabled(false);
    KYCRoleProviderAttachInputs memory attach = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerA,
      targetApprovedMarketCount: 3,
      closedMarketsToReclaim: claims
    });
    vm.expectRevert(IKYCRoleProviderFactory.SlotReclamationDisabled.selector);
    hooks.callCreateRoleProvider(factory, abi.encode(attach));

    // re-enable: duplicate index reverts cleanly.
    vm.prank(Admin);
    factory.setSlotReclamationEnabled(true);
    ClosedMarketClaim[] memory dupClaims = new ClosedMarketClaim[](2);
    dupClaims[0] = ClosedMarketClaim({ hooksInstance: address(hooks), marketIndex: 0 });
    dupClaims[1] = ClosedMarketClaim({ hooksInstance: address(hooks), marketIndex: 0 });
    KYCRoleProviderAttachInputs memory dupAttach = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerA,
      targetApprovedMarketCount: 3,
      closedMarketsToReclaim: dupClaims
    });
    vm.expectRevert(IKYCRoleProviderFactory.MarketAlreadyReclaimed.selector);
    hooks.callCreateRoleProvider(factory, abi.encode(dupAttach));

    // valid pre-closed claims offset the 2 closed markets, charging net 1 slot in one tx.
    assertEq(hooks.callCreateRoleProvider(factory, abi.encode(attach)), providerA);
    assertEq(factory.usedSlots(BorrowerA), 1);
    assertTrue(factory.closedMarketReclaimed(address(m0)));
    assertTrue(factory.closedMarketReclaimed(address(m1)));
    assertTrue(factory.isHooksAuthorized(address(hooks)));

    HooksAuthorization memory auth = factory.getHooksAuthorization(address(hooks));
    assertEq(auth.approvedMarketCount, 3);
    assertEq(auth.reclaimedMarketCount, 2);

    // cannot reclaim m0 a second time.
    vm.expectRevert(IKYCRoleProviderFactory.MarketAlreadyReclaimed.selector);
    factory.reclaimClosedMarket(address(hooks), 0);
  }

  // ┌─ test_reclaimClosedMarket_PerMarketWithoutHookRetirement ─────
  function test_reclaimClosedMarket_PerMarketWithoutHookRetirement() external {
    MockHooksForFactory hooks = hooksFactory.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactory.createMarket(address(hooks));
    MockMarketForFactory m2 = hooksFactory.createMarket(address(hooks));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 2);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks), 2);
    assertEq(factory.usedSlots(BorrowerA), 2);

    // close only m1; m2 stays open on the same hooks instance.
    m1.close();
    factory.reclaimClosedMarket(address(hooks), 0);

    assertEq(factory.usedSlots(BorrowerA), 1);
    assertTrue(factory.closedMarketReclaimed(address(m1)));
    // hooks stays authorized for m2 with approvedMarketCount still 2.
    assertTrue(factory.isHooksAuthorized(address(hooks)));
    HooksAuthorization memory auth = factory.getHooksAuthorization(address(hooks));
    assertEq(auth.approvedMarketCount, 2);

    // borrower can reuse the reclaimed slot to add m3 on the SAME hooks instance.
    hooksFactory.createMarket(address(hooks));
    assertFalse(factory.isHooksAuthorized(address(hooks)));
    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks), 3);
    assertTrue(factory.isHooksAuthorized(address(hooks)));
    assertEq(factory.usedSlots(BorrowerA), 2);
    assertFalse(m2.isClosed());
  }

  // ┌─ test_reclaimClosedMarket_CommitsProjectedClosureViaUpdateState ─────
  function test_reclaimClosedMarket_CommitsProjectedClosureViaUpdateState() external {
    MockHooksForFactory hooks = hooksFactoryV25.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactoryV25.createMarket(address(hooks));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 1);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactoryV25), address(hooks), 1);

    // simulates v2.5 projected repayment closure committed only when `updateState()` executes.
    m1.setProjectedClosure(true);
    assertFalse(m1.isClosed());

    factory.reclaimClosedMarket(address(hooks), 0);
    assertEq(m1.updateStateCalls(), 1);
    assertTrue(m1.isClosed());
    assertEq(factory.usedSlots(BorrowerA), 0);
  }

  // ┌─ test_reclaimClosedMarket_GuardsAndToggle ─────
  function test_reclaimClosedMarket_GuardsAndToggle() external {
    MockHooksForFactory hooks = hooksFactory.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactory.createMarket(address(hooks));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 2);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks), 2);

    // open market reverts.
    vm.expectRevert(IKYCRoleProviderFactory.MarketNotClosed.selector);
    factory.reclaimClosedMarket(address(hooks), 0);

    // index within approvedMarketCount (2) but >= currentMarkets (1) reverts cleanly, no underflow.
    vm.expectRevert(IKYCRoleProviderFactory.MarketIndexOutOfBounds.selector);
    factory.reclaimClosedMarket(address(hooks), 1);

    // sneaking a 3rd unapproved market (index 2 >= approvedMarketCount 2) and closing it cannot manufacture credit.
    hooksFactory.createMarket(address(hooks));
    MockMarketForFactory snuck = hooksFactory.createMarket(address(hooks));
    snuck.close();
    vm.expectRevert(IKYCRoleProviderFactory.MarketIndexOutOfBounds.selector);
    factory.reclaimClosedMarket(address(hooks), 2);

    // admin toggle disables reclamation.
    m1.close();
    vm.prank(Admin);
    factory.setSlotReclamationEnabled(false);
    vm.expectRevert(IKYCRoleProviderFactory.SlotReclamationDisabled.selector);
    factory.reclaimClosedMarket(address(hooks), 0);

    // re-enable -> succeeds once, second attempt reverts.
    vm.prank(Admin);
    factory.setSlotReclamationEnabled(true);
    factory.reclaimClosedMarket(address(hooks), 0);
    vm.expectRevert(IKYCRoleProviderFactory.MarketAlreadyReclaimed.selector);
    factory.reclaimClosedMarket(address(hooks), 0);
  }

  // ┌─ test_inlineReclaim_AuthorizeAndAttachAtCap ─────
  function test_inlineReclaim_AuthorizeAndAttachAtCap() external {
    MockHooksForFactory hooks1 = hooksFactory.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactory.createMarket(address(hooks1));
    MockHooksForFactory hooks2 = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(hooks2));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 1);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 1);
    m1.close();

    // at cap (1/1), borrower reclaims m1 and attaches KYC to hooks2 in a single tx.
    ClosedMarketClaim[] memory claims = new ClosedMarketClaim[](1);
    claims[0] = ClosedMarketClaim({ hooksInstance: address(hooks1), marketIndex: 0 });
    KYCRoleProviderAttachInputs memory inputs = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: providerA,
      targetApprovedMarketCount: 1,
      closedMarketsToReclaim: claims
    });

    assertEq(hooks2.callCreateRoleProvider(factory, abi.encode(inputs)), providerA);
    assertEq(factory.usedSlots(BorrowerA), 1);
    assertTrue(factory.closedMarketReclaimed(address(m1)));
    assertTrue(factory.isHooksAuthorized(address(hooks2)));
  }

  // ┌─ test_batchReclaimAndFourArgAuthorizeHooks ─────
  function test_batchReclaimAndFourArgAuthorizeHooks() external {
    MockHooksForFactory hooks1 = hooksFactory.createHooks(BorrowerA);
    MockMarketForFactory m1 = hooksFactory.createMarket(address(hooks1));
    MockMarketForFactory m2 = hooksFactory.createMarket(address(hooks1));
    MockHooksForFactory hooks2 = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(hooks2));
    MockHooksForFactory hooks3 = hooksFactory.createHooks(BorrowerA);
    hooksFactory.createMarket(address(hooks3));

    vm.prank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 2);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks1), 2);

    m1.close();
    m2.close();

    // 4-arg authorizeHooks reclaims m1 inline to fund hooks2.
    ClosedMarketClaim[] memory singleClaim = new ClosedMarketClaim[](1);
    singleClaim[0] = ClosedMarketClaim({ hooksInstance: address(hooks1), marketIndex: 0 });
    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks2), 1, singleClaim);
    assertEq(factory.usedSlots(BorrowerA), 2);

    // batch reclaim m2, then authorize hooks3.
    ClosedMarketClaim[] memory batchClaim = new ClosedMarketClaim[](1);
    batchClaim[0] = ClosedMarketClaim({ hooksInstance: address(hooks1), marketIndex: 1 });
    factory.reclaimClosedMarkets(batchClaim);
    assertEq(factory.usedSlots(BorrowerA), 1);

    vm.prank(BorrowerA);
    factory.authorizeHooks(address(hooksFactory), address(hooks3), 1);
    assertEq(factory.usedSlots(BorrowerA), 2);
  }

  // ┌─ test_slotConservation_MultiBorrowerFuzz ─────
  function test_slotConservation_MultiBorrowerFuzz(uint8[24] calldata actions, uint8[24] calldata targets) external {
    MockHooksForFactory[4] memory hooksList = [
      hooksFactory.createHooks(BorrowerA),
      hooksFactory.createHooks(BorrowerA),
      hooksFactory.createHooks(BorrowerB),
      hooksFactory.createHooks(BorrowerB)
    ];

    vm.startPrank(Admin);
    factory.setBorrowerAllowance(BorrowerA, 10);
    factory.setBorrowerAllowance(BorrowerB, 10);
    vm.stopPrank();

    for (uint256 step; step < 24; ++step) {
      MockHooksForFactory h = hooksList[targets[step] % 4];
      uint256 op = actions[step] % 7;

      if (op == 0) {
        hooksFactory.createMarket(address(h));
      } else if (op == 1 || op == 2) {
        HooksAuthorization memory auth = factory.getHooksAuthorization(address(h));
        uint32 deployed = uint32(hooksFactory.getMarketsForHooksInstanceCount(address(h)));
        uint32 nextTarget = (auth.approvedMarketCount > deployed ? auth.approvedMarketCount : deployed) + 1;
        address owner = h.borrower();
        if (auth.approvedMarketCount == 0 || auth.borrower == owner) {
          uint32 delta = nextTarget - auth.approvedMarketCount;
          if (uint256(factory.usedSlots(owner)) + delta <= factory.borrowerAllowance(owner)) {
            if (op == 1) {
              vm.prank(owner);
              factory.authorizeHooks(address(hooksFactory), address(h), nextTarget);
            } else {
              KYCRoleProviderAttachInputs memory inputs = KYCRoleProviderAttachInputs({
                hooksFactory: address(hooksFactory),
                provider: providerA,
                targetApprovedMarketCount: nextTarget,
                closedMarketsToReclaim: new ClosedMarketClaim[](0)
              });
              h.callCreateRoleProvider(factory, abi.encode(inputs));
            }
          }
        }
      } else if (op == 3) {
        HooksAuthorization memory auth = factory.getHooksAuthorization(address(h));
        uint32 deployed = uint32(hooksFactory.getMarketsForHooksInstanceCount(address(h)));
        if (auth.approvedMarketCount > deployed) {
          // exercises both partial reduction and full delete-to-0 on empty hooks.
          uint32 reduced = (targets[step] & 1 == 0) ? deployed : auth.approvedMarketCount - 1;
          vm.prank(auth.borrower);
          factory.reduceUnusedSlots(address(h), reduced);
        }
      } else if (op == 4) {
        HooksAuthorization memory auth = factory.getHooksAuthorization(address(h));
        uint256 deployed = hooksFactory.getMarketsForHooksInstanceCount(address(h));
        uint256 boundCount = auth.approvedMarketCount < deployed ? auth.approvedMarketCount : deployed;
        if (boundCount > 0) {
          uint256 mIdx = targets[step] % boundCount;
          address market = hooksFactory.getMarketsForHooksInstance(address(h), mIdx, mIdx + 1)[0];
          if (!factory.closedMarketReclaimed(market)) {
            MockMarketForFactory(market).close();
            factory.reclaimClosedMarket(address(h), mIdx);
          }
        }
      } else if (op == 5) {
        // rotate hooks borrower between A and B and self-migrate if destination allowance permits.
        address nextOwner = h.borrower() == BorrowerA ? BorrowerB : BorrowerA;
        h.setBorrower(nextOwner);
        HooksAuthorization memory auth = factory.getHooksAuthorization(address(h));
        if (auth.approvedMarketCount > 0 && auth.borrower != nextOwner) {
          uint32 active = auth.approvedMarketCount - auth.reclaimedMarketCount;
          if (uint256(factory.usedSlots(nextOwner)) + active <= factory.borrowerAllowance(nextOwner)) {
            vm.prank(nextOwner);
            factory.migrateHooksBorrower(address(h));
          }
        }
      } else {
        address targetBorrower = (targets[step] & 1 == 0) ? BorrowerA : BorrowerB;
        vm.prank(Admin);
        factory.setBorrowerAllowance(targetBorrower, uint32(targets[step] % 12));
      }

      uint256 expectedA;
      uint256 expectedB;
      for (uint256 i; i < 4; ++i) {
        HooksAuthorization memory a = factory.getHooksAuthorization(address(hooksList[i]));
        if (a.approvedMarketCount == 0) continue;
        uint256 active = a.approvedMarketCount - a.reclaimedMarketCount;
        if (a.borrower == BorrowerA) expectedA += active;
        else if (a.borrower == BorrowerB) expectedB += active;
      }
      assertEq(factory.usedSlots(BorrowerA), expectedA);
      assertEq(factory.usedSlots(BorrowerB), expectedB);
    }
  }
}

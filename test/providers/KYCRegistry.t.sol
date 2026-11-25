// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRegistry.t
//  \ ^ /   Lender registration, keeper attribute sync, expiry, and pruning.
//    V
//
//  FIXTURE
//  setUp()
//
//  ADMIN AND KEEPERS
//  test_constructor_InvalidInputsRevert()
//  test_setKeeper_OnlyAdministratorAndNonZero()
//  test_handoff_AdministratorTransfer()
//
//  REGISTRATION AND PRUNING
//  test_register_PermissionlessAndPaginated()
//  test_pruneUnverifiedLenders_AtomicAndGuarded()
//
//  ATTRIBUTES AND EXPIRY
//  test_setAttributes_AutoRegistersAndUpdates()
//  test_setAttributes_InvalidInputsRevert()
//  test_removeAttributes_AtomicAndEnablesPruning()
//  test_updateAttributes_AtomicRemovalsBeforeSets()
//  test_expiry_ActiveExpiresWhilePresenceFailsClosed()
//  test_meetsAttributes_Fuzz(uint40,uint40,uint40)
// ═════

import { Test } from 'forge-std/Test.sol';
import { IManagedRoleProvider } from 'src/access/IManagedRoleProvider.sol';
import {
  IKYCRegistry,
  KYCAttribute,
  KYCAttributeInput,
  KYCAttributeRemoval
} from 'src/providers/IKYCRegistry.sol';
import { KYCRegistry } from 'src/providers/KYCRegistry.sol';

// ┌─ KYCRegistryTest ──────────────────────────────────────────────────────────
contract KYCRegistryTest is Test {
  address internal constant Admin = address(0xAD1);
  address internal constant NextAdmin = address(0xAD2);
  address internal constant Keeper = address(0xBEEF);
  address internal constant Keeper2 = address(0xCAFE);
  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);
  address internal constant Carol = address(0xCA201);

  bytes32 internal constant AttrSomaVerified = keccak256('WILDCAT:SOMA_VERIFIED');
  bytes32 internal constant AttrInstitutional = keccak256('SOMA:INSTITUTIONAL');
  bytes32 internal constant AttrUS = keccak256('SOMA:US');
  bytes32 internal constant AttrAccredited = keccak256('SOMA:ACCREDITED');

  uint40 internal constant Start = 1_760_000_000;
  uint8 internal constant SourceWildcat = 1;
  uint8 internal constant SourceSoma = 2;

  KYCRegistry internal registry;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(Start);
    address[] memory keepers = new address[](1);
    keepers[0] = Keeper;
    registry = new KYCRegistry(Admin, keepers);
  }

  // ░░▒▒▓▓██ [ ADMIN AND KEEPERS ] ────────────────────────────────────────────

  // ┌─ test_constructor_InvalidInputsRevert ─────
  function test_constructor_InvalidInputsRevert() external {
    address[] memory emptyKeepers = new address[](0);
    vm.expectRevert(IManagedRoleProvider.InvalidAdministratorTransferTarget.selector);
    new KYCRegistry(address(0), emptyKeepers);

    address[] memory badKeepers = new address[](1);
    badKeepers[0] = address(0);
    vm.expectRevert(IKYCRegistry.InvalidKeeper.selector);
    new KYCRegistry(Admin, badKeepers);
  }

  // ┌─ test_setKeeper_OnlyAdministratorAndNonZero ─────
  function test_setKeeper_OnlyAdministratorAndNonZero() external {
    assertTrue(registry.isKeeper(Keeper));
    assertFalse(registry.isKeeper(Keeper2));

    vm.prank(Keeper);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    registry.setKeeper(Keeper2, true);

    vm.startPrank(Admin);
    vm.expectRevert(IKYCRegistry.InvalidKeeper.selector);
    registry.setKeeper(address(0), true);

    vm.expectEmit(true, true, false, true, address(registry));
    emit IKYCRegistry.KeeperUpdated(Admin, Keeper2, true);
    registry.setKeeper(Keeper2, true);
    assertTrue(registry.isKeeper(Keeper2));

    vm.expectEmit(true, true, false, true, address(registry));
    emit IKYCRegistry.KeeperUpdated(Admin, Keeper2, false);
    registry.setKeeper(Keeper2, false);
    assertFalse(registry.isKeeper(Keeper2));
    vm.stopPrank();
  }

  // ┌─ test_handoff_AdministratorTransfer ─────
  function test_handoff_AdministratorTransfer() external {
    vm.prank(Admin);
    registry.requestAdministratorTransfer(NextAdmin);
    assertEq(registry.administrator(), Admin);
    assertEq(registry.pendingAdministrator(), NextAdmin);

    vm.prank(NextAdmin);
    registry.acceptAdministratorTransfer();
    assertEq(registry.administrator(), NextAdmin);
    assertEq(registry.pendingAdministrator(), address(0));

    vm.prank(Admin);
    vm.expectRevert(IManagedRoleProvider.CallerNotAdministrator.selector);
    registry.setKeeper(Keeper2, true);

    vm.prank(NextAdmin);
    registry.setKeeper(Keeper2, true);
    assertTrue(registry.isKeeper(Keeper2));
  }

  // ░░▒▒▓▓██ [ REGISTRATION AND PRUNING ] ─────────────────────────────────────

  // ┌─ test_register_PermissionlessAndPaginated ─────
  function test_register_PermissionlessAndPaginated() external {
    vm.expectEmit(true, false, false, true, address(registry));
    emit IKYCRegistry.LenderRegistered(Alice);
    vm.prank(Alice);
    registry.register();

    vm.prank(Alice);
    vm.expectRevert(IKYCRegistry.AlreadyRegistered.selector);
    registry.register();

    vm.prank(Bob);
    registry.register();
    vm.prank(Carol);
    registry.register();

    assertTrue(registry.isRegistered(Alice));
    assertEq(registry.getRegisteredLendersCount(), 3);

    address[] memory page = registry.getRegisteredLenders(0, 2);
    assertEq(page.length, 2);
    assertEq(page[0], Alice);
    assertEq(page[1], Bob);

    address[] memory tail = registry.getRegisteredLenders(2, 10);
    assertEq(tail.length, 1);
    assertEq(tail[0], Carol);

    assertEq(registry.getRegisteredLenders(5, 10).length, 0);
    assertEq(registry.getRegisteredLenders(2, 2).length, 0);

    vm.expectRevert(IKYCRegistry.InvalidPaginationRange.selector);
    registry.getRegisteredLenders(3, 2);
  }

  // ┌─ test_pruneUnverifiedLenders_AtomicAndGuarded ─────
  function test_pruneUnverifiedLenders_AtomicAndGuarded() external {
    vm.prank(Alice);
    registry.register();
    vm.prank(Bob);
    registry.register();

    vm.prank(Keeper);
    registry.setAttribute(
      KYCAttributeInput({
        account: Bob,
        attributeId: AttrSomaVerified,
        issuedAt: Start,
        expiresAt: 0,
        sourceId: SourceWildcat
      })
    );

    address[] memory pair = new address[](2);
    pair[0] = Alice;
    pair[1] = Bob;

    vm.prank(Alice);
    vm.expectRevert(IKYCRegistry.CallerNotKeeperOrAdministrator.selector);
    registry.pruneUnverifiedLenders(pair);

    // second entry has attributes, so the whole batch must roll back.
    vm.prank(Keeper);
    vm.expectRevert(IKYCRegistry.LenderHasAttributes.selector);
    registry.pruneUnverifiedLenders(pair);
    assertTrue(registry.isRegistered(Alice));

    address[] memory missing = new address[](1);
    missing[0] = Carol;
    vm.prank(Admin);
    vm.expectRevert(IKYCRegistry.LenderNotRegistered.selector);
    registry.pruneUnverifiedLenders(missing);

    address[] memory unverified = new address[](1);
    unverified[0] = Alice;
    vm.expectEmit(true, true, false, true, address(registry));
    emit IKYCRegistry.LenderRemoved(Admin, Alice);
    vm.prank(Admin);
    registry.pruneUnverifiedLenders(unverified);

    assertFalse(registry.isRegistered(Alice));
    assertTrue(registry.isRegistered(Bob));
    assertEq(registry.getRegisteredLendersCount(), 1);
  }

  // ░░▒▒▓▓██ [ ATTRIBUTES AND EXPIRY ] ────────────────────────────────────────

  // ┌─ test_setAttributes_AutoRegistersAndUpdates ─────
  function test_setAttributes_AutoRegistersAndUpdates() external {
    KYCAttributeInput[] memory inputs = new KYCAttributeInput[](2);
    inputs[0] = KYCAttributeInput({
      account: Alice,
      attributeId: AttrSomaVerified,
      issuedAt: Start - 10,
      expiresAt: Start + 365 days,
      sourceId: SourceWildcat
    });
    inputs[1] = KYCAttributeInput({
      account: Alice,
      attributeId: AttrAccredited,
      issuedAt: Start - 5,
      expiresAt: Start + 90 days,
      sourceId: SourceSoma
    });

    vm.prank(Keeper);
    registry.setAttributes(inputs);

    assertTrue(registry.isRegistered(Alice));
    assertEq(registry.getRegisteredLendersCount(), 1);

    (bytes32[] memory ids, KYCAttribute[] memory records) = registry.getLenderAttributes(Alice);
    assertEq(ids.length, 2);
    assertEq(records.length, 2);
    assertEq(records[0].issuedAt, Start - 10);
    assertEq(records[0].expiresAt, Start + 365 days);
    assertEq(records[0].updatedAt, Start);
    assertEq(records[0].sourceId, SourceWildcat);

    // refreshing an existing attribute updates metadata without duplicating the key.
    vm.warp(Start + 10 days);
    vm.prank(Keeper);
    registry.setAttribute(
      KYCAttributeInput({
        account: Alice,
        attributeId: AttrAccredited,
        issuedAt: Start + 10 days,
        expiresAt: Start + 100 days,
        sourceId: SourceSoma
      })
    );

    assertEq(registry.getLenderAttributeIds(Alice).length, 2);
    KYCAttribute memory refreshed = registry.getAttribute(Alice, AttrAccredited);
    assertEq(refreshed.issuedAt, Start + 10 days);
    assertEq(refreshed.expiresAt, Start + 100 days);
    assertEq(refreshed.updatedAt, Start + 10 days);
  }

  // ┌─ test_setAttributes_InvalidInputsRevert ─────
  function test_setAttributes_InvalidInputsRevert() external {
    KYCAttributeInput memory valid = KYCAttributeInput({
      account: Alice,
      attributeId: AttrSomaVerified,
      issuedAt: Start,
      expiresAt: 0,
      sourceId: SourceWildcat
    });

    vm.prank(Admin);
    vm.expectRevert(IKYCRegistry.CallerNotKeeper.selector);
    registry.setAttribute(valid);

    vm.startPrank(Keeper);
    vm.expectRevert(IKYCRegistry.InvalidAccount.selector);
    registry.setAttribute(KYCAttributeInput(address(0), AttrSomaVerified, Start, 0, SourceWildcat));

    vm.expectRevert(IKYCRegistry.InvalidAttributeId.selector);
    registry.setAttribute(KYCAttributeInput(Alice, bytes32(0), Start, 0, SourceWildcat));

    vm.expectRevert(IKYCRegistry.InvalidTimestamps.selector);
    registry.setAttribute(KYCAttributeInput(Alice, AttrSomaVerified, 0, 0, SourceWildcat));

    vm.expectRevert(IKYCRegistry.InvalidTimestamps.selector);
    registry.setAttribute(KYCAttributeInput(Alice, AttrSomaVerified, Start, Start - 1, SourceWildcat));

    // batch atomicity: bad second entry rolls back the first.
    KYCAttributeInput[] memory batch = new KYCAttributeInput[](2);
    batch[0] = valid;
    batch[1] = KYCAttributeInput(Bob, bytes32(0), Start, 0, SourceSoma);
    vm.expectRevert(IKYCRegistry.InvalidAttributeId.selector);
    registry.setAttributes(batch);
    vm.stopPrank();

    assertFalse(registry.isRegistered(Alice));
    assertFalse(registry.hasAttribute(Alice, AttrSomaVerified));
  }

  // ┌─ test_removeAttributes_AtomicAndEnablesPruning ─────
  function test_removeAttributes_AtomicAndEnablesPruning() external {
    vm.startPrank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrSomaVerified, Start, 0, SourceWildcat));
    registry.setAttribute(KYCAttributeInput(Alice, AttrUS, Start, 0, SourceSoma));

    KYCAttributeRemoval[] memory badBatch = new KYCAttributeRemoval[](2);
    badBatch[0] = KYCAttributeRemoval(Alice, AttrUS);
    badBatch[1] = KYCAttributeRemoval(Alice, AttrAccredited);
    vm.expectRevert(IKYCRegistry.AttributeNotFound.selector);
    registry.removeAttributes(badBatch);
    assertTrue(registry.hasAttribute(Alice, AttrUS));

    KYCAttributeRemoval[] memory goodBatch = new KYCAttributeRemoval[](2);
    goodBatch[0] = KYCAttributeRemoval(Alice, AttrUS);
    goodBatch[1] = KYCAttributeRemoval(Alice, AttrSomaVerified);
    registry.removeAttributes(goodBatch);

    assertFalse(registry.hasAttribute(Alice, AttrUS));
    assertFalse(registry.hasAttribute(Alice, AttrSomaVerified));
    assertEq(registry.getLenderAttributeIds(Alice).length, 0);

    // once all attributes are cleared, the wallet can be pruned from the registered set.
    address[] memory toPrune = new address[](1);
    toPrune[0] = Alice;
    registry.pruneUnverifiedLenders(toPrune);
    vm.stopPrank();

    assertFalse(registry.isRegistered(Alice));
  }

  // ┌─ test_updateAttributes_AtomicRemovalsBeforeSets ─────
  function test_updateAttributes_AtomicRemovalsBeforeSets() external {
    vm.startPrank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrSomaVerified, Start, 0, SourceWildcat));
    registry.setAttribute(KYCAttributeInput(Alice, AttrUS, Start, 0, SourceSoma));
    vm.stopPrank();

    KYCAttributeInput[] memory sets = new KYCAttributeInput[](2);
    sets[0] = KYCAttributeInput(Alice, AttrInstitutional, Start + 1, 0, SourceSoma);
    sets[1] = KYCAttributeInput(Alice, AttrSomaVerified, Start + 1, Start + 365 days, SourceWildcat);
    KYCAttributeRemoval[] memory removals = new KYCAttributeRemoval[](2);
    removals[0] = KYCAttributeRemoval(Alice, AttrUS);
    removals[1] = KYCAttributeRemoval(Alice, AttrSomaVerified);

    vm.prank(Admin);
    vm.expectRevert(IKYCRegistry.CallerNotKeeper.selector);
    registry.updateAttributes(sets, removals);

    // removals run before sets: AttrUS clears, AttrInstitutional sets, and replaced AttrSomaVerified finishes set.
    vm.warp(Start + 1);
    vm.prank(Keeper);
    registry.updateAttributes(sets, removals);

    assertFalse(registry.hasAttribute(Alice, AttrUS));
    assertTrue(registry.hasActiveAttribute(Alice, AttrInstitutional));
    assertTrue(registry.hasActiveAttribute(Alice, AttrSomaVerified));
    assertEq(registry.getAttribute(Alice, AttrSomaVerified).expiresAt, Start + 365 days);

    // atomic rollback when a set fails after a removal succeeded.
    KYCAttributeInput[] memory badSets = new KYCAttributeInput[](1);
    badSets[0] = KYCAttributeInput(Alice, bytes32(0), Start + 2, 0, SourceSoma);
    KYCAttributeRemoval[] memory oneRemoval = new KYCAttributeRemoval[](1);
    oneRemoval[0] = KYCAttributeRemoval(Alice, AttrInstitutional);

    vm.prank(Keeper);
    vm.expectRevert(IKYCRegistry.InvalidAttributeId.selector);
    registry.updateAttributes(badSets, oneRemoval);
    assertTrue(registry.hasActiveAttribute(Alice, AttrInstitutional));
  }

  // ┌─ test_expiry_ActiveExpiresWhilePresenceFailsClosed ─────
  function test_expiry_ActiveExpiresWhilePresenceFailsClosed() external {
    uint40 expiry = Start + 30 days;
    vm.prank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrUS, Start, expiry, SourceSoma));

    vm.warp(expiry);
    assertTrue(registry.hasActiveAttribute(Alice, AttrUS));
    assertTrue(registry.hasAttribute(Alice, AttrUS));

    vm.warp(expiry + 1);
    assertFalse(registry.hasActiveAttribute(Alice, AttrUS));
    // forbidden checks rely on `hasAttribute` staying true past expiry until explicit removal.
    assertTrue(registry.hasAttribute(Alice, AttrUS));

    vm.prank(Keeper);
    registry.removeAttribute(Alice, AttrUS);
    assertFalse(registry.hasAttribute(Alice, AttrUS));
  }

  // ┌─ test_meetsAttributes_Fuzz ─────
  function test_meetsAttributes_Fuzz(uint40 reqExpiry, uint40 forbExpiry, uint40 nowTs) external {
    reqExpiry = uint40(bound(reqExpiry, Start, Start + 365 days));
    forbExpiry = uint40(bound(forbExpiry, Start, Start + 365 days));
    nowTs = uint40(bound(nowTs, Start, Start + 400 days));

    vm.startPrank(Keeper);
    registry.setAttribute(KYCAttributeInput(Alice, AttrSomaVerified, Start, reqExpiry, SourceWildcat));
    registry.setAttribute(KYCAttributeInput(Alice, AttrUS, Start, forbExpiry, SourceSoma));
    vm.stopPrank();

    bytes32[] memory req = new bytes32[](1);
    req[0] = AttrSomaVerified;
    bytes32[] memory forb = new bytes32[](1);
    forb[0] = AttrUS;

    vm.warp(nowTs);
    // forbidden key is present, so `meetsAttributes` must stay false even if `forbExpiry < nowTs`.
    assertFalse(registry.meetsAttributes(Alice, req, forb));

    vm.prank(Keeper);
    registry.removeAttribute(Alice, AttrUS);
    assertEq(registry.meetsAttributes(Alice, req, forb), nowTs <= reqExpiry);
  }
}

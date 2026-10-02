// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // SphereXConfig.t
// ║  ██▀▀     ▀▀██   Engine administration, sender registration, and disabled guards.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  FIXTURE
// ║  _newFixture()
// ║  _newEngine(...)
// ║  _assertConfig(...)
// ║
// ║  ENGINE ADMINISTRATION
// ║  test_constructor_StoresInitialConfiguration()
// ║  test_transferAdmin_IsTwoStepAndMovesAuthority()
// ║  test_transferAdmin_RequiresCurrentAdmin()
// ║  test_acceptAdmin_RequiresPendingAdmin()
// ║  test_changeOperator_EmitsAndRequiresAdmin()
// ║
// ║  ENGINE SELECTION
// ║  test_changeEngine_AcceptsDisabledAndCompatibleEngines()
// ║  test_changeEngine_RejectsIncompatibleEngine()
// ║  test_changeEngine_RequiresOperator()
// ║
// ║  SENDER REGISTRATION
// ║  test_addSender_AllowsAdminAndOperator()
// ║  test_addSender_RejectsOutsider()
// ║  test_addSender_IsNoOpWhenEngineDisabled()
// ║
// ║  REGISTERED GUARDS
// ║  test_registeredConfig_UsesControllerAsOperator()
// ║  test_registeredGuard_AllowsCallWhenEngineDisabled()
// ╚═════

import { SphereXConfig } from 'src/spherex/SphereXConfig.sol';
import { SphereXProtectedRegisteredBase } from 'src/spherex/SphereXProtectedRegisteredBase.sol';
import { SphereXConfigHarness } from '../mocks/SphereXConfigMocks.sol';
import { SphereXEngineMock } from '../mocks/SphereXConfigMocks.sol';
import { SphereXRegisteredHarness } from '../mocks/SphereXConfigMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ SphereXConfigTest ────────────────────────────────────────────────────────
contract SphereXConfigTest is TestKernel {
  struct Fixture {
    SphereXEngineMock engine;
    SphereXConfigHarness config;
  }

  event ChangedSpherexOperator(address oldSphereXAdmin, address newSphereXAdmin);
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);
  event SpherexAdminTransferStarted(address currentAdmin, address pendingAdmin);
  event SpherexAdminTransferCompleted(address oldAdmin, address newAdmin);
  event NewAllowedSenderOnchain(address sender);
  event NewSenderOnEngine(address sender);

  address internal constant Admin = address(0xAD);
  address internal constant Operator = address(0x0F);
  address internal constant PendingAdmin = address(0xBEEF);
  address internal constant Outsider = address(0xBAD);
  address internal constant Sender = address(0x51);

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ _newFixture ─────
  function _newFixture() internal returns (Fixture memory fixture) {
    fixture.engine = _newEngine(true);
    fixture.config = SphereXConfigHarness(
      _deployCode(
        'test/mocks/SphereXConfigMocks.sol:SphereXConfigHarness', abi.encode(Admin, Operator, address(fixture.engine))
      )
    );
  }

  // ┌─ _newEngine ─────
  function _newEngine(bool supported) internal returns (SphereXEngineMock engine) {
    engine =
      SphereXEngineMock(_deployCode('test/mocks/SphereXConfigMocks.sol:SphereXEngineMock', abi.encode(supported)));
  }

  // ┌─ _assertConfig ─────
  function _assertConfig(
    SphereXConfigHarness config,
    address pendingAdmin,
    address admin,
    address operator,
    address engine
  )
    internal
    view
  {
    assertEq(config.pendingSphereXAdmin(), pendingAdmin);
    assertEq(config.sphereXAdmin(), admin);
    assertEq(config.sphereXOperator(), operator);
    assertEq(config.sphereXEngine(), engine);
  }

  // ░░▒▒▓▓██ [ ENGINE ADMINISTRATION ] ────────────────────────────────────────

  // ┌─ test_constructor_StoresInitialConfiguration ─────
  function test_constructor_StoresInitialConfiguration() external {
    Fixture memory fixture = _newFixture();
    _assertConfig(fixture.config, address(0), Admin, Operator, address(fixture.engine));
  }

  // ┌─ test_transferAdmin_IsTwoStepAndMovesAuthority ─────
  function test_transferAdmin_IsTwoStepAndMovesAuthority() external {
    Fixture memory fixture = _newFixture();

    vm.expectEmit(address(fixture.config));
    emit SpherexAdminTransferStarted(Admin, PendingAdmin);
    vm.prank(Admin);
    fixture.config.transferSphereXAdminRole(PendingAdmin);
    _assertConfig(fixture.config, PendingAdmin, Admin, Operator, address(fixture.engine));

    vm.expectEmit(address(fixture.config));
    emit SpherexAdminTransferCompleted(Admin, PendingAdmin);
    vm.prank(PendingAdmin);
    fixture.config.acceptSphereXAdminRole();
    _assertConfig(fixture.config, address(0), PendingAdmin, Operator, address(fixture.engine));

    vm.prank(PendingAdmin);
    fixture.config.changeSphereXOperator(Outsider);
    assertEq(fixture.config.sphereXOperator(), Outsider);
  }

  // ┌─ test_transferAdmin_RequiresCurrentAdmin ─────
  function test_transferAdmin_RequiresCurrentAdmin() external {
    Fixture memory fixture = _newFixture();
    vm.expectRevert(SphereXConfig.SphereXAdminRequired.selector);
    vm.prank(Outsider);
    fixture.config.transferSphereXAdminRole(PendingAdmin);
  }

  // ┌─ test_acceptAdmin_RequiresPendingAdmin ─────
  function test_acceptAdmin_RequiresPendingAdmin() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(SphereXConfig.SphereXNotPendingAdmin.selector);
    vm.prank(PendingAdmin);
    fixture.config.acceptSphereXAdminRole();

    vm.prank(Admin);
    fixture.config.transferSphereXAdminRole(PendingAdmin);

    vm.expectRevert(SphereXConfig.SphereXNotPendingAdmin.selector);
    vm.prank(Outsider);
    fixture.config.acceptSphereXAdminRole();
  }

  // ┌─ test_changeOperator_EmitsAndRequiresAdmin ─────
  function test_changeOperator_EmitsAndRequiresAdmin() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(SphereXConfig.SphereXAdminRequired.selector);
    vm.prank(Outsider);
    fixture.config.changeSphereXOperator(PendingAdmin);

    vm.expectEmit(address(fixture.config));
    emit ChangedSpherexOperator(Operator, PendingAdmin);
    vm.prank(Admin);
    fixture.config.changeSphereXOperator(PendingAdmin);
    _assertConfig(fixture.config, address(0), Admin, PendingAdmin, address(fixture.engine));
  }

  // ░░▒▒▓▓██ [ ENGINE SELECTION ] ─────────────────────────────────────────────

  // ┌─ test_changeEngine_AcceptsDisabledAndCompatibleEngines ─────
  function test_changeEngine_AcceptsDisabledAndCompatibleEngines() external {
    Fixture memory fixture = _newFixture();

    vm.expectEmit(address(fixture.config));
    emit ChangedSpherexEngineAddress(address(fixture.engine), address(0));
    vm.prank(Operator);
    fixture.config.changeSphereXEngine(address(0));
    assertEq(fixture.config.sphereXEngine(), address(0));

    SphereXEngineMock nextEngine = _newEngine(true);
    vm.expectEmit(address(fixture.config));
    emit ChangedSpherexEngineAddress(address(0), address(nextEngine));
    vm.prank(Operator);
    fixture.config.changeSphereXEngine(address(nextEngine));
    assertEq(fixture.config.sphereXEngine(), address(nextEngine));
  }

  // ┌─ test_changeEngine_RejectsIncompatibleEngine ─────
  function test_changeEngine_RejectsIncompatibleEngine() external {
    Fixture memory fixture = _newFixture();
    SphereXEngineMock badEngine = _newEngine(false);

    vm.expectRevert(SphereXConfig.SphereXNotEngine.selector);
    vm.prank(Operator);
    fixture.config.changeSphereXEngine(address(badEngine));
    assertEq(fixture.config.sphereXEngine(), address(fixture.engine));
  }

  // ┌─ test_changeEngine_RequiresOperator ─────
  function test_changeEngine_RequiresOperator() external {
    Fixture memory fixture = _newFixture();
    vm.expectRevert(SphereXConfig.SphereXOperatorRequired.selector);
    vm.prank(Admin);
    fixture.config.changeSphereXEngine(address(0));
  }

  // ░░▒▒▓▓██ [ SENDER REGISTRATION ] ──────────────────────────────────────────

  // ┌─ test_addSender_AllowsAdminAndOperator ─────
  function test_addSender_AllowsAdminAndOperator() external {
    Fixture memory fixture = _newFixture();

    vm.expectEmit(address(fixture.engine));
    emit NewSenderOnEngine(Sender);
    vm.expectEmit(address(fixture.config));
    emit NewAllowedSenderOnchain(Sender);
    vm.prank(Admin);
    fixture.config.addSender(Sender);

    vm.expectEmit(address(fixture.engine));
    emit NewSenderOnEngine(Outsider);
    vm.expectEmit(address(fixture.config));
    emit NewAllowedSenderOnchain(Outsider);
    vm.prank(Operator);
    fixture.config.addSender(Outsider);
  }

  // ┌─ test_addSender_RejectsOutsider ─────
  function test_addSender_RejectsOutsider() external {
    Fixture memory fixture = _newFixture();
    vm.expectRevert(SphereXConfig.SphereXOperatorOrAdminRequired.selector);
    vm.prank(Outsider);
    fixture.config.addSender(Sender);
  }

  // ┌─ test_addSender_IsNoOpWhenEngineDisabled ─────
  function test_addSender_IsNoOpWhenEngineDisabled() external {
    Fixture memory fixture = _newFixture();
    vm.prank(Operator);
    fixture.config.changeSphereXEngine(address(0));

    vm.recordLogs();
    vm.prank(Admin);
    fixture.config.addSender(Sender);
    assertEq(vm.getRecordedLogs().length, 0);
  }

  // ░░▒▒▓▓██ [ REGISTERED GUARDS ] ────────────────────────────────────────────

  // ┌─ test_registeredConfig_UsesControllerAsOperator ─────
  function test_registeredConfig_UsesControllerAsOperator() external {
    SphereXRegisteredHarness registered = SphereXRegisteredHarness(
      _deployCode('test/mocks/SphereXConfigMocks.sol:SphereXRegisteredHarness', abi.encode(Admin, address(0)))
    );
    assertEq(registered.sphereXOperator(), Admin);
    assertEq(registered.sphereXEngine(), address(0));

    vm.expectRevert(SphereXProtectedRegisteredBase.SphereXOperatorRequired.selector);
    vm.prank(Outsider);
    registered.changeSphereXEngine(address(0));

    vm.expectEmit(address(registered));
    emit ChangedSpherexEngineAddress(address(0), Outsider);
    vm.prank(Admin);
    registered.changeSphereXEngine(Outsider);
    assertEq(registered.sphereXEngine(), Outsider);
  }

  // ┌─ test_registeredGuard_AllowsCallWhenEngineDisabled ─────
  function test_registeredGuard_AllowsCallWhenEngineDisabled() external {
    SphereXRegisteredHarness registered = SphereXRegisteredHarness(
      _deployCode('test/mocks/SphereXConfigMocks.sol:SphereXRegisteredHarness', abi.encode(Admin, address(0)))
    );

    registered.setValue(123);
    assertEq(registered.value(), 123);
  }
}

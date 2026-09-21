// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'openzeppelin/contracts/access/IAccessControl.sol';
import 'openzeppelin/contracts/access/IAccessControlDefaultAdminRules.sol';
import { ILegacyWildcatMarketControllerFactory } from 'script/mock/MockArchControllerOwner.sol';
import { MockArchControllerOwner } from 'script/mock/MockArchControllerOwner.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';
import { ArchControllerOwnerLegacyFactoryMock } from '../mocks/ArchControllerOwnerMocks.sol';
import { ArchControllerOwnerProtocolTargetMock } from '../mocks/ArchControllerOwnerMocks.sol';
import { ArchControllerOwnerSphereXEngineMock } from '../mocks/ArchControllerOwnerMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract MockArchControllerOwnerTest is TestKernel {
  struct Fixture {
    WildcatArchController archController;
    MockArchControllerOwner helper;
    ArchControllerOwnerProtocolTargetMock protocolTarget;
    ArchControllerOwnerLegacyFactoryMock legacyFactory;
    ArchControllerOwnerSphereXEngineMock sphereXEngine;
  }

  event AccountAuthorized(address indexed authorizer, address indexed account);
  event AccountDeauthorized(address indexed authorizer, address indexed account);
  event ProtocolActionExecuted(
    address indexed executor,
    address indexed target,
    bytes4 indexed selector
  );

  address internal constant OldExecutor = 0xca732651410E915090d7A7D889A1E44eF4575fcE;
  address internal constant NewExecutor = 0xCa7007a75296b532Ce1606d9e130eAa849800Ca7;
  address internal constant ThirdExecutor = address(0xA11CE);
  address internal constant BadCaller = address(0xBAD);

  function _deployArchController() internal returns (WildcatArchController archController) {
    archController = WildcatArchController(
      _deployCode('src/WildcatArchController.sol:WildcatArchController')
    );
  }

  function _deployHelper(
    WildcatArchController archController,
    address[] memory initialExecutors
  ) internal returns (MockArchControllerOwner helper) {
    helper = MockArchControllerOwner(
      _deployCode(
        'script/mock/MockArchControllerOwner.sol:MockArchControllerOwner',
        abi.encode(address(archController), initialExecutors)
      )
    );
  }

  function _deployProtocolTarget(
    address archController
  ) internal returns (ArchControllerOwnerProtocolTargetMock target) {
    target = ArchControllerOwnerProtocolTargetMock(
      _deployCode(
        'test/mocks/ArchControllerOwnerMocks.sol:ArchControllerOwnerProtocolTargetMock',
        abi.encode(archController)
      )
    );
  }

  function _deployLegacyFactory(
    address archController
  ) internal returns (ArchControllerOwnerLegacyFactoryMock factory) {
    factory = ArchControllerOwnerLegacyFactoryMock(
      _deployCode(
        'test/mocks/ArchControllerOwnerMocks.sol:ArchControllerOwnerLegacyFactoryMock',
        abi.encode(archController)
      )
    );
  }

  function _deploySphereXEngine() internal returns (ArchControllerOwnerSphereXEngineMock engine) {
    engine = ArchControllerOwnerSphereXEngineMock(
      _deployCode(
        'test/mocks/ArchControllerOwnerMocks.sol:ArchControllerOwnerSphereXEngineMock',
        abi.encode(uint48(1 hours), OldExecutor)
      )
    );
  }

  function _initialExecutors() internal pure returns (address[] memory accounts) {
    accounts = new address[](2);
    accounts[0] = OldExecutor;
    accounts[1] = NewExecutor;
  }

  function _newFixture() internal returns (Fixture memory fixture) {
    fixture.archController = _deployArchController();
    fixture.archController.transferSphereXAdminRole(OldExecutor);
    vm.prank(OldExecutor);
    fixture.archController.acceptSphereXAdminRole();
    fixture.archController.transferOwnership(OldExecutor);

    fixture.sphereXEngine = _deploySphereXEngine();
    bytes32 senderAdderRole = fixture.sphereXEngine.SENDER_ADDER_ROLE();
    vm.prank(OldExecutor);
    fixture.sphereXEngine.grantRole(senderAdderRole, address(fixture.archController));

    vm.startPrank(OldExecutor);
    fixture.archController.changeSphereXOperator(OldExecutor);
    fixture.archController.changeSphereXEngine(address(fixture.sphereXEngine));
    vm.stopPrank();

    fixture.helper = _deployHelper(fixture.archController, _initialExecutors());
    vm.prank(OldExecutor);
    fixture.archController.transferOwnership(address(fixture.helper));

    fixture.protocolTarget = _deployProtocolTarget(address(fixture.archController));
    fixture.legacyFactory = _deployLegacyFactory(address(fixture.archController));
  }

  // ========================================================================== //
  //                              Executor set                                  //
  // ========================================================================== //

  function test_constructor_RecordsExplicitExecutors() external {
    Fixture memory fixture = _newFixture();
    assertEq(address(fixture.helper.archController()), address(fixture.archController));
    assertEq(fixture.helper.version(), '2');
    assertTrue(fixture.helper.authorizedAccounts(OldExecutor));
    assertTrue(fixture.helper.authorizedAccounts(NewExecutor));
    assertEq(fixture.helper.getAuthorizedAccountsCount(), 2);

    address[] memory accounts = fixture.helper.getAuthorizedAccounts();
    assertEq(accounts.length, 2);
    assertEq(accounts[0], OldExecutor);
    assertEq(accounts[1], NewExecutor);
  }

  function test_constructor_RejectsInvalidInputs() external {
    WildcatArchController archController = _deployArchController();
    address[] memory emptyExecutors = new address[](0);
    vm.expectRevert(MockArchControllerOwner.InvalidInitialExecutors.selector);
    _deployHelper(archController, emptyExecutors);

    address[] memory oneExecutor = new address[](1);
    oneExecutor[0] = OldExecutor;
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    _deployHelper(WildcatArchController(address(0)), oneExecutor);
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    _deployHelper(WildcatArchController(address(0xBEEF)), oneExecutor);

    oneExecutor[0] = address(0);
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    _deployHelper(archController, oneExecutor);

    address[] memory duplicateExecutors = new address[](2);
    duplicateExecutors[0] = OldExecutor;
    duplicateExecutors[1] = OldExecutor;
    vm.expectRevert(MockArchControllerOwner.AccountAlreadyAuthorized.selector);
    _deployHelper(archController, duplicateExecutors);
  }

  function test_authorizeAndDeauthorizeAccounts_EmitsAndUsesSwapPop() external {
    Fixture memory fixture = _newFixture();

    vm.expectEmit(address(fixture.helper));
    emit AccountAuthorized(NewExecutor, ThirdExecutor);
    vm.prank(NewExecutor);
    fixture.helper.authorizeAccount(ThirdExecutor);
    assertTrue(fixture.helper.authorizedAccounts(ThirdExecutor));
    assertEq(fixture.helper.getAuthorizedAccountsCount(), 3);

    vm.expectEmit(address(fixture.helper));
    emit AccountDeauthorized(NewExecutor, OldExecutor);
    vm.prank(NewExecutor);
    fixture.helper.deauthorizeAccount(OldExecutor);

    address[] memory accounts = fixture.helper.getAuthorizedAccounts();
    assertEq(accounts.length, 2);
    assertEq(accounts[0], ThirdExecutor);
    assertEq(accounts[1], NewExecutor);
    assertFalse(fixture.helper.authorizedAccounts(OldExecutor));

    vm.prank(ThirdExecutor);
    fixture.helper.deauthorizeAccount(NewExecutor);
    accounts = fixture.helper.getAuthorizedAccounts();
    assertEq(accounts.length, 1);
    assertEq(accounts[0], ThirdExecutor);
    assertFalse(fixture.helper.authorizedAccounts(NewExecutor));
  }

  function test_authorizationMutation_ValidatesCallerAndAccount() external {
    Fixture memory fixture = _newFixture();

    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    vm.prank(BadCaller);
    fixture.helper.authorizeAccount(ThirdExecutor);

    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    vm.prank(NewExecutor);
    fixture.helper.authorizeAccount(address(0));

    vm.expectRevert(MockArchControllerOwner.AccountAlreadyAuthorized.selector);
    vm.prank(NewExecutor);
    fixture.helper.authorizeAccount(OldExecutor);

    vm.expectRevert(MockArchControllerOwner.AccountNotAuthorized.selector);
    vm.prank(NewExecutor);
    fixture.helper.deauthorizeAccount(ThirdExecutor);
  }

  function test_deauthorizeAccount_RejectsFinalExecutor() external {
    WildcatArchController archController = _deployArchController();
    address[] memory accounts = new address[](1);
    accounts[0] = OldExecutor;
    MockArchControllerOwner helper = _deployHelper(archController, accounts);

    vm.expectRevert(MockArchControllerOwner.CannotRemoveFinalAuthorizedAccount.selector);
    vm.prank(OldExecutor);
    helper.deauthorizeAccount(OldExecutor);
  }

  // ========================================================================== //
  //                          ArchController operations                         //
  // ========================================================================== //

  function test_registerBorrowerAndBatch_ArePermissionless() external {
    Fixture memory fixture = _newFixture();
    address borrower = address(0xB0B);
    vm.prank(BadCaller);
    fixture.helper.registerBorrower(borrower);
    assertTrue(fixture.archController.isRegisteredBorrower(borrower));

    address[] memory borrowers = new address[](2);
    borrowers[0] = address(0xCAFE);
    borrowers[1] = address(0xD00D);
    vm.prank(BadCaller);
    fixture.helper.registerBorrowers(borrowers);
    assertTrue(fixture.archController.isRegisteredBorrower(borrowers[0]));
    assertTrue(fixture.archController.isRegisteredBorrower(borrowers[1]));
  }

  function test_returnOwnership_GivesArchControllerToAuthorizedCaller() external {
    Fixture memory fixture = _newFixture();
    vm.prank(NewExecutor);
    fixture.helper.returnOwnership();
    assertEq(fixture.archController.owner(), NewExecutor);
  }

  function test_executeProtocolAction_CallsArchController() external {
    Fixture memory fixture = _newFixture();
    bytes memory data = abi.encodeCall(
      WildcatArchController.registerControllerFactory,
      (address(fixture.protocolTarget))
    );
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(fixture.archController), data);
    assertTrue(
      fixture.archController.isRegisteredControllerFactory(address(fixture.protocolTarget))
    );
  }

  function test_executeProtocolAction_EmitsForBoundTargetAndReturnsData() external {
    Fixture memory fixture = _newFixture();
    bytes memory data = abi.encodeCall(ArchControllerOwnerProtocolTargetMock.setValue, (42));

    vm.expectEmit(address(fixture.helper));
    emit ProtocolActionExecuted(
      NewExecutor,
      address(fixture.protocolTarget),
      ArchControllerOwnerProtocolTargetMock.setValue.selector
    );
    vm.prank(NewExecutor);
    bytes memory result = fixture.helper.executeProtocolAction(
      address(fixture.protocolTarget),
      data
    );

    assertEq(abi.decode(result, (uint256)), 43);
    assertEq(fixture.protocolTarget.value(), 42);
    assertEq(fixture.protocolTarget.lastCaller(), address(fixture.helper));
  }

  function test_executeProtocolAction_BubblesTargetRevert() external {
    Fixture memory fixture = _newFixture();
    bytes memory data = abi.encodeCall(ArchControllerOwnerProtocolTargetMock.fail, (17));

    vm.expectRevert(
      abi.encodeWithSelector(ArchControllerOwnerProtocolTargetMock.ExpectedFailure.selector, 17)
    );
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(fixture.protocolTarget), data);
  }

  function test_executeProtocolAction_RejectsInvalidTargetOrData() external {
    Fixture memory fixture = _newFixture();
    bytes memory data = abi.encodeCall(ArchControllerOwnerProtocolTargetMock.setValue, (42));

    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(0xBEEF), data);

    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(fixture.helper), data);

    WildcatArchController otherArchController = _deployArchController();
    ArchControllerOwnerProtocolTargetMock wrongArchTarget = _deployProtocolTarget(
      address(otherArchController)
    );
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(wrongArchTarget), data);

    bytes memory archControllerCall = abi.encodeWithSignature('archController()');
    vm.mockCall(address(fixture.protocolTarget), archControllerCall, hex'01');
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(fixture.protocolTarget), data);
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(address(fixture.protocolTarget), archControllerCall, revertData);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(fixture.protocolTarget), data);
    vm.clearMockedCalls();

    vm.expectRevert(MockArchControllerOwner.InvalidProtocolAction.selector);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(address(fixture.protocolTarget), hex'1234');
  }

  function test_executeProtocolAction_RequiresAuthorization() external {
    Fixture memory fixture = _newFixture();
    bytes memory data = abi.encodeCall(ArchControllerOwnerProtocolTargetMock.setValue, (42));
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    vm.prank(BadCaller);
    fixture.helper.executeProtocolAction(address(fixture.protocolTarget), data);
  }

  function test_setProtocolFeeConfiguration_PreservesLegacyCallAndRequiresAuthorization() external {
    Fixture memory fixture = _newFixture();
    address feeRecipient = address(0xFEE);
    vm.prank(NewExecutor);
    fixture.helper.setProtocolFeeConfiguration(
      ILegacyWildcatMarketControllerFactory(address(fixture.legacyFactory)),
      feeRecipient,
      address(0),
      0,
      200
    );

    assertEq(fixture.legacyFactory.feeRecipient(), feeRecipient);
    assertEq(fixture.legacyFactory.originationFeeAsset(), address(0));
    assertEq(fixture.legacyFactory.originationFeeAmount(), 0);
    assertEq(fixture.legacyFactory.protocolFeeBips(), 200);

    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    vm.prank(BadCaller);
    fixture.helper.setProtocolFeeConfiguration(
      ILegacyWildcatMarketControllerFactory(address(fixture.legacyFactory)),
      feeRecipient,
      address(0),
      0,
      500
    );
  }

  // ========================================================================== //
  //                            SphereX handoff                                 //
  // ========================================================================== //

  function test_archControllerSphereXRoles_CanMoveToHelper() external {
    Fixture memory fixture = _newFixture();
    vm.prank(OldExecutor);
    fixture.archController.transferSphereXAdminRole(address(fixture.helper));
    assertEq(fixture.archController.pendingSphereXAdmin(), address(fixture.helper));

    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.archController),
      abi.encodeCall(IWildcatArchController.acceptSphereXAdminRole, ())
    );
    assertEq(fixture.archController.sphereXAdmin(), address(fixture.helper));
    assertEq(fixture.archController.pendingSphereXAdmin(), address(0));

    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.archController),
      abi.encodeCall(IWildcatArchController.changeSphereXOperator, (address(fixture.helper)))
    );
    assertEq(fixture.archController.sphereXOperator(), address(fixture.helper));
    assertEq(fixture.archController.sphereXEngine(), address(fixture.sphereXEngine));
  }

  function test_sphereXEngineRoles_CanMoveToHelper() external {
    Fixture memory fixture = _newFixture();
    vm.prank(OldExecutor);
    fixture.sphereXEngine.beginDefaultAdminTransfer(address(fixture.helper));
    (address pendingAdmin, uint48 acceptSchedule) = fixture.sphereXEngine.pendingDefaultAdmin();
    assertEq(pendingAdmin, address(fixture.helper));

    vm.warp(uint256(acceptSchedule) + 1);
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.sphereXEngine),
      abi.encodeCall(IAccessControlDefaultAdminRules.acceptDefaultAdminTransfer, ())
    );
    assertEq(fixture.sphereXEngine.defaultAdmin(), address(fixture.helper));

    bytes32 operatorRole = fixture.sphereXEngine.OPERATOR_ROLE();
    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.sphereXEngine),
      abi.encodeCall(IAccessControl.grantRole, (operatorRole, address(fixture.helper)))
    );
    assertTrue(fixture.sphereXEngine.hasRole(operatorRole, address(fixture.helper)));

    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.sphereXEngine),
      abi.encodeCall(IAccessControl.revokeRole, (operatorRole, OldExecutor))
    );
    assertFalse(fixture.sphereXEngine.hasRole(operatorRole, OldExecutor));
    assertTrue(
      fixture.sphereXEngine.hasRole(
        fixture.sphereXEngine.SENDER_ADDER_ROLE(),
        address(fixture.archController)
      )
    );
  }

  function test_oldAndNewExecutors_OperateConcurrently() external {
    Fixture memory fixture = _newFixture();
    vm.prank(OldExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.protocolTarget),
      abi.encodeCall(ArchControllerOwnerProtocolTargetMock.setValue, (1))
    );
    assertEq(fixture.protocolTarget.value(), 1);

    vm.prank(NewExecutor);
    fixture.helper.executeProtocolAction(
      address(fixture.protocolTarget),
      abi.encodeCall(ArchControllerOwnerProtocolTargetMock.setValue, (2))
    );
    assertEq(fixture.protocolTarget.value(), 2);
  }
}

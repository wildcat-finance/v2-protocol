// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol';
import 'openzeppelin/contracts/access/IAccessControl.sol';
import 'openzeppelin/contracts/access/IAccessControlDefaultAdminRules.sol';

import 'script/mock/MockArchControllerOwner.sol';
import 'src/interfaces/IWildcatArchController.sol';
import 'src/spherex/ISphereXEngine.sol';

contract AuthorityTestProtocolTarget {
  error ExpectedFailure(uint256 value);

  address public immutable archController;
  address public lastCaller;
  uint256 public value;

  constructor(address archController_) {
    archController = archController_;
  }

  function setValue(uint256 value_) external returns (uint256 result) {
    lastCaller = msg.sender;
    value = value_;
    result = value_ + 1;
  }

  function fail(uint256 value_) external pure {
    revert ExpectedFailure(value_);
  }
}

contract AuthorityTestLegacyFactory {
  error CallerNotArchControllerOwner();

  address public immutable archController;
  address public feeRecipient;
  address public originationFeeAsset;
  uint80 public originationFeeAmount;
  uint16 public protocolFeeBips;

  constructor(address archController_) {
    archController = archController_;
  }

  function setProtocolFeeConfiguration(
    address feeRecipient_,
    address originationFeeAsset_,
    uint80 originationFeeAmount_,
    uint16 protocolFeeBips_
  ) external {
    if (msg.sender != WildcatArchController(archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    feeRecipient = feeRecipient_;
    originationFeeAsset = originationFeeAsset_;
    originationFeeAmount = originationFeeAmount_;
    protocolFeeBips = protocolFeeBips_;
  }
}

contract AuthorityTestSphereXEngine is AccessControlDefaultAdminRules, ISphereXEngine {
  bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
  bytes32 public constant SENDER_ADDER_ROLE = keccak256('SENDER_ADDER_ROLE');

  constructor(
    uint48 initialDelay,
    address initialDefaultAdmin
  ) AccessControlDefaultAdminRules(initialDelay, initialDefaultAdmin) {
    _grantRole(OPERATOR_ROLE, initialDefaultAdmin);
  }

  function sphereXValidatePre(
    int256,
    address,
    bytes calldata
  ) external pure override returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  function sphereXValidatePost(
    int256,
    uint256,
    bytes32[] calldata,
    bytes32[] calldata
  ) external pure override {}

  function sphereXValidateInternalPre(
    int256
  ) external pure override returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  function sphereXValidateInternalPost(
    int256,
    uint256,
    bytes32[] calldata,
    bytes32[] calldata
  ) external pure override {}

  function addAllowedSenderOnChain(address) external override onlyRole(SENDER_ADDER_ROLE) {}

  function supportsInterface(
    bytes4 interfaceId
  ) public view override(AccessControlDefaultAdminRules, ISphereXEngine) returns (bool) {
    return interfaceId == type(ISphereXEngine).interfaceId || super.supportsInterface(interfaceId);
  }
}

contract MockArchControllerOwnerTest is Test {
  event AccountAuthorized(address indexed authorizer, address indexed account);
  event AccountDeauthorized(address indexed authorizer, address indexed account);
  event ProtocolActionExecuted(
    address indexed executor,
    address indexed target,
    bytes4 indexed selector
  );

  address internal constant OLD_EXECUTOR = 0xca732651410E915090d7A7D889A1E44eF4575fcE;
  address internal constant NEW_EXECUTOR = 0xCa7007a75296b532Ce1606d9e130eAa849800Ca7;
  address internal constant THIRD_EXECUTOR = address(0xA11CE);

  WildcatArchController internal archController;
  MockArchControllerOwner internal helper;
  AuthorityTestProtocolTarget internal protocolTarget;
  AuthorityTestLegacyFactory internal legacyFactory;
  AuthorityTestSphereXEngine internal sphereXEngine;

  function setUp() external {
    vm.prank(OLD_EXECUTOR);
    archController = new WildcatArchController();

    sphereXEngine = new AuthorityTestSphereXEngine(1 hours, OLD_EXECUTOR);
    bytes32 senderAdderRole = sphereXEngine.SENDER_ADDER_ROLE();
    vm.prank(OLD_EXECUTOR);
    sphereXEngine.grantRole(senderAdderRole, address(archController));

    vm.prank(OLD_EXECUTOR);
    archController.changeSphereXOperator(OLD_EXECUTOR);
    vm.prank(OLD_EXECUTOR);
    archController.changeSphereXEngine(address(sphereXEngine));

    address[] memory initialExecutors = new address[](2);
    initialExecutors[0] = OLD_EXECUTOR;
    initialExecutors[1] = NEW_EXECUTOR;
    vm.prank(OLD_EXECUTOR);
    helper = new MockArchControllerOwner(address(archController), initialExecutors);

    vm.prank(OLD_EXECUTOR);
    archController.transferOwnership(address(helper));

    protocolTarget = new AuthorityTestProtocolTarget(address(archController));
    legacyFactory = new AuthorityTestLegacyFactory(address(archController));
  }

  function test_constructorRecordsExplicitExecutors() external view {
    assertEq(address(helper.archController()), address(archController));
    assertEq(helper.version(), '2');
    assertTrue(helper.authorizedAccounts(OLD_EXECUTOR));
    assertTrue(helper.authorizedAccounts(NEW_EXECUTOR));
    assertEq(helper.getAuthorizedAccountsCount(), 2);

    address[] memory accounts = helper.getAuthorizedAccounts();
    assertEq(accounts.length, 2);
    assertEq(accounts[0], OLD_EXECUTOR);
    assertEq(accounts[1], NEW_EXECUTOR);
  }

  function test_constructorRejectsInvalidInputs() external {
    address[] memory emptyExecutors = new address[](0);
    vm.expectRevert(MockArchControllerOwner.InvalidInitialExecutors.selector);
    new MockArchControllerOwner(address(archController), emptyExecutors);

    address[] memory oneExecutor = new address[](1);
    oneExecutor[0] = OLD_EXECUTOR;
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    new MockArchControllerOwner(address(0), oneExecutor);

    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    new MockArchControllerOwner(address(0xBEEF), oneExecutor);

    oneExecutor[0] = address(0);
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    new MockArchControllerOwner(address(archController), oneExecutor);

    address[] memory duplicateExecutors = new address[](2);
    duplicateExecutors[0] = OLD_EXECUTOR;
    duplicateExecutors[1] = OLD_EXECUTOR;
    vm.expectRevert(MockArchControllerOwner.AccountAlreadyAuthorized.selector);
    new MockArchControllerOwner(address(archController), duplicateExecutors);
  }

  function test_authorizeAndDeauthorizeAccounts() external {
    vm.expectEmit(true, true, false, true, address(helper));
    emit AccountAuthorized(NEW_EXECUTOR, THIRD_EXECUTOR);
    vm.prank(NEW_EXECUTOR);
    helper.authorizeAccount(THIRD_EXECUTOR);

    assertTrue(helper.authorizedAccounts(THIRD_EXECUTOR));
    assertEq(helper.getAuthorizedAccountsCount(), 3);

    vm.expectEmit(true, true, false, true, address(helper));
    emit AccountDeauthorized(NEW_EXECUTOR, OLD_EXECUTOR);
    vm.prank(NEW_EXECUTOR);
    helper.deauthorizeAccount(OLD_EXECUTOR);

    assertFalse(helper.authorizedAccounts(OLD_EXECUTOR));
    assertTrue(helper.authorizedAccounts(NEW_EXECUTOR));
    assertTrue(helper.authorizedAccounts(THIRD_EXECUTOR));
    assertEq(helper.getAuthorizedAccountsCount(), 2);

    address[] memory accounts = helper.getAuthorizedAccounts();
    assertEq(accounts[0], THIRD_EXECUTOR);
    assertEq(accounts[1], NEW_EXECUTOR);
  }

  function test_authorizationGuardsAndValidation() external {
    vm.prank(address(0xBAD));
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.authorizeAccount(THIRD_EXECUTOR);

    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    helper.authorizeAccount(address(0));

    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.AccountAlreadyAuthorized.selector);
    helper.authorizeAccount(OLD_EXECUTOR);

    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.AccountNotAuthorized.selector);
    helper.deauthorizeAccount(THIRD_EXECUTOR);
  }

  function test_cannotRemoveFinalAuthorizedAccount() external {
    address[] memory initialExecutors = new address[](1);
    initialExecutors[0] = OLD_EXECUTOR;
    MockArchControllerOwner singleExecutorHelper = new MockArchControllerOwner(
      address(archController),
      initialExecutors
    );

    vm.prank(OLD_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.CannotRemoveFinalAuthorizedAccount.selector);
    singleExecutorHelper.deauthorizeAccount(OLD_EXECUTOR);
  }

  function test_registerBorrowerIsPermissionless() external {
    address borrower = address(0xB0B);
    vm.prank(address(0xBAD));
    helper.registerBorrower(borrower);
    assertTrue(archController.isRegisteredBorrower(borrower));
  }

  function test_registerBorrowersIsPermissionless() external {
    address[] memory borrowers = new address[](2);
    borrowers[0] = address(0xB0B);
    borrowers[1] = address(0xCAFE);
    vm.prank(address(0xBAD));
    helper.registerBorrowers(borrowers);
    assertTrue(archController.isRegisteredBorrower(borrowers[0]));
    assertTrue(archController.isRegisteredBorrower(borrowers[1]));
  }

  function test_returnOwnershipToAuthorizedCaller() external {
    vm.prank(NEW_EXECUTOR);
    helper.returnOwnership();
    assertEq(archController.owner(), NEW_EXECUTOR);
  }

  function test_executeProtocolActionOnArchController() external {
    bytes memory data = abi.encodeCall(
      WildcatArchController.registerControllerFactory,
      (address(protocolTarget))
    );
    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(address(archController), data);
    assertTrue(archController.isRegisteredControllerFactory(address(protocolTarget)));
  }

  function test_executeProtocolActionOnBoundTargetReturnsData() external {
    bytes memory data = abi.encodeCall(AuthorityTestProtocolTarget.setValue, (42));

    vm.expectEmit(true, true, true, true, address(helper));
    emit ProtocolActionExecuted(
      NEW_EXECUTOR,
      address(protocolTarget),
      AuthorityTestProtocolTarget.setValue.selector
    );
    vm.prank(NEW_EXECUTOR);
    bytes memory result = helper.executeProtocolAction(address(protocolTarget), data);

    assertEq(abi.decode(result, (uint256)), 43);
    assertEq(protocolTarget.value(), 42);
    assertEq(protocolTarget.lastCaller(), address(helper));
  }

  function test_executeProtocolActionBubblesRevertData() external {
    bytes memory data = abi.encodeCall(AuthorityTestProtocolTarget.fail, (17));
    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(
      abi.encodeWithSelector(AuthorityTestProtocolTarget.ExpectedFailure.selector, 17)
    );
    helper.executeProtocolAction(address(protocolTarget), data);
  }

  function test_executeProtocolActionRejectsInvalidTargetsAndData() external {
    bytes memory data = abi.encodeCall(AuthorityTestProtocolTarget.setValue, (42));

    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    helper.executeProtocolAction(address(0xBEEF), data);

    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    helper.executeProtocolAction(address(helper), data);

    vm.prank(OLD_EXECUTOR);
    WildcatArchController otherArchController = new WildcatArchController();
    AuthorityTestProtocolTarget wrongArchTarget = new AuthorityTestProtocolTarget(
      address(otherArchController)
    );
    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    helper.executeProtocolAction(address(wrongArchTarget), data);

    vm.prank(NEW_EXECUTOR);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolAction.selector);
    helper.executeProtocolAction(address(protocolTarget), hex'1234');
  }

  function test_executeProtocolActionRequiresAuthorization() external {
    bytes memory data = abi.encodeCall(AuthorityTestProtocolTarget.setValue, (42));
    vm.prank(address(0xBAD));
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.executeProtocolAction(address(protocolTarget), data);
  }

  function test_legacyProtocolFeeConfigurationIsPreservedAndRestricted() external {
    address feeRecipient = address(0xFEE);
    vm.prank(NEW_EXECUTOR);
    helper.setProtocolFeeConfiguration(
      ILegacyWildcatMarketControllerFactory(address(legacyFactory)),
      feeRecipient,
      address(0),
      0,
      200
    );

    assertEq(legacyFactory.feeRecipient(), feeRecipient);
    assertEq(legacyFactory.originationFeeAsset(), address(0));
    assertEq(legacyFactory.originationFeeAmount(), 0);
    assertEq(legacyFactory.protocolFeeBips(), 200);

    vm.prank(address(0xBAD));
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.setProtocolFeeConfiguration(
      ILegacyWildcatMarketControllerFactory(address(legacyFactory)),
      feeRecipient,
      address(0),
      0,
      500
    );
  }

  function test_archControllerSphereXRolesCanMoveToHelper() external {
    vm.prank(OLD_EXECUTOR);
    archController.transferSphereXAdminRole(address(helper));
    assertEq(archController.pendingSphereXAdmin(), address(helper));

    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(
      address(archController),
      abi.encodeCall(IWildcatArchController.acceptSphereXAdminRole, ())
    );
    assertEq(archController.sphereXAdmin(), address(helper));
    assertEq(archController.pendingSphereXAdmin(), address(0));

    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(
      address(archController),
      abi.encodeCall(IWildcatArchController.changeSphereXOperator, (address(helper)))
    );
    assertEq(archController.sphereXOperator(), address(helper));
    assertEq(archController.sphereXEngine(), address(sphereXEngine));
  }

  function test_sphereXEngineRolesCanMoveToHelper() external {
    vm.prank(OLD_EXECUTOR);
    sphereXEngine.beginDefaultAdminTransfer(address(helper));
    (address pendingAdmin, uint48 acceptSchedule) = sphereXEngine.pendingDefaultAdmin();
    assertEq(pendingAdmin, address(helper));

    vm.warp(uint256(acceptSchedule) + 1);
    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(
      address(sphereXEngine),
      abi.encodeCall(IAccessControlDefaultAdminRules.acceptDefaultAdminTransfer, ())
    );
    assertEq(sphereXEngine.defaultAdmin(), address(helper));

    bytes32 operatorRole = sphereXEngine.OPERATOR_ROLE();
    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(
      address(sphereXEngine),
      abi.encodeCall(IAccessControl.grantRole, (operatorRole, address(helper)))
    );
    assertTrue(sphereXEngine.hasRole(operatorRole, address(helper)));

    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(
      address(sphereXEngine),
      abi.encodeCall(IAccessControl.revokeRole, (operatorRole, OLD_EXECUTOR))
    );
    assertFalse(sphereXEngine.hasRole(operatorRole, OLD_EXECUTOR));
    assertTrue(sphereXEngine.hasRole(sphereXEngine.SENDER_ADDER_ROLE(), address(archController)));
  }

  function test_oldAndNewExecutorsCanOperateConcurrently() external {
    vm.prank(OLD_EXECUTOR);
    helper.executeProtocolAction(
      address(protocolTarget),
      abi.encodeCall(AuthorityTestProtocolTarget.setValue, (1))
    );
    assertEq(protocolTarget.value(), 1);

    vm.prank(NEW_EXECUTOR);
    helper.executeProtocolAction(
      address(protocolTarget),
      abi.encodeCall(AuthorityTestProtocolTarget.setValue, (2))
    );
    assertEq(protocolTarget.value(), 2);
  }
}

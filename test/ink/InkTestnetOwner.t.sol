// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from 'forge-std/Test.sol';
import { SafeHarness } from './InkDeployment.t.sol';
import {
  InkDeployment,
  MockArchControllerOwner,
  WildcatArchController,
  HooksFactory,
  SphereXEngine
} from '../../script/ink/InkDeployment.sol';
import { HooksTemplate, IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';

contract InkTestnetOwnerTest is Test, InkDeployment {
  address internal constant DEPLOYER = address(0xDE9107);
  address internal constant NEXT_EXECUTOR = address(0xA11CE);
  address internal constant PUBLIC_CALLER = address(0xCA11);
  Config internal c;
  Deployment internal d;
  MockArchControllerOwner internal helper;

  function setUp() public {
    vm.chainId(TESTNET);
    vm.warp(1_800_000_000);
    vm.deal(DEPLOYER, 100 ether);
    c.chainId = TESTNET;
    c.deployer = DEPLOYER;
    c.expectedNonce = vm.getNonce(DEPLOYER);
    c.feeRecipient = address(0xFEE);
    c.protocolFeeBips = 500;
    c.sanctions.push(address(0xBAD1));
    d = _deploy(c);
    helper = MockArchControllerOwner(d.testnetOwner);
  }

  function verifyForTest() external view {
    _verify(c, d);
  }

  function _newOpenTemplate() internal returns (address) {
    return
      _store('ExtraOpenTermHooks', 'OpenTermHooks.sol:OpenTermHooks', vm.getCode('OpenTermHooks.sol:OpenTermHooks'));
  }

  function _addData(address template) internal view returns (bytes memory) {
    return abi.encodeCall(
      HooksFactory.addHooksTemplate, (template, 'ExtraOpenTermHooks', c.feeRecipient, address(0), 0, uint16(500))
    );
  }

  function test_constructorRejectsLegacyArgumentsAndInvalidExecutors() public {
    bytes memory initCode = abi.encodePacked(
      vm.getCode('MockArchControllerOwner.sol:MockArchControllerOwner'), abi.encode(d.archController, d.hooksFactory)
    );
    address deployed;
    assembly { deployed := create(0, add(initCode, 32), mload(initCode)) }
    assertEq(deployed, address(0));

    address[] memory executors = new address[](0);
    vm.expectRevert(MockArchControllerOwner.InvalidInitialExecutors.selector);
    new MockArchControllerOwner(d.archController, executors);
    executors = new address[](1);
    vm.expectRevert(MockArchControllerOwner.ZeroAddress.selector);
    new MockArchControllerOwner(d.archController, executors);
    executors = new address[](2);
    executors[0] = executors[1] = DEPLOYER;
    vm.expectRevert(MockArchControllerOwner.AccountAlreadyAuthorized.selector);
    new MockArchControllerOwner(d.archController, executors);
  }

  function test_publicBorrowerBatchRegistration() public {
    address[] memory borrowers = new address[](2);
    borrowers[0] = address(0xCAFE);
    borrowers[1] = address(0xD00D);
    vm.prank(PUBLIC_CALLER);
    helper.registerBorrowers(borrowers);
    WildcatArchController arch = WildcatArchController(d.archController);
    assertTrue(arch.isRegisteredBorrower(borrowers[0]));
    assertTrue(arch.isRegisteredBorrower(borrowers[1]));
  }

  function test_forwardedAddUpdateAndDisableWorkOnV21Factory() public {
    address template = _newOpenTemplate();
    vm.startPrank(DEPLOYER);
    helper.executeProtocolAction(d.hooksFactory, _addData(template));
    helper.executeProtocolAction(
      d.hooksFactory,
      abi.encodeCall(HooksFactory.updateHooksTemplateFees, (template, NEXT_EXECUTOR, address(0), 0, uint16(250)))
    );
    helper.executeProtocolAction(d.hooksFactory, abi.encodeCall(HooksFactory.disableHooksTemplate, (template)));
    vm.stopPrank();
    HooksTemplate memory details = HooksFactory(d.hooksFactory).getHooksTemplateDetails(template);
    assertTrue(details.exists);
    assertFalse(details.enabled);
    assertEq(details.feeRecipient, NEXT_EXECUTOR);
    assertEq(details.protocolFeeBips, 250);
    assertEq(WildcatArchController(d.archController).owner(), address(helper));
  }

  function test_legacyHooksSelectorsAreNotHelperEntrypoints() public {
    bytes[] memory calls = new bytes[](3);
    calls[0] = _addData(_newOpenTemplate());
    calls[1] = abi.encodeCall(
      HooksFactory.updateHooksTemplateFees, (d.openTermHooks, c.feeRecipient, address(0), 0, uint16(500))
    );
    calls[2] = abi.encodeCall(HooksFactory.disableHooksTemplate, (d.openTermHooks));
    vm.startPrank(DEPLOYER);
    for (uint256 i; i < calls.length; ++i) {
      (bool ok,) = address(helper).call(calls[i]);
      assertFalse(ok);
    }
    vm.stopPrank();
  }

  function test_adminActionsRejectUnauthorizedCaller() public {
    bytes memory data = _addData(_newOpenTemplate());
    vm.startPrank(PUBLIC_CALLER);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.executeProtocolAction(d.hooksFactory, data);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.authorizeAccount(PUBLIC_CALLER);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.deauthorizeAccount(DEPLOYER);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.returnOwnership();
    vm.stopPrank();
  }

  function test_forwardingPreservesFactoryRevertsAndReturnData() public {
    bytes memory data = _addData(d.openTermHooks);
    vm.startPrank(DEPLOYER);
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateAlreadyExists.selector);
    helper.executeProtocolAction(d.hooksFactory, data);
    bytes memory result = helper.executeProtocolAction(d.hooksFactory, abi.encodeCall(HooksFactory.archController, ()));
    assertEq(abi.decode(result, (address)), d.archController);
    vm.stopPrank();
  }

  function test_targetValidationAcceptsSameControllerFactoryOnly() public {
    HooksFactory second = new HooksFactory(d.archController, d.sanctionsSentinel, d.marketInitCodeStorage, 0);
    WildcatArchController otherArch = new WildcatArchController();
    HooksFactory foreign = new HooksFactory(address(otherArch), d.sanctionsSentinel, d.marketInitCodeStorage, 0);
    address template = _newOpenTemplate();
    bytes memory data = _addData(template);
    vm.startPrank(DEPLOYER);
    helper.executeProtocolAction(address(second), data);
    assertTrue(second.isHooksTemplate(template));
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    helper.executeProtocolAction(address(foreign), data);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    helper.executeProtocolAction(PUBLIC_CALLER, data);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolTarget.selector);
    helper.executeProtocolAction(address(helper), data);
    vm.expectRevert(MockArchControllerOwner.InvalidProtocolAction.selector);
    helper.executeProtocolAction(d.hooksFactory, hex'123456');
    vm.stopPrank();
  }

  function test_safeExecutorKeepsHelperOwnershipAndDeployerAuthorization() public {
    SafeHarness safe = new SafeHarness();
    vm.prank(DEPLOYER);
    helper.authorizeAccount(address(safe));
    safe.execute(
      address(helper),
      abi.encodeCall(
        MockArchControllerOwner.executeProtocolAction,
        (
          d.hooksFactory,
          abi.encodeCall(
            HooksFactory.updateHooksTemplateFees, (d.openTermHooks, c.feeRecipient, address(0), 0, uint16(250))
          )
        )
      )
    );
    assertEq(HooksFactory(d.hooksFactory).getHooksTemplateDetails(d.openTermHooks).protocolFeeBips, 250);
    assertTrue(helper.authorizedAccounts(DEPLOYER));
    assertTrue(helper.authorizedAccounts(address(safe)));
    assertEq(helper.getAuthorizedAccountsCount(), 2);
    WildcatArchController arch = WildcatArchController(d.archController);
    assertEq(arch.owner(), address(helper));
    assertEq(arch.sphereXAdmin(), DEPLOYER);
    assertEq(SphereXEngine(d.sphereXEngine).defaultAdmin(), DEPLOYER);
    vm.prank(PUBLIC_CALLER);
    helper.registerBorrower(PUBLIC_CALLER);
    assertTrue(arch.isRegisteredBorrower(PUBLIC_CALLER));
  }

  function test_executorRotationAndOwnershipRecovery() public {
    vm.prank(DEPLOYER);
    helper.authorizeAccount(NEXT_EXECUTOR);
    vm.startPrank(NEXT_EXECUTOR);
    helper.deauthorizeAccount(DEPLOYER);
    vm.expectRevert(MockArchControllerOwner.CannotRemoveFinalAuthorizedAccount.selector);
    helper.deauthorizeAccount(NEXT_EXECUTOR);
    helper.returnOwnership();
    vm.stopPrank();
    assertFalse(helper.authorizedAccounts(DEPLOYER));
    assertEq(helper.getAuthorizedAccountsCount(), 1);
    assertEq(helper.getAuthorizedAccounts()[0], NEXT_EXECUTOR);
    assertEq(WildcatArchController(d.archController).owner(), NEXT_EXECUTOR);
    vm.prank(DEPLOYER);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.returnOwnership();
  }

  function test_eoaExecutorCanRetireDeployerAndKeepHelperOwnership() public {
    _exerciseExecutorRetirement(NEXT_EXECUTOR);
  }

  function test_safeExecutorCanRetireDeployerAndKeepHelperOwnership() public {
    _exerciseExecutorRetirement(address(new SafeHarness()));
  }

  function _executorCall(address executor, bytes memory data) internal {
    if (executor.code.length != 0) {
      SafeHarness(executor).execute(address(helper), data);
    } else {
      vm.prank(executor);
      (bool ok, bytes memory result) = address(helper).call(data);
      if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }
  }

  function _exerciseExecutorRetirement(address executor) internal {
    vm.prank(DEPLOYER);
    helper.authorizeAccount(executor);
    // the live proof repeats the current owner, exercising both permission gates without moving ownership.
    bytes memory proof = abi.encodeCall(
      MockArchControllerOwner.executeProtocolAction,
      (d.archController, abi.encodeWithSignature('transferOwnership(address)', address(helper)))
    );
    _executorCall(executor, proof);
    assertTrue(helper.authorizedAccounts(DEPLOYER));
    _executorCall(executor, abi.encodeCall(MockArchControllerOwner.deauthorizeAccount, (DEPLOYER)));
    _executorCall(executor, proof);
    assertEq(helper.getAuthorizedAccountsCount(), 1);
    assertEq(helper.getAuthorizedAccounts()[0], executor);
    assertFalse(helper.authorizedAccounts(DEPLOYER));
    vm.startPrank(DEPLOYER);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.executeProtocolAction(d.archController, abi.encodeWithSignature('transferOwnership(address)', DEPLOYER));
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.authorizeAccount(DEPLOYER);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.deauthorizeAccount(executor);
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.returnOwnership();
    vm.stopPrank();
    _executorCall(
      executor,
      abi.encodeCall(
        MockArchControllerOwner.executeProtocolAction,
        (
          d.hooksFactory,
          abi.encodeCall(
            HooksFactory.updateHooksTemplateFees, (d.openTermHooks, c.feeRecipient, address(0), 0, uint16(250))
          )
        )
      )
    );
    assertEq(HooksFactory(d.hooksFactory).getHooksTemplateDetails(d.openTermHooks).protocolFeeBips, 250);
    vm.prank(PUBLIC_CALLER);
    helper.registerBorrower(PUBLIC_CALLER);
    WildcatArchController arch = WildcatArchController(d.archController);
    assertTrue(arch.isRegisteredBorrower(PUBLIC_CALLER));
    assertEq(arch.owner(), address(helper));
    // executor retirement is not a SphereX handoff.
    assertEq(arch.sphereXAdmin(), DEPLOYER);
    assertEq(SphereXEngine(d.sphereXEngine).defaultAdmin(), DEPLOYER);
  }

  function test_helperOwnershipDoesNotGrantSphereXRoles() public {
    WildcatArchController arch = WildcatArchController(d.archController);
    SphereXEngine engine = SphereXEngine(d.sphereXEngine);
    assertEq(arch.sphereXAdmin(), DEPLOYER);
    assertEq(arch.sphereXOperator(), DEPLOYER);
    assertEq(engine.defaultAdmin(), DEPLOYER);
    assertFalse(engine.hasRole(engine.OPERATOR_ROLE(), address(helper)));
    vm.startPrank(DEPLOYER);
    vm.expectRevert();
    helper.executeProtocolAction(
      d.archController, abi.encodeWithSignature('changeSphereXOperator(address)', NEXT_EXECUTOR)
    );
    vm.expectRevert();
    helper.executeProtocolAction(d.sphereXEngine, abi.encodeWithSignature('deactivateAllRules()'));
    vm.stopPrank();
  }

  function test_bootstrapVerificationRejectsExtraOrReplacedExecutor() public {
    vm.prank(DEPLOYER);
    helper.authorizeAccount(NEXT_EXECUTOR);
    vm.expectRevert('Ink: helper executor count');
    this.verifyForTest();
    vm.prank(NEXT_EXECUTOR);
    helper.deauthorizeAccount(DEPLOYER);
    vm.expectRevert('Ink: helper executor');
    this.verifyForTest();
  }

  function test_bootstrapVerificationRejectsWrongHelperBindingAndVersion() public {
    vm.mockCall(address(helper), abi.encodeWithSignature('archController()'), abi.encode(address(0xBAD)));
    vm.expectRevert('Ink: helper arch');
    this.verifyForTest();
    vm.clearMockedCalls();
    vm.mockCall(address(helper), abi.encodeWithSignature('version()'), abi.encode('1'));
    vm.expectRevert('Ink: helper version');
    this.verifyForTest();
    vm.clearMockedCalls();
  }
}

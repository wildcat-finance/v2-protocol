// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from 'forge-std/Test.sol';
import { HandoffInk } from '../../script/ink/HandoffInk.s.sol';
import {
  InkDeployment,
  WildcatArchController,
  WildcatSanctionsSentinel,
  ChainalysisProxy,
  WildcatCopyOfChainalysisList,
  WildcatFeeRecipient,
  SphereXEngine,
  OpenAccessRoleProvider,
  HooksFactory,
  Wildcat4626WrapperFactory,
  MockArchControllerOwner
} from '../../script/ink/InkDeployment.sol';
import { SphereXPatterns } from '../../script/ink/SphereXPatterns.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { HooksConfig, LibHooksConfig } from 'src/types/HooksConfig.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

contract SafeHarness {
  function getThreshold() external pure returns (uint256) {
    return 1;
  }

  function execute(address target, bytes memory data) external {
    (bool ok, bytes memory result) = target.call(data);
    if (!ok) assembly { revert(add(result, 32), mload(result)) }
  }
}

contract InkDeploymentTest is Test, HandoffInk {
  using LibHooksConfig for HooksConfig;
  address internal constant DEPLOYER = address(0xDE9107);
  address internal constant BORROWER = address(0xB0440);
  address internal constant LENDER = address(0xA11CE);

  function config(uint256 chain) internal returns (Config memory c) {
    vm.chainId(chain);
    vm.warp(1_800_000_000);
    vm.deal(DEPLOYER, 100 ether);
    c.chainId = chain;
    c.deployer = DEPLOYER;
    c.expectedNonce = vm.getNonce(DEPLOYER);
    c.deployFeeRecipient = true;
    c.feeRecipient = address(0xFEE);
    c.protocolFeeBips = 500;
    c.sanctions = new address[](2);
    c.sanctions[0] = address(0xBAD1);
    c.sanctions[1] = address(0xBAD2);
  }

  function deployForTest(Config memory c) external returns (Deployment memory) {
    return _deploy(c);
  }

  function verifyForTest(Config memory c, Deployment memory d) external view {
    _verify(c, d);
  }

  function nominateForTest(Config memory c, Deployment memory d, address safe) external {
    _nominate(c, d, safe);
  }

  function finishForTest(
    Config memory c,
    Deployment memory d,
    address safe,
    address updater,
    address treasury
  )
    external
  {
    _finish(c, d, safe, updater, treasury);
  }

  function test_mainnetBootstrapAndCandidateRoundtrip() public {
    Config memory c = config(MAINNET);
    Deployment memory d = _deploy(c);
    assertEq(records.length, 13);
    assertEq(WildcatArchController(d.archController).getRegisteredMarkets().length, 0);
    assertEq(d.testnetOwner, address(0));
    string memory output = './deployments/ink/runs/test-candidate.json';
    vm.createDir('./deployments/ink/runs', true);
    _writeCandidate(c, d, output);
    Deployment memory parsed = _readDeployment(vm.readFile(output));
    assertEq(keccak256(abi.encode(parsed)), keccak256(abi.encode(d)));
    vm.removeFile(output);
  }

  function test_testnetUsesHelperEvenWithRealMirrorAndEngine() public {
    Config memory c = config(TESTNET);
    Deployment memory d = _deploy(c);
    assertEq(records.length, 14);
    MockArchControllerOwner helper = MockArchControllerOwner(d.testnetOwner);
    assertEq(helper.version(), '2');
    assertEq(address(helper.archController()), d.archController);
    address[] memory executors = helper.getAuthorizedAccounts();
    assertEq(executors.length, 1);
    assertEq(executors[0], DEPLOYER);
    assertTrue(helper.authorizedAccounts(DEPLOYER));
    assertFalse(helper.authorizedAccounts(address(this)));
    assertFalse(helper.authorizedAccounts(c.feeRecipient));
    assertEq(records[records.length - 1].constructorArgs, abi.encode(d.archController, executors));
    vm.prank(address(0xCA11));
    helper.registerBorrower(BORROWER);
    assertTrue(WildcatArchController(d.archController).isRegisteredBorrower(BORROWER));
    assertEq(ChainalysisProxy(d.sanctionsAdapter).owner(), DEPLOYER);
    assertEq(WildcatCopyOfChainalysisList(d.sanctionsList).owner(), DEPLOYER);
    vm.prank(address(0xCA11));
    vm.expectRevert(MockArchControllerOwner.NotAuthorized.selector);
    helper.returnOwnership();
  }

  function test_externalFeeDestinationIsExplicitAndNoForwarderIsDeployed() public {
    Config memory c = config(MAINNET);
    c.deployFeeRecipient = false;
    Deployment memory d = _deploy(c);
    assertEq(records.length, 12);
    assertEq(d.feeRecipient, c.feeRecipient);
  }

  function test_preflightRejectsWrongChainNonceEmptyAndDuplicateSnapshot() public {
    Config memory c = config(MAINNET);
    vm.chainId(31337);
    vm.expectRevert('Ink: wrong chain');
    this.deployForTest(c);
    vm.chainId(MAINNET);
    c.expectedNonce++;
    vm.expectRevert('Ink: nonce changed; do not rerun');
    this.deployForTest(c);
    c.expectedNonce--;
    c.sanctions[1] = c.sanctions[0];
    vm.expectRevert('Ink: sanctions must be sorted, unique, nonzero');
    this.deployForTest(c);
    c.sanctions = new address[](0);
    vm.expectRevert('Ink: empty sanctions snapshot');
    this.deployForTest(c);
    c.sanctions = new address[](1);
    c.sanctions[0] = address(1);
    c.feeRecipient = address(0);
    vm.expectRevert('Ink: explicit fee recipient required');
    this.deployForTest(c);
  }

  function test_batchesLargeSnapshot() public {
    Config memory c = config(TESTNET);
    c.sanctions = new address[](205);
    for (uint256 i; i < c.sanctions.length; ++i) {
      c.sanctions[i] = address(uint160(i + 1));
    }
    Deployment memory d = _deploy(c);
    assertEq(WildcatCopyOfChainalysisList(d.sanctionsList).getSanctionedAddressesCount(), 205);
  }

  function test_feeAboveFactoryLimitFailsBeforeAnyDeployment() public {
    Config memory c = config(MAINNET);
    uint64 nonce = vm.getNonce(DEPLOYER);
    c.protocolFeeBips = 1001;
    vm.expectRevert('Ink: invalid fee');
    this.deployForTest(c);
    assertEq(vm.getNonce(DEPLOYER), nonce);
    assertEq(records.length, 0);
    c.protocolFeeBips = 1000;
    Deployment memory d = _deploy(c);
    assertEq(HooksFactory(d.hooksFactory).getHooksTemplateDetails(d.openTermHooks).protocolFeeBips, 1000);
  }

  function _market(Deployment memory d, bool fixedTerm) internal returns (WildcatMarket market, MockERC20 token) {
    if (d.testnetOwner == address(0)) {
      vm.prank(DEPLOYER);
      WildcatArchController(d.archController).registerBorrower(BORROWER);
    } else {
      vm.prank(BORROWER);
      MockArchControllerOwner(d.testnetOwner).registerBorrower(BORROWER);
    }
    token = new MockERC20('Ink rehearsal only', 'TEST', 18);
    vm.startPrank(BORROWER);
    HooksFactory factory = HooksFactory(d.hooksFactory);
    address hooks = factory.deployHooksInstance(fixedTerm ? d.fixedTermHooks : d.openTermHooks, '');
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(token),
      namePrefix: 'Wildcat ',
      symbolPrefix: 'WC',
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1000,
      delinquencyFeeBips: 1000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 1000,
      delinquencyGracePeriod: 1 days,
      hooks: HooksConfig.wrap(0).setHooksAddress(hooks)
    });
    bytes memory hooksData = fixedTerm
      ? abi.encode(uint32(block.timestamp + 30 days), uint128(0), false, true, true)
      : abi.encode(uint128(0), false);
    market = WildcatMarket(factory.deployMarket(inputs, hooksData, bytes32(uint256(1)), address(0), 0));
    vm.stopPrank();
  }

  function test_openTermAndWrapperWithActiveSphereXAndSanctions() public {
    _checkOpenTermAndWrapper(MAINNET);
  }

  function test_testnetOpenTermAndWrapperWithActiveSphereXAndSanctions() public {
    _checkOpenTermAndWrapper(TESTNET);
  }

  function _checkOpenTermAndWrapper(uint256 chain) internal {
    Config memory c = config(chain);
    Deployment memory d = _deploy(c);
    (WildcatMarket market, MockERC20 token) = _market(d, false);
    Wildcat4626Wrapper wrapper =
      Wildcat4626Wrapper(Wildcat4626WrapperFactory(d.wrapperFactory).createWrapper(address(market)));
    token.mint(LENDER, 10e18);
    vm.startPrank(LENDER);
    token.approve(address(market), type(uint256).max);
    market.deposit(10e18);
    market.approve(address(wrapper), type(uint256).max);
    wrapper.deposit(4e18, LENDER);
    wrapper.redeem(2e18, LENDER, LENDER);
    wrapper.transfer(address(0xB0B), 1e18);
    vm.stopPrank();
    assertEq(wrapper.balanceOf(LENDER), 1e18);
    assertEq(market.balanceOf(LENDER), 8e18);

    address[] memory denied = new address[](1);
    denied[0] = LENDER;
    vm.prank(DEPLOYER);
    WildcatCopyOfChainalysisList(d.sanctionsList).addToSanctionsList(denied);
    assertTrue(WildcatSanctionsSentinel(d.sanctionsSentinel).isSanctioned(BORROWER, LENDER));
    assertEq(OpenAccessRoleProvider(d.openAccessRoleProvider).getCredential(LENDER), 0);
    vm.prank(LENDER);
    vm.expectRevert();
    wrapper.deposit(1e18, LENDER);
    vm.prank(DEPLOYER);
    WildcatCopyOfChainalysisList(d.sanctionsList).removeFromSanctionsList(denied);
    vm.prank(LENDER);
    wrapper.deposit(1e18, LENDER);

    vm.prank(DEPLOYER);
    SphereXEngine(d.sphereXEngine).removeAllowedPatterns(SphereXPatterns.getPatterns());
    vm.prank(LENDER);
    vm.expectRevert(bytes4(keccak256('TransferFailed()')));
    wrapper.redeem(1e18, LENDER, LENDER);
    vm.prank(LENDER);
    vm.expectRevert('SphereX error: disallowed tx pattern');
    market.transfer(address(0xB0B), 1e18);
  }

  function test_fixedTermMarketCanDeployAndDepositWithActiveSphereX() public {
    _checkFixedTermMarket(MAINNET);
  }

  function test_testnetFixedTermMarketCanDeployAndDepositWithActiveSphereX() public {
    _checkFixedTermMarket(TESTNET);
  }

  function _checkFixedTermMarket(uint256 chain) internal {
    Deployment memory d = _deploy(config(chain));
    (WildcatMarket market, MockERC20 token) = _market(d, true);
    token.mint(LENDER, 1e18);
    vm.startPrank(LENDER);
    token.approve(address(market), 1e18);
    market.deposit(1e18);
    vm.stopPrank();
    assertEq(market.balanceOf(LENDER), 1e18);
  }

  function test_verificationRejectsDisabledEngineAndRetargetedSanctions() public {
    Config memory c = config(MAINNET);
    Deployment memory d = _deploy(c);
    vm.prank(LENDER);
    vm.expectRevert(bytes4(keccak256('Unauthorized()')));
    ChainalysisProxy(d.sanctionsAdapter).setSanctionsRegistry(address(0));
    vm.prank(LENDER);
    vm.expectRevert(bytes4(keccak256('Unauthorized()')));
    WildcatCopyOfChainalysisList(d.sanctionsList).addToSanctionsList(c.sanctions);
    vm.prank(DEPLOYER);
    SphereXEngine(d.sphereXEngine).deactivateAllRules();
    vm.expectRevert('Ink: SphereX rules disabled');
    this.verifyForTest(c, d);
    vm.prank(DEPLOYER);
    SphereXEngine(d.sphereXEngine).configureRules(0x0000000000000001);
    vm.prank(DEPLOYER);
    ChainalysisProxy(d.sanctionsAdapter).setSanctionsRegistry(address(0));
    vm.expectRevert('Ink: adapter backend');
    this.verifyForTest(c, d);
  }

  function test_safeHandoffRespectsDelayAndIndependentUpdater() public {
    Config memory c = config(MAINNET);
    Deployment memory d = _deploy(c);
    (WildcatMarket existingMarket, MockERC20 token) = _market(d, false);
    SafeHarness safe = new SafeHarness();
    // membership and updater ownership can change before the Safe handoff.
    address[] memory initialUpdate = new address[](1);
    initialUpdate[0] = address(0xDA7A);
    vm.prank(DEPLOYER);
    WildcatCopyOfChainalysisList(d.sanctionsList).addToSanctionsList(initialUpdate);
    vm.prank(DEPLOYER);
    WildcatCopyOfChainalysisList(d.sanctionsList).transferOwnership(address(0xDA7A));
    _nominate(c, d, address(safe));
    vm.expectRevert();
    safe.execute(d.sphereXEngine, abi.encodeWithSignature('acceptDefaultAdminTransfer()'));
    vm.expectRevert('Ink: Safe must accept/configure arch');
    this.finishForTest(c, d, address(safe), address(0xDA7A), address(safe));
    vm.warp(block.timestamp + 1 hours + 1);
    safe.execute(d.archController, abi.encodeWithSignature('acceptSphereXAdminRole()'));
    safe.execute(d.archController, abi.encodeWithSignature('changeSphereXOperator(address)', address(safe)));
    safe.execute(d.sphereXEngine, abi.encodeWithSignature('acceptDefaultAdminTransfer()'));
    _finish(c, d, address(safe), address(0xDA7A), address(safe));
    assertEq(WildcatArchController(d.archController).owner(), address(safe));
    assertEq(WildcatCopyOfChainalysisList(d.sanctionsList).owner(), address(0xDA7A));
    assertEq(WildcatFeeRecipient(d.feeRecipient).recipient(), address(safe));
    assertEq(existingMarket.feeRecipient(), d.feeRecipient);
    token.mint(d.feeRecipient, 1e18);
    vm.prank(address(safe));
    WildcatFeeRecipient(d.feeRecipient).releaseERC20Fees(address(token));
    assertEq(token.balanceOf(address(safe)), 1e18);
    vm.prank(DEPLOYER);
    vm.expectRevert();
    WildcatArchController(d.archController).registerBorrower(address(0xBAD));
    vm.prank(DEPLOYER);
    vm.expectRevert();
    SphereXEngine(d.sphereXEngine).deactivateAllRules();
    address[] memory more = new address[](1);
    more[0] = address(0xDAD);
    vm.prank(address(0xDA7A));
    WildcatCopyOfChainalysisList(d.sanctionsList).addToSanctionsList(more);
    assertTrue(ChainalysisProxy(d.sanctionsAdapter).isSanctioned(more[0]));
  }

  function test_handoffRejectsEOARecipientAndTestnet() public {
    Config memory c = config(MAINNET);
    Deployment memory d = _deploy(c);
    vm.expectRevert('Ink: deployed Safe required');
    this.nominateForTest(c, d, address(0xBAD));
    c.chainId = TESTNET;
    vm.expectRevert('Ink: mainnet handoff only');
    this.nominateForTest(c, d, address(0xBAD));
  }

  function test_safeHandoffWithDirectFeesRemovesDeployerPowers() public {
    Config memory c = config(MAINNET);
    c.deployFeeRecipient = false;
    SafeHarness safe = new SafeHarness();
    c.feeRecipient = address(safe);
    Deployment memory d = _deploy(c);
    _nominate(c, d, address(safe));
    vm.warp(block.timestamp + 1 hours + 1);
    safe.execute(d.archController, abi.encodeWithSignature('acceptSphereXAdminRole()'));
    safe.execute(d.archController, abi.encodeWithSignature('changeSphereXOperator(address)', address(safe)));
    safe.execute(d.sphereXEngine, abi.encodeWithSignature('acceptDefaultAdminTransfer()'));
    _finish(c, d, address(safe), address(safe), address(safe));

    WildcatArchController arch = WildcatArchController(d.archController);
    SphereXEngine engine = SphereXEngine(d.sphereXEngine);
    ChainalysisProxy adapter = ChainalysisProxy(d.sanctionsAdapter);
    WildcatCopyOfChainalysisList list = WildcatCopyOfChainalysisList(d.sanctionsList);
    assertEq(d.testnetOwner, address(0));
    assertEq(d.feeRecipient, address(safe));
    assertEq(arch.pendingSphereXAdmin(), address(0));
    (address pending,) = engine.pendingDefaultAdmin();
    assertEq(pending, address(0));
    assertFalse(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), DEPLOYER));
    assertFalse(engine.hasRole(engine.OPERATOR_ROLE(), DEPLOYER));
    assertFalse(engine.hasRole(engine.SENDER_ADDER_ROLE(), DEPLOYER));
    assertTrue(engine.hasRole(engine.SENDER_ADDER_ROLE(), d.archController));

    bytes memory fees = abi.encodeCall(
      HooksFactory.updateHooksTemplateFees, (d.openTermHooks, address(safe), address(0), 0, uint16(250))
    );
    address[] memory none = new address[](0);
    safe.execute(d.archController, abi.encodeCall(WildcatArchController.registerBorrower, (BORROWER)));
    safe.execute(d.hooksFactory, fees);
    safe.execute(d.archController, abi.encodeWithSignature('changeSphereXOperator(address)', address(safe)));
    safe.execute(d.sphereXEngine, abi.encodeCall(SphereXEngine.addAllowedSender, (none)));
    safe.execute(d.sanctionsAdapter, abi.encodeCall(ChainalysisProxy.setSanctionsRegistry, (d.sanctionsList)));
    safe.execute(d.sanctionsList, abi.encodeCall(WildcatCopyOfChainalysisList.updateSanctionsList, (none, none)));
    assertTrue(arch.isRegisteredBorrower(BORROWER));
    assertEq(HooksFactory(d.hooksFactory).getHooksTemplateDetails(d.openTermHooks).protocolFeeBips, 250);

    vm.startPrank(DEPLOYER);
    vm.expectRevert();
    arch.transferOwnership(DEPLOYER);
    vm.expectRevert();
    HooksFactory(d.hooksFactory).disableHooksTemplate(d.openTermHooks);
    vm.expectRevert();
    arch.changeSphereXOperator(DEPLOYER);
    vm.expectRevert();
    arch.changeSphereXEngine(address(0));
    vm.expectRevert();
    engine.beginDefaultAdminTransfer(DEPLOYER);
    vm.expectRevert();
    engine.deactivateAllRules();
    vm.expectRevert();
    adapter.setSanctionsRegistry(address(0));
    vm.expectRevert();
    list.updateSanctionsList(none, none);
    vm.stopPrank();
  }

  function test_rerunRefusesAlreadyConsumedDeployerNonce() public {
    Config memory c = config(MAINNET);
    _deploy(c);
    vm.expectRevert('Ink: nonce changed; do not rerun');
    this.deployForTest(c);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test } from 'forge-std/Test.sol';
import { ContinueInkTestnet } from '../../script/ink/ContinueInk.s.sol';
import {
  WildcatArchController,
  WildcatCopyOfChainalysisList,
  MockArchControllerOwner,
  ChainalysisProxy
} from '../../script/ink/InkDeployment.sol';

contract InkContinuationTest is Test, ContinueInkTestnet {
  address internal constant DEPLOYER = address(0xCA73);

  function _partial() internal returns (Config memory c, Deployment memory d, string memory parent) {
    vm.chainId(TESTNET);
    vm.setNonce(DEPLOYER, 1);
    vm.deal(DEPLOYER, 1 ether);
    c.chainId = TESTNET;
    c.deployer = DEPLOYER;
    c.expectedNonce = 1;
    c.feeRecipient = address(0xFEE);
    c.protocolFeeBips = 500;
    c.snapshotHash = keccak256('deferred snapshot');
    c.sanctions = new address[](137);
    for (uint256 i; i < c.sanctions.length; ++i) {
      c.sanctions[i] = address(uint160(i + 1));
    }
    vm.startBroadcast(DEPLOYER);
    d.archController = _create('WildcatArchController', 'WildcatArchController.sol:WildcatArchController', '');
    d.sphereXEngine = _create('SphereXEngine', 'spherex-engine/SphereXEngine.sol:SphereXEngine', '');
    d.sanctionsList = _create('SanctionsList', 'WildcatCopyOfChainalysisList.sol:WildcatCopyOfChainalysisList', '');
    vm.stopBroadcast();
    // Forge runs tests concurrently; filesystem writes aren't isolated like EVM state.
    string memory path = string.concat('deployments/ink/runs/test-continuation-parent-', vm.toString(msg.sig), '.json');
    vm.createDir('deployments/ink/runs', true);
    _writeCandidate(c, d, path);
    parent = vm.readFile(path);
    vm.removeFile(path);
    delete records;
    c.expectedNonce = 4;
  }

  function continueForTest(Config memory c, string memory parent) external returns (Deployment memory) {
    return _continue(c, parent);
  }

  function verifySeededForTest(Config memory c, Deployment memory d) external view {
    _verify(c, d);
  }

  function test_continuationReusesThreeSkipsOnlySeedingAndKeepsPublicRegistration() public {
    (Config memory c, Deployment memory old, string memory parent) = _partial();
    Deployment memory d = _continue(c, parent);
    assertEq(d.archController, old.archController);
    assertEq(d.sphereXEngine, old.sphereXEngine);
    assertEq(d.sanctionsList, old.sanctionsList);
    assertEq(d.sanctionsAdapter, vm.computeCreateAddress(DEPLOYER, 4));
    assertEq(d.testnetOwner, vm.computeCreateAddress(DEPLOYER, 23));
    assertEq(vm.getNonce(DEPLOYER), 25);
    assertEq(records.length, 13);
    assertEq(WildcatCopyOfChainalysisList(d.sanctionsList).getSanctionedAddressesCount(), 0);
    assertEq(ChainalysisProxy(d.sanctionsAdapter).sanctionsRegistry(), d.sanctionsList);
    WildcatArchController arch = WildcatArchController(d.archController);
    assertEq(arch.owner(), d.testnetOwner);
    address publicCaller = address(0xB0B);
    MockArchControllerOwner helper = MockArchControllerOwner(d.testnetOwner);
    assertFalse(helper.authorizedAccounts(publicCaller));
    vm.prank(publicCaller);
    helper.registerBorrower(publicCaller);
    assertTrue(arch.isRegisteredBorrower(publicCaller));
    _verify(c, d, false);
    vm.expectRevert('Ink: snapshot count');
    this.verifySeededForTest(c, d);

    string memory path = 'deployments/ink/runs/test-continuation-candidate.json';
    _writeCandidate(c, d, path, false);
    string memory candidate = vm.readFile(path);
    assertFalse(vm.parseJsonBool(candidate, '.sanctionsSeeded'));
    assertEq(vm.parseJsonBytes32(candidate, '.snapshotHash'), c.snapshotHash);
    assertEq(vm.parseJsonUint(candidate, '.startNonce'), 4);
    assertEq(vm.parseJsonUint(candidate, '.endNonce'), 25);
    vm.removeFile(path);
  }

  function test_rejectsWrongRuntime() public {
    (Config memory c, Deployment memory d, string memory parent) = _partial();
    vm.etch(d.archController, hex'6000');
    vm.expectRevert('Ink: reused runtime code');
    this.continueForTest(c, parent);
  }

  function test_rejectsChangedListOwner() public {
    (Config memory c, Deployment memory d, string memory parent) = _partial();
    vm.prank(DEPLOYER);
    WildcatCopyOfChainalysisList(d.sanctionsList).transferOwnership(address(0xBAD));
    vm.expectRevert('Ink: reused list owner');
    this.continueForTest(c, parent);
  }

  function test_rejectsAlreadySeededList() public {
    (Config memory c, Deployment memory d, string memory parent) = _partial();
    vm.prank(DEPLOYER);
    WildcatCopyOfChainalysisList(d.sanctionsList).addToSanctionsList(c.sanctions);
    vm.expectRevert('Ink: reused list is not empty');
    this.continueForTest(c, parent);
  }

  function test_rejectsNonceDrift() public {
    (Config memory c,, string memory parent) = _partial();
    vm.setNonce(DEPLOYER, 5);
    vm.expectRevert('Ink: nonce changed; do not rerun');
    this.continueForTest(c, parent);
  }

  function test_rejectsSnapshotChange() public {
    (Config memory c,, string memory parent) = _partial();
    c.snapshotHash = keccak256('different list');
    vm.expectRevert('Ink: parent snapshot');
    this.continueForTest(c, parent);
  }

  function test_rejectsMainnetContinuation() public {
    (Config memory c,, string memory parent) = _partial();
    c.chainId = MAINNET;
    vm.chainId(MAINNET);
    vm.expectRevert('Ink: continuation is testnet-only');
    this.continueForTest(c, parent);
  }
}

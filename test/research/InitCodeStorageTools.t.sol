// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'script/common/DeployScriptBase.sol';
import '../libraries/CompressedInitCode.t.sol';
import '../libraries/SplitInitCode.t.sol';

contract InitCodeStorageToolHarness is DeployScriptBase {
  function read(address store) external view returns (bytes memory) {
    return LibStoredInitCode.getInitCode(store);
  }

  function verify(address store, bytes memory original) external view {
    _verifyStoredInitCode(store, 'test artifact', original);
  }

  function fits(bytes memory original) external pure {
    _requireInitCodeStoragePayloadFits(original, 'test artifact');
  }

  function predicate(bytes memory original) external pure returns (string memory) {
    return _planInitCodeStoragePredicate('store', original);
  }

  function planDeployment(
    bytes memory original,
    address secondary
  ) external pure returns (string memory artifact, bytes memory args) {
    artifact = _initCodeStorageArtifact(original);
    bytes memory input = _initCodeStorageConstructorInput(original);
    args = original.length <= 24_575 ? abi.encode(input) : abi.encode(input, secondary);
  }

  function reuse(
    address store,
    address secondary,
    bytes memory original
  )
    external
    returns (address primary, address recordedSecondary, uint256 artifacts, bool didDeploy)
  {
    Deployments memory deployments;
    // serialized cheatcode objects survive reverted calls. start each simulated run empty.
    deployments.deployments = JsonUtil.create('{}');
    deployments.privateKeyVarName = 'E24_TEST_DEPLOYER';
    if (store != address(0)) deployments.set('Test_initCodeStorage', store);
    if (secondary != address(0)) deployments.set('Test_initCodeStorage_secondary', secondary);
    (primary, didDeploy) = LibDeployment.getOrDeployInitcodeStorage(
      deployments,
      'Test',
      original,
      false
    );
    if (deployments.has('Test_initCodeStorage_secondary'))
      recordedSecondary = deployments.get('Test_initCodeStorage_secondary');
    artifacts = deployments.artifacts.length;
  }

  function exportPlan(bytes memory original) external {
    Deployments memory deployments;
    deployments.dir = 'deploy-out/split-storage-plan-test';
    DeployPlanEntry memory entry;
    entry.sequence = 1;
    entry.id = 'deploy-store';
    entry.output = 'store';
    entry.description = 'Deploy the selected initcode storage format.';
    _planInitCodeStorageEntry(deployments, entry, original);
    _writePlanInitCodeStorageInventory(
      deployments,
      1,
      'anvil',
      'Test_initCodeStorage',
      'store',
      original
    );
  }
}

contract ContextDependentCodeReader {
  address internal immutable acceptedCaller;
  bytes internal original;

  constructor(address caller_, bytes memory original_) {
    acceptedCaller = caller_;
    original = original_;
  }

  fallback() external {
    bytes memory result = original;
    if (msg.sender != acceptedCaller) result = hex'fe';
    assembly ('memory-safe') {
      return(add(result, 32), mload(result))
    }
  }
}

contract InitCodeStorageToolsTest is TestKernel {
  SplitCodeHarness internal storageHarness;
  InitCodeStorageToolHarness internal toolsHarness;

  function setUp() external {
    storageHarness = SplitCodeHarness(
      _deployCode('test/libraries/SplitInitCode.t.sol:SplitCodeHarness')
    );
    toolsHarness = InitCodeStorageToolHarness(
      _deployCode('test/research/InitCodeStorageTools.t.sol:InitCodeStorageToolHarness')
    );
  }

  function _expectMismatch(address store, bytes memory original) internal {
    vm.expectRevert(bytes('Verification failed for test artifact: stored init code mismatch'));
    toolsHarness.verify(store, original);
  }

  function testFuzz_verifiesRawSplitAndReusedStores(bytes memory original) external {
    address raw = storageHarness.deployInitCode(original);
    (address primary, address secondary) = storageHarness.split(original);
    toolsHarness.verify(raw, original);
    toolsHarness.verify(primary, original);
    (address reused, , , bool deployed) = toolsHarness.reuse(raw, address(0), original);
    assertEq(reused, raw);
    assertFalse(deployed);
    (reused, , , deployed) = toolsHarness.reuse(primary, secondary, original);
    assertEq(reused, primary);
    assertFalse(deployed);
  }

  function testFuzz_rejectsEveryMutatedPrimaryRegion(
    bytes memory original,
    uint256 indexSeed,
    uint8 difference
  ) external {
    (address primary, ) = storageHarness.split(original);
    bytes memory runtime = primary.code;
    uint256 readerLength = type(SplitInitCodeReader).runtimeCode.length;
    uint256[4] memory offsets = [
      bound(indexSeed, 0, readerLength - 1),
      readerLength + (original.length > 0 ? indexSeed % original.length : 0),
      runtime.length - 24 + (indexSeed % 20),
      runtime.length - 1 - (indexSeed % 4)
    ];
    bytes1 mask = bytes1(difference == 0 ? uint8(1) : difference);
    for (uint256 i; i < offsets.length; ++i) {
      runtime[offsets[i]] ^= mask;
      vm.etch(primary, runtime);
      _expectMismatch(primary, original);
      runtime[offsets[i]] ^= mask;
    }
    vm.etch(primary, runtime);
    toolsHarness.verify(primary, original);
  }

  function test_rejectsSecondaryMutationTruncationAndTrailingBytes() external {
    bytes memory original = new bytes(25_000);
    (address primary, address secondary) = storageHarness.split(original);
    bytes memory saved = secondary.code;
    bytes memory changed = bytes.concat(saved);
    changed[1] ^= 0x01;
    vm.etch(secondary, changed);
    _expectMismatch(primary, original);
    vm.etch(secondary, bytes.concat(saved, hex'00'));
    _expectMismatch(primary, original);
    vm.etch(secondary, hex'00');
    _expectMismatch(primary, original);
    vm.etch(secondary, '');
    _expectMismatch(primary, original);
    vm.etch(secondary, saved);
    toolsHarness.verify(primary, original);
    _expectMismatch(primary, bytes.concat(original, hex'01'));
  }

  function test_rejectsContextDependentReaderEvenWhenReadbackMatches() external {
    bytes memory original = hex'600160005260206000f3';
    address store = _deployCode(
      'test/research/InitCodeStorageTools.t.sol:ContextDependentCodeReader',
      abi.encode(address(toolsHarness), original)
    );
    assertEq(toolsHarness.read(store), original, 'one read does not authenticate a reader');
    assertEq(storageHarness.read(store), hex'fe', 'different program for the factory');
    _expectMismatch(store, original);
  }

  function test_rejectsCompressedStoresEvenWhenReadbackMatches() external {
    bytes memory original = hex'600160005260206000f3';
    address store = LibCompressedInitCode.deployInitCode(original);
    assertEq(toolsHarness.read(store), original);
    _expectMismatch(store, original);
  }

  function test_partialReuseAuthenticatesSecondaryAndRecoversInventoryLink() external {
    bytes memory original = new bytes(25_000);
    (address primary, address secondary) = storageHarness.split(original);
    (address reused, address linked, uint256 artifacts, bool deployed) = toolsHarness.reuse(
      primary,
      address(0),
      original
    );
    assertEq(reused, primary);
    assertEq(linked, secondary);
    assertEq(artifacts, 1, 'only the missing secondary inventory record');
    assertFalse(deployed);
    vm.expectRevert(bytes('Stored secondary address mismatch'));
    toolsHarness.reuse(primary, address(0xBAD), original);
    vm.expectRevert(bytes('Stored secondary code mismatch'));
    toolsHarness.reuse(address(0), address(0xBAD), original);
    (reused, linked, artifacts, deployed) = toolsHarness.reuse(address(0), secondary, original);
    assertTrue(deployed);
    assertEq(linked, secondary);
    assertEq(artifacts, 1, 'only the primary needs deployment');
    toolsHarness.verify(reused, original);
  }

  function test_directDeploymentTracksBothPreparedArtifacts() external {
    bytes memory original = new bytes(25_000);
    (address primary, address secondary, uint256 artifacts, bool deployed) = toolsHarness.reuse(
      address(0),
      address(0),
      original
    );
    assertTrue(deployed);
    assertEq(artifacts, 2);
    assertEq(LibSplitInitCode.getSecondaryAddress(primary), secondary);
    toolsHarness.verify(primary, original);
  }

  function test_planAndDirectFormatsMatchAtStorageThreshold() external {
    for (uint256 length = 24_574; length <= 24_576; ++length) {
      bytes memory original = new bytes(length);
      original[length - 1] = 0xab;
      toolsHarness.fits(original);
      address secondary;
      if (length > 24_575)
        secondary = _deployCode(
          LibDeployment.PreparedStorageArtifact,
          abi.encode(LibSplitInitCode.getSecondaryRuntime(original))
        );
      (string memory artifact, bytes memory args) = toolsHarness.planDeployment(
        original,
        secondary
      );
      address planned = _deployCode(artifact, args);
      bytes memory expected = length <= 24_575
        ? bytes.concat(hex'00', original)
        : LibSplitInitCode.getPrimaryRuntime(original, secondary);
      assertEq(planned.code, expected, 'prepared installation preserves every byte');
      toolsHarness.verify(planned, original);
      assertEq(storageHarness.read(planned), original);
      string memory predicate = toolsHarness.predicate(original);
      assertEq(
        vm.parseJsonString(predicate, '.type'),
        length <= 24_575 ? 'codeHash' : 'splitCodeHash'
      );
      assertEq(
        vm.parseJsonBytes32(predicate, '.expect'),
        keccak256(LibDeployment.initCodeStorageRuntime(original))
      );
      assertEq(vm.parseJsonBytes32(predicate, '.initCodeHash'), keccak256(original));
      assertTrue(planned.code.length <= 24_576);
    }
    vm.expectRevert(LibSplitInitCode.InitCodeDeploymentFailed.selector);
    toolsHarness.fits(new bytes(LibSplitInitCode.maximumInitCodeSize() + 1));
  }

  function test_linkedInstallerRejectsMissingOrAlreadyBoundAddress() external {
    bytes memory original = new bytes(25_000);
    (string memory artifact, bytes memory args) = toolsHarness.planDeployment(original, address(0));
    vm.expectRevert(bytes('Invalid split storage link'));
    _deployCode(artifact, args);
    bytes memory boundRuntime = LibSplitInitCode.getPrimaryRuntime(original, address(1));
    vm.expectRevert();
    _deployCode(artifact, abi.encode(boundRuntime, address(2)));
  }

  function test_generatedPlanTracksAndBindsSecondary() external {
    vm.setEnv('EXPECTED_EXECUTOR', vm.toString(address(0x1234)));
    bytes memory original = vm.getCode('src/market/WildcatMarket.sol:WildcatMarket');
    toolsHarness.exportPlan(original);
    string memory primary = vm.readFile(
      'deploy-out/split-storage-plan-test/plan-entries/01-deploy-store.json'
    );
    string memory secondary = vm.readFile(
      'deploy-out/split-storage-plan-test/plan-entries/01-deploy-store-secondary.json'
    );
    assertEq(vm.parseJsonString(primary, '.after[0]'), 'deploy-store-secondary');
    assertEq(vm.parseJsonString(primary, '.constructorArgs.decoded[1].$ref'), 'store-secondary');
    assertEq(vm.parseJsonString(primary, '.predicate.secondary.$ref'), 'store-secondary');
    assertEq(
      vm.parseJsonBytes32(primary, '.predicate.secondaryCodeHash'),
      vm.parseJsonBytes32(secondary, '.predicate.expect')
    );
    assertEq(vm.parseJsonBytes32(primary, '.predicate.initCodeHash'), keccak256(original));
    string memory record = vm.readFile(
      'deploy-out/split-storage-plan-test/inventory-pending/01-Test_initCodeStorage.json'
    );
    assertEq(vm.parseJsonString(record, '.secondary.$ref'), 'store-secondary');
    assertTrue(
      vm.exists(
        'deploy-out/split-storage-plan-test/inventory-pending/01-Test_initCodeStorage_secondary.json'
      )
    );
  }

  function test_exportHistoricalCompressionControl() external {
    string[2] memory paths = [
      'src/market/WildcatMarket.sol:WildcatMarket',
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
    ];
    string memory output;
    for (uint256 i; i < paths.length; ++i) {
      bytes memory original = vm.getCode(paths[i]);
      string memory name = i == 0 ? 'WildcatMarket' : 'WildcatMarketRevolving';
      vm.serializeBytes('compression-rpc', string.concat(name, '_creation'), original);
      output = vm.serializeBytes(
        'compression-rpc',
        string.concat(name, '_runtime'),
        LibCompressedInitCode.getStorageRuntime(original)
      );
    }
    vm.writeJson(output, 'deploy-out/compression-rpc.json');
  }
}

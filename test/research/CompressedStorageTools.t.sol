// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import 'script/common/DeployScriptBase.sol';
import '../libraries/CompressedInitCode.t.sol';

contract CompressedStorageToolHarness is DeployScriptBase {
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
    bytes memory original
  ) external pure returns (string memory artifact, bytes memory args) {
    return (
      _initCodeStorageArtifact(original),
      abi.encode(_initCodeStorageConstructorInput(original))
    );
  }

  function reuse(address store, bytes memory original) external returns (address) {
    Deployments memory deployments;
    deployments.deployments = JsonUtil.create();
    deployments.set('Test_initCodeStorage', store);
    (address result, bool didDeploy) = LibDeployment.getOrDeployInitcodeStorage(
      deployments,
      'Test',
      original,
      false
    );
    require(!didDeploy, 'unexpected deployment');
    return result;
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

contract CompressedStorageToolsTest is TestKernel {
  CompressedCodeHarness internal storageHarness;
  CompressedStorageToolHarness internal toolsHarness;

  function setUp() external {
    storageHarness = CompressedCodeHarness(
      _deployCode('test/libraries/CompressedInitCode.t.sol:CompressedCodeHarness')
    );
    toolsHarness = CompressedStorageToolHarness(
      _deployCode('test/research/CompressedStorageTools.t.sol:CompressedStorageToolHarness')
    );
  }

  function _expectMismatch(address store, bytes memory original) internal {
    vm.expectRevert(bytes('Verification failed for test artifact: stored init code mismatch'));
    toolsHarness.verify(store, original);
  }

  function testFuzz_verifiesRawCompressedAndReusedStores(bytes memory original) external {
    address raw = storageHarness.deployInitCode(original);
    address compressed = storageHarness.compress(original);
    toolsHarness.verify(raw, original);
    toolsHarness.verify(compressed, original);
    assertEq(toolsHarness.reuse(raw, original), raw);
    assertEq(toolsHarness.reuse(compressed, original), compressed);
  }

  function testFuzz_rejectsEveryMutatedRegion(
    bytes memory original,
    uint256 indexSeed,
    uint8 difference
  ) external {
    address store = storageHarness.compress(original);
    bytes memory runtime = store.code;
    uint256 readerLength = type(CompressedInitCodeReader).runtimeCode.length;
    uint256[3] memory offsets = [
      bound(indexSeed, 0, readerLength - 1),
      readerLength +
        (runtime.length > readerLength + 2 ? indexSeed % (runtime.length - readerLength - 2) : 0),
      runtime.length - 1 - (indexSeed % 2)
    ];
    bytes1 mask = bytes1(difference == 0 ? uint8(1) : difference);
    for (uint256 i; i < offsets.length; ++i) {
      runtime[offsets[i]] ^= mask;
      vm.etch(store, runtime);
      _expectMismatch(store, original);
      runtime[offsets[i]] ^= mask;
    }
    vm.etch(store, runtime);
    toolsHarness.verify(store, original);
  }

  function test_rejectsTruncationTrailingBytesAndWrongArtifact() external {
    bytes memory original = hex'600160005260206000f3';
    address store = storageHarness.compress(original);
    bytes memory runtime = store.code;
    vm.etch(store, bytes.concat(runtime, hex'00'));
    _expectMismatch(store, original);
    assembly ('memory-safe') {
      mstore(runtime, sub(mload(runtime), 1))
    }
    vm.etch(store, runtime);
    _expectMismatch(store, original);
    store = storageHarness.compress(original);
    _expectMismatch(store, bytes.concat(original, hex'00'));
    vm.expectRevert(bytes('Stored init code mismatch'));
    toolsHarness.reuse(store, hex'fe');
  }

  function test_rejectsContextDependentReaderEvenWhenReadbackMatches() external {
    bytes memory original = hex'600160005260206000f3';
    address store = _deployCode(
      'test/research/CompressedStorageTools.t.sol:ContextDependentCodeReader',
      abi.encode(address(toolsHarness), original)
    );
    assertEq(
      toolsHarness.read(store),
      original,
      'one successful read does not authenticate a reader'
    );
    assertEq(storageHarness.read(store), hex'fe', 'the factory could receive a different program');
    _expectMismatch(store, original);
    vm.expectRevert(bytes('Stored init code mismatch'));
    toolsHarness.reuse(store, original);
  }

  function test_rejectsMalformedLiteralThatTheDecoderAccepts() external {
    address store = address(0xBAD5704E);
    vm.etch(store, bytes.concat(type(CompressedInitCodeReader).runtimeCode, hex'02ab0002'));
    assertEq(storageHarness.read(store), hex'ab0000');
    _expectMismatch(store, hex'ab0000');
  }

  function test_rejectsDifferentValidEncodingOfTheSameBytes() external {
    address store = address(0xBAD5704E);
    vm.etch(store, bytes.concat(type(CompressedInitCodeReader).runtimeCode, hex'004120000004'));
    assertEq(storageHarness.read(store), bytes('AAAA'));
    // the pinned encoder emits a literal run for this short input. approving a different
    // stream requires a different reviewed runtime hash, even if both streams decode correctly.
    _expectMismatch(store, bytes('AAAA'));
  }

  function test_planAndDirectFormatsMatchAtStorageThreshold() external {
    for (uint256 length = 24_574; length <= 24_576; ++length) {
      bytes memory original = new bytes(length);
      toolsHarness.fits(original);
      (string memory artifact, bytes memory args) = toolsHarness.planDeployment(original);
      address planned = _deployCode(artifact, args);
      address direct = length <= 24_575
        ? storageHarness.deployInitCode(original)
        : storageHarness.compress(original);
      assertEq(planned.code, direct.code, 'plan and direct storage formats');
      string memory predicate = toolsHarness.predicate(original);
      assertEq(vm.parseJsonString(predicate, '.type'), 'codeHash');
      assertEq(vm.parseJsonBytes32(predicate, '.expect'), planned.codehash);
      assertEq(vm.parseJsonBytes32(predicate, '.initCodeHash'), keccak256(original));
      toolsHarness.verify(planned, original);
      assertEq(storageHarness.read(planned), original);
      assertTrue(planned.code.length <= 24_576);
    }
  }

  function test_planArtifactAndDirectStoresForBothMarkets() external {
    string[2] memory artifacts = [
      'src/market/WildcatMarket.sol:WildcatMarket',
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving'
    ];
    string memory fixtures;
    for (uint256 i; i < artifacts.length; ++i) {
      bytes memory original = vm.getCode(artifacts[i]);
      toolsHarness.fits(original);
      (string memory artifact, bytes memory args) = toolsHarness.planDeployment(original);
      address planned = _deployCode(artifact, args);
      address direct = storageHarness.compress(original);
      assertEq(planned.code, direct.code);
      toolsHarness.verify(planned, original);
      assertEq(storageHarness.read(planned), original);
      string memory name = i == 0 ? 'WildcatMarket' : 'WildcatMarketRevolving';
      vm.serializeBytes('compression-rpc', string.concat(name, '_creation'), original);
      fixtures = vm.serializeBytes(
        'compression-rpc',
        string.concat(name, '_runtime'),
        planned.code
      );
    }
    // the RPC suite uses the pinned Solidity encoder's bytes, then checks them on a fresh node.
    vm.writeJson(fixtures, 'deploy-out/compression-rpc.json');
  }
}

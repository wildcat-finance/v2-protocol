// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import './CompressedInitCode.t.sol';

contract CompressionIntegrityHarness is CompressedCodeHarness {
  function guardedRead(
    address store,
    bytes memory guard,
    uint8 misalignment
  )
    external
    view
    returns (bytes memory first, bytes memory second)
  {
    bytes32 beforeHash = keccak256(guard);
    assembly ('memory-safe') {
      mstore(0x40, add(mload(0x40), and(misalignment, 31)))
    }
    first = LibStoredInitCode.getInitCode(store);
    bytes32 firstHash = keccak256(first);
    second = LibStoredInitCode.getInitCode(store);
    require(keccak256(first) == firstHash && keccak256(guard) == beforeHash, 'memory clobber');
    uint256 zeroSlot;
    assembly ('memory-safe') {
      zeroSlot := mload(0x60)
    }
    require(zeroSlot == 0, 'dirty zero slot');
  }

  function guardedCreate2(
    address store,
    bytes32 salt,
    bytes memory args,
    bytes memory guard
  )
    external
    returns (address deployment)
  {
    bytes32 argsHash = keccak256(args);
    bytes32 guardHash = keccak256(guard);
    deployment = LibStoredInitCode.create2WithStoredInitCode(store, salt, args);
    require(keccak256(args) == argsHash && keccak256(guard) == guardHash, 'memory clobber');
  }
}

contract CompressionIntegrityTest is TestKernel {
  CompressionIntegrityHarness internal harness;

  function setUp() external {
    harness = CompressionIntegrityHarness(
      _deployCode('test/libraries/CompressionIntegrity.t.sol:CompressionIntegrityHarness')
    );
  }

  function _pattern(uint256 length, bytes32 seed, uint8 mode) internal pure returns (bytes memory data) {
    data = new bytes(length);
    for (uint256 i; i < length; i += 32) {
      bytes32 word = mode % 4 == 0
        ? bytes32(0)
        : mode % 4 == 1
          ? seed
          : mode % 4 == 2 ? bytes32(i % 257 == 0 ? uint256(seed) : 0) : keccak256(abi.encode(seed, i));
      assembly ('memory-safe') {
        mstore(add(add(data, 0x20), i), word)
      }
    }
  }

  function _reference(bytes memory original, bytes memory compressed) internal returns (bytes memory) {
    string[] memory command = new string[](4);
    command[0] = 'python3';
    command[1] = 'scripts/research/fastlz-reference.py';
    command[2] = vm.toString(original);
    command[3] = vm.toString(compressed);
    (bytes memory referenceCompressed, bytes memory referenceDecoded) = abi.decode(vm.ffi(command), (bytes, bytes));
    assertEq(referenceDecoded, original, 'upstream decodes Solady stream');
    return referenceCompressed;
  }

  function _readStream(bytes memory compressed) internal returns (bytes memory result) {
    // malformed streams use this too. etching creates a test input, not deployment-size evidence.
    address store = address(0xC0DEC);
    vm.etch(
      store, bytes.concat(type(CompressedInitCodeReader).runtimeCode, compressed, bytes2(uint16(compressed.length)))
    );
    return harness.read(store);
  }

  function testFuzz_referenceCodec(bytes32 seed, uint16 lengthSeed, uint8 mode) external {
    bytes memory original = _pattern(bound(lengthSeed, 0, 8192), seed, mode);
    bytes memory compressed = LibZip.flzCompress(original);
    bytes memory referenceCompressed = _reference(original, compressed);
    assertEq(_readStream(referenceCompressed), original, 'reader decodes upstream stream');
  }

  function test_referenceArtifactCorpus() external {
    string[10] memory artifacts = [
      'src/market/WildcatMarket.sol:WildcatMarket',
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving',
      'src/HooksFactory.sol:HooksFactory',
      'src/HooksFactoryRevolving.sol:HooksFactoryRevolving',
      'src/access/OpenTermHooks.sol:OpenTermHooks',
      'src/access/FixedTermHooks.sol:FixedTermHooks',
      'src/access/PeriodicTermHooks.sol:PeriodicTermHooks',
      'test/mocks/TransferFeatureHooks.sol:PeriodicTransferHooks',
      'test/mocks/BorrowFeatureHooks.sol:PeriodicBorrowHooks',
      'test/mocks/AprReplacementHooks.sol:PeriodicAprReplacementHooks'
    ];
    for (uint256 i; i < artifacts.length; ++i) {
      bytes memory original = vm.getCode(artifacts[i]);
      bytes memory referenceCompressed = _reference(original, LibZip.flzCompress(original));
      assertEq(_readStream(referenceCompressed), original, artifacts[i]);
    }
  }

  function test_referenceBoundaryCorpus() external {
    uint256[17] memory lengths =
      [uint256(0), 1, 2, 15, 16, 31, 32, 33, 255, 256, 257, 263, 264, 8191, 8192, 8193, 49_152];
    for (uint256 i; i < lengths.length; ++i) {
      for (uint8 mode; mode < 4; ++mode) {
        bytes memory original = _pattern(lengths[i], keccak256(abi.encode(i)), mode);
        bytes memory stream = _reference(original, LibZip.flzCompress(original));
        // incompressible maximum-sized data isn't a deployable store, but still has to decode.
        assertEq(_readStream(stream), original);
      }
    }
  }

  function testFuzz_largePayloadAndMemory(bytes32 seed, uint16 lengthSeed, uint8 mode, uint8 alignment) external {
    bytes memory original = _pattern(bound(lengthSeed, 0, 49_152), seed, mode);
    bytes32 originalHash = keccak256(original);
    uint256 runtimeLength = type(CompressedInitCodeReader).runtimeCode.length + LibZip.flzCompress(original).length + 2;
    if (runtimeLength > 24_576) {
      uint64 nonce = vm.getNonce(address(harness));
      vm.expectRevert(LibCompressedInitCode.InitCodeDeploymentFailed.selector);
      harness.compress(original);
      assertEq(vm.getNonce(address(harness)), nonce, 'failed storage creation rolls back nonce');
      return;
    }
    address store = harness.compress(original);
    (bytes memory first, bytes memory second) = harness.guardedRead(store, abi.encode(seed, originalHash), alignment);
    assertEq(first, original);
    assertEq(second, original);
    assertEq(keccak256(original), originalHash);
  }

  function test_readerLiteralAndOverlappingMatchBoundaries() external {
    assertEq(_readStream(hex'00412000'), bytes('AAAA'));
    assertEq(_readStream(hex'014142e00001'), bytes('ABABABABABA'));
    bytes memory maxMatch = new bytes(265);
    for (uint256 i; i < maxMatch.length; ++i) {
      maxMatch[i] = 0x41;
    }
    assertEq(_readStream(hex'0041e0ff00'), maxMatch);
  }

  function test_decoderDoesNotValidateUntrustedStreams() external {
    // LibZip pads a truncated literal with memory bytes. artifact verification must reject
    // this store; a successful STATICCALL alone is not an integrity check.
    assertEq(_readStream(hex'02ab'), hex'ab0000');
  }

  function testFuzz_create2MemoryGuards(bytes memory data, bytes32 salt) external {
    bytes memory code = vm.getCode('test/libraries/CompressedInitCode.t.sol:CompressedConstructorProbe');
    address store = harness.compress(code);
    address deployed = harness.guardedCreate2(store, salt, abi.encode(data), data);
    assertEq(CompressedConstructorProbe(deployed).dataHash(), keccak256(data));
    assertEq(CompressedConstructorProbe(deployed).deployer(), address(harness));
  }

  function testFuzz_readerIgnoresCallerAndCalldata(bytes memory data, bytes memory callData, address caller) external {
    address store = harness.compress(data);
    vm.prank(caller);
    (bool success, bytes memory decoded) = store.staticcall(callData);
    assertTrue(success);
    assertEq(decoded, data);
  }

  function test_creationFailureRollsBackNonceAndValue() external {
    address store = harness.compress(hex'5f5ffd');
    vm.deal(address(harness), 1 ether);
    uint64 nonce = vm.getNonce(address(harness));
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.createWithStoredInitCode(store, 1 ether);
    assertEq(vm.getNonce(address(harness)), nonce);
    assertEq(address(harness).balance, 1 ether);
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.create2WithStoredInitCode(store, bytes32(0), 1 ether);
    assertEq(vm.getNonce(address(harness)), nonce);
    assertEq(address(harness).balance, 1 ether);
  }

  function test_create2TotalInitCodeLimitIncludesArguments() external {
    bytes memory code = new bytes(49_120);
    // return one STOP byte. the rest is unreachable creation-code padding.
    code[0] = 0x60;
    code[1] = 0x01;
    code[2] = 0x5f;
    code[3] = 0xf3;
    address store = harness.compress(code);
    address deployed = harness.create2Memory(store, bytes32(uint256(1)), 0, new bytes(32));
    assertEq(deployed.code, hex'00');
    uint64 nonce = vm.getNonce(address(harness));
    (bool success,) = address(harness).call{ gas: 2_000_000 }(
      abi.encodeCall(harness.create2Memory, (store, bytes32(uint256(2)), 0, new bytes(33)))
    );
    assertFalse(success, 'EIP-3860 applies after arguments are appended');
    assertEq(vm.getNonce(address(harness)), nonce);
    deployed = harness.create2Calldata(store, bytes32(uint256(3)), 0, new bytes(32));
    assertEq(deployed.code, hex'00');
    nonce = vm.getNonce(address(harness));
    (success,) = address(harness).call{ gas: 2_000_000 }(
      abi.encodeCall(harness.create2Calldata, (store, bytes32(uint256(4)), 0, new bytes(33)))
    );
    assertFalse(success, 'calldata arguments count toward EIP-3860 too');
    assertEq(vm.getNonce(address(harness)), nonce);
  }
}

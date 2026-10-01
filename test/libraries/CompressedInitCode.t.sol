// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // CompressedInitCode.t
// ║  ██▀▀     ▀▀██   Compressed storage round trips, limits, and deployment context.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  COMPRESSION AND READING
// ║  compress(...)
// ║  read(...)
// ║
// ║  CREATE2 ADAPTERS
// ║  create2Memory(...)
// ║  create2Calldata(...)
// ║
// ║  CONSTRUCTOR PROBE
// ║  constructor(...)
// ║
// ║  MUTATING READER
// ║  fallback()
// ║
// ║  OVERSIZED READER
// ║  fallback()
// ║
// ║  FIXTURE
// ║  setUp()
// ║
// ║  STORAGE ROUND TRIPS
// ║  testFuzz_roundTripAndExactlyOneStorageContract(...)
// ║  test_roundTripLengthBoundaries()
// ║  test_rawStorageRemainsByteExact()
// ║
// ║  STORAGE AND READER LIMITS
// ║  test_compressionRejectsUndeployableInputLength()
// ║  test_incompressiblePayloadStillEnforcesStorageLimit()
// ║  test_readerIsStaticAndCapsOutput()
// ║
// ║  DEPLOYMENT CONTEXT
// ║  test_createPreservesFactoryContextAndValue()
// ║  test_create2HashesOriginalBytesAndRejectsDuplicateSalt()
// ║  testFuzz_constructorArgsMemoryAndCalldata(...)
// ╚═════

import 'src/libraries/LibCompressedInitCode.sol';
import './wrappers/LibStoredInitCodeExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ CompressedCodeHarness ────────────────────────────────────────────────────
contract CompressedCodeHarness is LibStoredInitCodeExternal {
  // ░░▒▒▓▓██ [ COMPRESSION AND READING ] ──────────────────────────────────────

  // ┌─ compress ─────
  function compress(bytes memory code) external returns (address) {
    return LibCompressedInitCode.deployInitCode(code);
  }

  // ┌─ read ─────
  function read(address store) external view returns (bytes memory) {
    return LibStoredInitCode.getInitCode(store);
  }

  // ░░▒▒▓▓██ [ CREATE2 ADAPTERS ] ─────────────────────────────────────────────

  // ┌─ create2Memory ─────
  function create2Memory(address store, bytes32 salt, uint256 value, bytes memory args) external returns (address) {
    return LibStoredInitCode.create2WithStoredInitCode(store, salt, value, args);
  }

  // ┌─ create2Calldata ─────
  function create2Calldata(address store, bytes32 salt, uint256 value, bytes calldata args) external returns (address) {
    return LibStoredInitCode.create2WithStoredInitCodeCD(store, salt, value, args);
  }
}

// ┌─ CompressedConstructorProbe ───────────────────────────────────────────────
contract CompressedConstructorProbe {
  address public immutable deployer;
  uint256 public immutable value;
  bytes32 public immutable dataHash;

  // ░░▒▒▓▓██ [ CONSTRUCTOR PROBE ] ────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(bytes memory data) payable {
    deployer = msg.sender;
    value = msg.value;
    dataHash = keccak256(data);
  }
}

// ┌─ MutatingCodeReader ───────────────────────────────────────────────────────
contract MutatingCodeReader {
  uint256 public calls;

  // ░░▒▒▓▓██ [ MUTATING READER ] ──────────────────────────────────────────────

  // ┌─ fallback ─────
  fallback() external {
    calls++;
  }
}

// ┌─ OversizedCodeReader ──────────────────────────────────────────────────────
contract OversizedCodeReader {
  // ░░▒▒▓▓██ [ OVERSIZED READER ] ─────────────────────────────────────────────

  // ┌─ fallback ─────
  fallback() external {
    assembly {
      return(0, 49153)
    }
  }
}

// ┌─ CompressedInitCodeTest ───────────────────────────────────────────────────
contract CompressedInitCodeTest is TestKernel {
  CompressedCodeHarness internal harness;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    harness = CompressedCodeHarness(_deployCode('test/libraries/CompressedInitCode.t.sol:CompressedCodeHarness'));
  }

  // ░░▒▒▓▓██ [ STORAGE ROUND TRIPS ] ──────────────────────────────────────────

  // ┌─ testFuzz_roundTripAndExactlyOneStorageContract ─────
  function testFuzz_roundTripAndExactlyOneStorageContract(bytes memory data) external {
    uint64 nonce = vm.getNonce(address(harness));
    address store = harness.compress(data);
    assertEq(vm.getNonce(address(harness)), nonce + 1);
    assertTrue(store.code.length <= 24_576);
    assertTrue(store.code[0] != bytes1(0));
    assertEq(harness.read(store), data);
    (bool success, bytes memory returned) = store.staticcall('');
    assertTrue(success);
    assertEq(returned, data);
  }

  // ┌─ test_roundTripLengthBoundaries ─────
  function test_roundTripLengthBoundaries() external {
    uint256[9] memory lengths = [uint256(0), 1, 31, 32, 33, 255, 1024, 26_000, 49_152];
    for (uint256 i; i < lengths.length; ++i) {
      bytes memory data = new bytes(lengths[i]);
      if (data.length != 0) data[data.length - 1] = 0xab;
      address store = harness.compress(data);
      assertEq(harness.read(store), data);
      assertTrue(store.code.length <= 24_576);
    }
  }

  // ┌─ test_rawStorageRemainsByteExact ─────
  function test_rawStorageRemainsByteExact() external {
    bytes memory code = hex'0060feabcdef';
    address store = harness.deployInitCode(code);
    assertEq(store.code, bytes.concat(hex'00', code));
    assertEq(harness.read(store), code);
  }

  // ░░▒▒▓▓██ [ STORAGE AND READER LIMITS ] ────────────────────────────────────

  // ┌─ test_compressionRejectsUndeployableInputLength ─────
  function test_compressionRejectsUndeployableInputLength() external {
    bytes memory code = new bytes(49_153);
    vm.expectRevert(LibCompressedInitCode.InitCodeDeploymentFailed.selector);
    harness.compress(code);
  }

  // ┌─ test_incompressiblePayloadStillEnforcesStorageLimit ─────
  function test_incompressiblePayloadStillEnforcesStorageLimit() external {
    bytes memory code = new bytes(30_000);
    for (uint256 i; i < code.length; i += 32) {
      bytes32 word = keccak256(abi.encode(i));
      assembly ('memory-safe') {
        mstore(add(add(code, 0x20), i), word)
      }
    }
    vm.expectRevert(LibCompressedInitCode.InitCodeDeploymentFailed.selector);
    harness.compress(code);
  }

  // ┌─ test_readerIsStaticAndCapsOutput ─────
  function test_readerIsStaticAndCapsOutput() external {
    address mutating = _deployCode('test/libraries/CompressedInitCode.t.sol:MutatingCodeReader');
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(mutating);
    assertEq(MutatingCodeReader(mutating).calls(), 0);
    address oversized = _deployCode('test/libraries/CompressedInitCode.t.sol:OversizedCodeReader');
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(oversized);
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(address(0x1234));
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT CONTEXT ] ───────────────────────────────────────────

  // ┌─ test_createPreservesFactoryContextAndValue ─────
  function test_createPreservesFactoryContextAndValue() external {
    bytes memory code = vm.getCode('test/libraries/wrappers/LibStoredInitCodeExternal.sol:TestContract');
    address store = harness.compress(code);
    vm.deal(address(harness), 1 ether);
    address deployed = harness.createWithStoredInitCode(store, 1 ether);
    assertEq(TestContract(deployed).getValue(), 123);
    assertEq(deployed.balance, 1 ether);
  }

  // ┌─ test_create2HashesOriginalBytesAndRejectsDuplicateSalt ─────
  function test_create2HashesOriginalBytesAndRejectsDuplicateSalt() external {
    bytes memory code = vm.getCode('test/libraries/wrappers/LibStoredInitCodeExternal.sol:TestContract');
    address store = harness.compress(code);
    bytes32 salt = keccak256('compressed');
    address expected =
      harness.calculateCreate2Address(harness.getCreate2Prefix(address(harness)), salt, uint256(keccak256(code)));
    address actual = harness.create2WithStoredInitCode(store, salt);
    assertEq(actual, expected);
    assertEq(TestContract(actual).getValue(), 123);
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.create2WithStoredInitCode(store, salt);
  }

  // ┌─ testFuzz_constructorArgsMemoryAndCalldata ─────
  function testFuzz_constructorArgsMemoryAndCalldata(bytes memory data, bytes32 salt) external {
    bytes memory code = vm.getCode('test/libraries/CompressedInitCode.t.sol:CompressedConstructorProbe');
    address store = harness.compress(code);
    bytes memory args = abi.encode(data);
    vm.deal(address(harness), 2 ether);
    for (uint256 i; i < 2; ++i) {
      bytes32 actualSalt = keccak256(abi.encode(salt, i));
      address expected = harness.calculateCreate2Address(
        harness.getCreate2Prefix(address(harness)), actualSalt, uint256(keccak256(bytes.concat(code, args)))
      );
      address deployed = i == 0
        ? harness.create2Memory(store, actualSalt, 1 ether, args)
        : harness.create2Calldata(store, actualSalt, 1 ether, args);
      assertEq(deployed, expected);
      CompressedConstructorProbe probe = CompressedConstructorProbe(deployed);
      assertEq(probe.deployer(), address(harness));
      assertEq(probe.value(), 1 ether);
      assertEq(probe.dataHash(), keccak256(data));
    }
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // SplitInitCode.t
// ║  ██▀▀     ▀▀██   Split storage boundaries, integrity, and deployment context.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  STORAGE ADAPTERS
// ║  split(...)
// ║  read(...)
// ║  capacity()
// ║  verify(...)
// ║
// ║  DEPLOYMENT ADAPTER
// ║  create2WithValue(...)
// ║
// ║  FIXTURE
// ║  setUp()
// ║
// ║  STORAGE ROUND TRIPS
// ║  testFuzz_roundTrip(...)
// ║  testFuzz_roundTripAcrossChunkBoundary(...)
// ║  test_chunkBoundariesAndCapacity()
// ║  _check(...)
// ║
// ║  STORAGE INTEGRITY
// ║  test_rejectsMissingTruncatedTrailingAndExecutableSecondary()
// ║  test_attestationRejectsMutatedPayloadFooterAndReader()
// ║
// ║  DEPLOYMENT CONTEXT
// ║  testFuzz_constructorContextValueAndCreate2(...)
// ╚═════

import { LibSplitInitCode, SplitInitCodeReader } from 'src/libraries/LibSplitInitCode.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { CompressedConstructorProbe } from './CompressedInitCode.t.sol';
import { LibStoredInitCodeExternal } from './wrappers/LibStoredInitCodeExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ SplitCodeHarness ─────────────────────────────────────────────────────────
contract SplitCodeHarness is LibStoredInitCodeExternal {
  // ░░▒▒▓▓██ [ STORAGE ADAPTERS ] ─────────────────────────────────────────────

  // ┌─ split ─────
  function split(bytes memory code) external returns (address, address) {
    return LibSplitInitCode.deployInitCode(code);
  }

  // ┌─ read ─────
  function read(address store) external view returns (bytes memory) {
    return LibStoredInitCode.getInitCode(store);
  }

  // ┌─ capacity ─────
  function capacity() external pure returns (uint256 first, uint256 total) {
    return (LibSplitInitCode.firstChunkCapacity(), LibSplitInitCode.maximumInitCodeSize());
  }

  // ┌─ verify ─────
  function verify(address primary, address secondary, bytes memory original) external view {
    require(
      secondary.codehash == keccak256(LibSplitInitCode.getSecondaryRuntime(original)), 'secondary runtime mismatch'
    );
    require(
      primary.codehash == keccak256(LibSplitInitCode.getPrimaryRuntime(original, secondary)), 'primary runtime mismatch'
    );
    require(keccak256(LibStoredInitCode.getInitCode(primary)) == keccak256(original), 'read mismatch');
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT ADAPTER ] ───────────────────────────────────────────

  // ┌─ create2WithValue ─────
  function create2WithValue(address store, bytes32 salt, uint256 value, bytes memory args) external returns (address) {
    return LibStoredInitCode.create2WithStoredInitCode(store, salt, value, args);
  }
}

// ┌─ SplitInitCodeTest ────────────────────────────────────────────────────────
contract SplitInitCodeTest is TestKernel {
  SplitCodeHarness internal harness;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    harness = SplitCodeHarness(_deployCode('test/libraries/SplitInitCode.t.sol:SplitCodeHarness'));
  }

  // ░░▒▒▓▓██ [ STORAGE ROUND TRIPS ] ──────────────────────────────────────────

  // ┌─ testFuzz_roundTrip ─────
  function testFuzz_roundTrip(bytes memory data) external {
    _check(data);
  }

  // ┌─ testFuzz_roundTripAcrossChunkBoundary ─────
  function testFuzz_roundTripAcrossChunkBoundary(uint256 length, bytes32 seed) external {
    (, uint256 capacity) = harness.capacity();
    length = bound(length, 24_000, capacity);
    bytes memory data = new bytes(length);
    for (uint256 i; i < length; i += 32) {
      bytes32 word = keccak256(abi.encode(seed, i));
      assembly ('memory-safe') {
        mstore(add(add(data, 32), i), word)
      }
    }
    _check(data);
  }

  // ┌─ test_chunkBoundariesAndCapacity ─────
  function test_chunkBoundariesAndCapacity() external {
    (uint256 first, uint256 total) = harness.capacity();
    uint256[9] memory lengths = [uint256(0), 1, 31, 32, first - 1, first, first + 1, total - 1, total];
    for (uint256 i; i < lengths.length; ++i) {
      bytes memory data = new bytes(lengths[i]);
      if (data.length > 0) data[data.length - 1] = 0xab;
      _check(data);
    }
    vm.expectRevert(LibSplitInitCode.InitCodeDeploymentFailed.selector);
    harness.split(new bytes(total + 1));
  }

  // ┌─ _check ─────
  function _check(bytes memory data) internal returns (address primary, address secondary) {
    uint64 nonce = vm.getNonce(address(harness));
    (primary, secondary) = harness.split(data);
    assertEq(vm.getNonce(address(harness)), nonce + 2, 'exactly two storage contracts');
    assertTrue(primary.code.length <= 24_576, 'primary fits');
    assertTrue(secondary.code.length <= 24_576, 'secondary fits');
    assertTrue(primary.code[0] != 0, 'executable primary');
    assertTrue(secondary.code[0] == 0, 'inert secondary');
    assertEq(harness.read(primary), data, 'exact payload');
    harness.verify(primary, secondary, data);
    (bool success, bytes memory returned) = primary.staticcall(hex'deadbeef');
    assertTrue(success, 'read ignores calldata');
    assertEq(returned, data, 'same bytes for direct callers');
  }

  // ░░▒▒▓▓██ [ STORAGE INTEGRITY ] ────────────────────────────────────────────

  // ┌─ test_rejectsMissingTruncatedTrailingAndExecutableSecondary ─────
  function test_rejectsMissingTruncatedTrailingAndExecutableSecondary() external {
    (uint256 first,) = harness.capacity();
    bytes memory original = new bytes(first + 33);
    (address primary, address secondary) = _check(original);
    bytes memory saved = secondary.code;
    vm.etch(secondary, '');
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(primary);
    vm.etch(secondary, hex'00');
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(primary);
    vm.etch(secondary, bytes.concat(saved, hex'00'));
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(primary);
    saved[0] = 0x60;
    vm.etch(secondary, saved);
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.read(primary);
  }

  // ┌─ test_attestationRejectsMutatedPayloadFooterAndReader ─────
  function test_attestationRejectsMutatedPayloadFooterAndReader() external {
    (uint256 first,) = harness.capacity();
    bytes memory original = new bytes(first + 33);
    (address primary, address secondary) = _check(original);
    bytes memory savedPrimary = primary.code;
    uint256[5] memory offsets = [
      uint256(1),
      type(SplitInitCodeReader).runtimeCode.length,
      savedPrimary.length - 24,
      savedPrimary.length - 4,
      savedPrimary.length - 1
    ];
    for (uint256 i; i < offsets.length; ++i) {
      savedPrimary[offsets[i]] ^= 0x01;
      vm.etch(primary, savedPrimary);
      vm.expectRevert(bytes('primary runtime mismatch'));
      harness.verify(primary, secondary, original);
      savedPrimary[offsets[i]] ^= 0x01;
    }
    vm.etch(primary, savedPrimary);
    bytes memory tail = secondary.code;
    tail[tail.length - 1] ^= 0x01;
    vm.etch(secondary, tail);
    vm.expectRevert(bytes('secondary runtime mismatch'));
    harness.verify(primary, secondary, original);
    assertTrue(keccak256(harness.read(primary)) != keccak256(original), 'hash must catch wrong bytes');
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT CONTEXT ] ───────────────────────────────────────────

  // ┌─ testFuzz_constructorContextValueAndCreate2 ─────
  function testFuzz_constructorContextValueAndCreate2(bytes memory data, bytes32 salt) external {
    bytes memory code = vm.getCode('test/libraries/CompressedInitCode.t.sol:CompressedConstructorProbe');
    (address store,) = harness.split(code);
    bytes memory args = abi.encode(data);
    address expected = harness.calculateCreate2Address(
      harness.getCreate2Prefix(address(harness)), salt, uint256(keccak256(bytes.concat(code, args)))
    );
    address deployed = harness.create2WithStoredInitCodeCD(store, salt, args);
    assertEq(deployed, expected, 'original initcode controls CREATE2');
    CompressedConstructorProbe probe = CompressedConstructorProbe(deployed);
    assertEq(probe.deployer(), address(harness), 'factory context');
    assertEq(probe.dataHash(), keccak256(data), 'constructor bytes');
    vm.deal(address(harness), 1 ether);
    bytes32 paidSalt = keccak256(abi.encode(salt));
    address paid = harness.create2WithValue(store, paidSalt, 1 ether, args);
    assertEq(CompressedConstructorProbe(paid).value(), 1 ether, 'constructor value');
    assertEq(paid.balance, 1 ether, 'forwarded ETH');
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    harness.create2WithStoredInitCodeCD(store, salt, args);
  }
}

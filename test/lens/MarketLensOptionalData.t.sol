// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketLensOptionalData.t
//  \ ^ /   Optional constraints, lifecycle, and proposal response validation.
//    V
//
//  FIXTURE
//  setUp()
//
//  CONSTRAINT DATA
//  test_constraints_CurrentAndTrailingResponsesPreserveEveryField()
//  test_constraints_LegacyTenWordsKeepOriginalBounds()
//  testFuzz_constraints_RejectIncompleteResponses(...)
//  test_constraints_RejectDirtyIntegerWordsAndPreserveRevert()
//  _constraints()
//  _mockConstraints(...)
//
//  LIFECYCLE DATA
//  test_lifecycle_ZeroIsSupportedButMissingOrPartialGetterIsAbsent()
//  test_lifecycle_ClosureEndsPhaseWithoutDiscardingTermsOrDefault()
//  _mockLifecycle(...)
//
//  PENDING APR DATA
//  test_pendingAprChange_AbsentCompleteAndMalformedResponses()
// ═════

import { HooksInstanceDataLib, MarketParameterConstraints } from 'src/lens/HooksInstanceData.sol';
import { MarketLifecycleData } from 'src/lens/MarketLifecycleData.sol';
import { PeriodicPendingAprChangeData } from 'src/lens/HooksConfigData.sol';
import { LensProbeHarness } from '../mocks/LensMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ MarketLensOptionalDataTest ───────────────────────────────────────────────
contract MarketLensOptionalDataTest is TestKernel {
  LensProbeHarness internal probe;
  address internal constant Target = address(0xDA7A);

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    probe = LensProbeHarness(_deployCode('test/mocks/LensMocks.sol:LensProbeHarness'));
  }

  // ░░▒▒▓▓██ [ CONSTRAINT DATA ] ──────────────────────────────────────────────

  // ┌─ test_constraints_CurrentAndTrailingResponsesPreserveEveryField ─────
  function test_constraints_CurrentAndTrailingResponsesPreserveEveryField() external {
    bytes memory expected = _constraints();
    _mockConstraints(expected);
    (MarketParameterConstraints memory data, bool present) = probe.constraints(Target);
    assertTrue(present, 'repayment bounds present');
    assertEq(abi.encode(data), expected, 'current fields');
    _mockConstraints(bytes.concat(expected, abi.encode(uint256(999))));
    (data, present) = probe.constraints(Target);
    assertTrue(present, 'trailing data accepted');
    assertEq(abi.encode(data), expected, 'trailing data ignored');
  }

  // ┌─ test_constraints_LegacyTenWordsKeepOriginalBounds ─────
  function test_constraints_LegacyTenWordsKeepOriginalBounds() external {
    bytes memory legacy = _constraints();
    assembly ('memory-safe') {
      mstore(legacy, 0x140)
    }
    _mockConstraints(legacy);
    (MarketParameterConstraints memory data, bool present) = probe.constraints(Target);
    assertFalse(present, 'legacy has no repayment bounds');
    assertEq(abi.encode(data), bytes.concat(legacy, new bytes(64)), 'legacy fields retained');
  }

  // ┌─ testFuzz_constraints_RejectIncompleteResponses ─────
  function testFuzz_constraints_RejectIncompleteResponses(uint16 input) external {
    uint256 length = uint256(input) % 384;
    if (length == 320) length = 321;
    _mockConstraints(new bytes(length));
    vm.expectRevert(HooksInstanceDataLib.InvalidParameterConstraints.selector);
    probe.constraints(Target);
  }

  // ┌─ test_constraints_RejectDirtyIntegerWordsAndPreserveRevert ─────
  function test_constraints_RejectDirtyIntegerWordsAndPreserveRevert() external {
    bytes memory result = _constraints();
    assembly ('memory-safe') {
      mstore(add(result, 0x60), 0x10000)
    }
    _mockConstraints(result);
    vm.expectRevert();
    probe.constraints(Target);

    result = _constraints();
    assembly ('memory-safe') {
      mstore(add(result, 0x180), 0x100000000)
    }
    _mockConstraints(result);
    vm.expectRevert();
    probe.constraints(Target);

    bytes memory reason = abi.encodeWithSignature('ConstraintReadFailed(uint256)', 42);
    vm.mockCallRevert(Target, abi.encodeWithSignature('getParameterConstraints()'), reason);
    vm.expectRevert(reason);
    probe.constraints(Target);
  }

  // ┌─ _constraints ─────
  function _constraints() internal pure returns (bytes memory) {
    return
      abi.encode(uint256[12]([uint256(1), 90 days, 2, 10_000, 3, 10_000, 4, 365 days, 5, 10_000, 90 days, 730 days]));
  }

  // ┌─ _mockConstraints ─────
  function _mockConstraints(bytes memory result) internal {
    vm.mockCall(Target, abi.encodeWithSignature('getParameterConstraints()'), result);
  }

  // ░░▒▒▓▓██ [ LIFECYCLE DATA ] ───────────────────────────────────────────────

  // ┌─ test_lifecycle_ZeroIsSupportedButMissingOrPartialGetterIsAbsent ─────
  function test_lifecycle_ZeroIsSupportedButMissingOrPartialGetterIsAbsent() external {
    _mockLifecycle(0, 0, 0, 0);
    MarketLifecycleData memory data = probe.lifecycle(Target, false);
    assertTrue(data.isPresent, 'zero terms are supported');
    assertFalse(data.isInRepayment, 'no repayment date');
    _mockLifecycle(10, 20, 30, 30);
    vm.mockCall(Target, abi.encodeWithSignature('defaultedAt()'), new bytes(31));
    data = probe.lifecycle(Target, false);
    MarketLifecycleData memory absent;
    assertEq(abi.encode(data), abi.encode(absent), 'no partial lifecycle');
    vm.mockCallRevert(Target, abi.encodeWithSignature('defaultedAt()'), 'unsupported');
    assertEq(abi.encode(probe.lifecycle(Target, false)), abi.encode(absent), 'revert is absent');
  }

  // ┌─ test_lifecycle_ClosureEndsPhaseWithoutDiscardingTermsOrDefault ─────
  function test_lifecycle_ClosureEndsPhaseWithoutDiscardingTermsOrDefault() external {
    vm.warp(100);
    _mockLifecycle(100, 0, 100, 90);
    vm.mockCall(Target, abi.encodeWithSignature('repaymentPeriod()'), abi.encode(uint256(0), uint256(999)));
    MarketLifecycleData memory data = probe.lifecycle(Target, false);
    assertTrue(data.isInRepayment, 'date inclusive');
    assertEq(data.defaultedAt, 90, 'recorded marker');
    data = probe.lifecycle(Target, true);
    assertTrue(data.isPresent, 'closed getters supported');
    assertFalse(data.isInRepayment, 'closed phase');
    assertEq(data.repaymentDate, 100, 'terms retained');
    assertEq(data.repaymentPeriod, 0, 'trailing data ignored');
    assertEq(data.defaultedAt, 90, 'marker retained');
  }

  // ┌─ _mockLifecycle ─────
  function _mockLifecycle(uint256 date, uint256 period, uint256 deadline, uint256 defaultedAt) internal {
    vm.mockCall(Target, abi.encodeWithSignature('repaymentDate()'), abi.encode(date));
    vm.mockCall(Target, abi.encodeWithSignature('repaymentPeriod()'), abi.encode(period));
    vm.mockCall(Target, abi.encodeWithSignature('repaymentDeadline()'), abi.encode(deadline));
    vm.mockCall(Target, abi.encodeWithSignature('defaultedAt()'), abi.encode(defaultedAt));
  }

  // ░░▒▒▓▓██ [ PENDING APR DATA ] ─────────────────────────────────────────────

  // ┌─ test_pendingAprChange_AbsentCompleteAndMalformedResponses ─────
  function test_pendingAprChange_AbsentCompleteAndMalformedResponses() external {
    bytes memory input = abi.encodeWithSignature('getPendingAprChange(address)', address(1));
    vm.mockCall(Target, input, abi.encode(uint256(500), uint256(10)));
    assertFalse(probe.pendingAprChange(Target, address(1)).isPresent, 'two words lack bounds');
    vm.mockCallRevert(Target, input, 'unsupported');
    assertFalse(probe.pendingAprChange(Target, address(1)).isPresent, 'missing getter');
    vm.clearMockedCalls();
    vm.mockCall(Target, input, new bytes(128));
    PeriodicPendingAprChangeData memory data = probe.pendingAprChange(Target, address(1));
    assertTrue(data.isPresent, 'no proposal still supported');
    assertEq(data.proposalTimestamp, 0, 'no proposal');
    vm.mockCall(Target, input, abi.encode(uint256(500), uint256(10), uint256(20), uint256(30), uint256(99)));
    data = probe.pendingAprChange(Target, address(1));
    assertTrue(data.isPresent, 'proposal getter supported');
    assertEq(data.annualInterestBips, 500, 'proposal apr');
    assertEq(data.proposalTimestamp, 10, 'proposal time');
    assertEq(data.responseWindowStart, 20, 'response starts');
    assertEq(data.responseWindowEnd, 30, 'response ends');
    vm.mockCall(Target, input, abi.encode(uint256(65_536), uint256(10), uint256(20), uint256(30)));
    vm.expectRevert();
    probe.pendingAprChange(Target, address(1));
  }
}

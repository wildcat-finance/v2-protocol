// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketAccountingReader.t
//  \ ^ /   Legacy and extended market accounting response validation.
//    V
//
//  ACCOUNTING RESPONSES
//  set(...)
//  fallback(...)
//
//  STATE READS
//  test_legacyAndExtendedStatePreserveAllFields()
//  readState(...)
//
//  BATCH READS
//  test_legacyAndExtendedBatchPreserveWideCounters()
//  readBatch(...)
//
//  MALFORMED RESPONSES
//  test_rejectsTruncatedAndDirtyResponsesAndBubblesReverts()
// ═════

import { MarketAccountingReader } from 'src/lens/MarketAccountingReader.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { WithdrawalBatch } from 'src/libraries/Withdrawal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ AccountingResponseMock ───────────────────────────────────────────────────
contract AccountingResponseMock {
  bytes private response;
  bool private shouldRevert;

  // ░░▒▒▓▓██ [ ACCOUNTING RESPONSES ] ─────────────────────────────────────────

  // ┌─ set ─────
  function set(bytes memory data, bool revertCall) external {
    response = data;
    shouldRevert = revertCall;
  }

  // ┌─ fallback ─────
  fallback(bytes calldata) external returns (bytes memory) {
    if (shouldRevert) revert('market revert');
    return response;
  }
}

// ┌─ MarketAccountingReaderTest ───────────────────────────────────────────────
contract MarketAccountingReaderTest is TestKernel {
  // ░░▒▒▓▓██ [ STATE READS ] ──────────────────────────────────────────────────

  // ┌─ test_legacyAndExtendedStatePreserveAllFields ─────
  function test_legacyAndExtendedStatePreserveAllFields() external {
    AccountingResponseMock mock = new AccountingResponseMock();
    MarketState memory expected;
    expected.maxTotalSupply = type(uint128).max;
    expected.scaledTotalSupply = type(uint104).max;
    expected.scaleFactor = type(uint112).max;
    expected.lastInterestAccruedTimestamp = 42;
    expected.withdrawalRemainder = 999;
    mock.set(abi.encode(expected), false);
    assertEq(keccak256(abi.encode(this.readState(address(mock), false))), keccak256(abi.encode(expected)));
    assertEq(keccak256(abi.encode(this.readState(address(mock), true))), keccak256(abi.encode(expected)));
    bytes memory legacy = abi.encode(expected);
    assembly {
      mstore(legacy, 0x1c0)
    }
    mock.set(legacy, false);
    expected.withdrawalRemainder = 0;
    assertEq(keccak256(abi.encode(this.readState(address(mock), false))), keccak256(abi.encode(expected)));
    assertEq(keccak256(abi.encode(this.readState(address(mock), true))), keccak256(abi.encode(expected)));
  }

  // ┌─ readState ─────
  function readState(address market, bool previous) external view returns (MarketState memory) {
    if (previous) return MarketAccountingReader.previousState(WildcatMarket(market));
    return MarketAccountingReader.currentState(WildcatMarket(market));
  }

  // ░░▒▒▓▓██ [ BATCH READS ] ──────────────────────────────────────────────────

  // ┌─ test_legacyAndExtendedBatchPreserveWideCounters ─────
  function test_legacyAndExtendedBatchPreserveWideCounters() external {
    AccountingResponseMock mock = new AccountingResponseMock();
    WithdrawalBatch memory expected;
    expected.scaledTotalAmount = type(uint128).max;
    expected.scaledAmountBurned = type(uint128).max - 1;
    expected.normalizedAmountPaid = 91;
    expected.paymentRemainder = 123;
    mock.set(abi.encode(expected), false);
    assertEq(keccak256(abi.encode(this.readBatch(address(mock)))), keccak256(abi.encode(expected)));
    bytes memory legacy = abi.encode(expected);
    assembly {
      mstore(legacy, 0x60)
    }
    mock.set(legacy, false);
    expected.paymentRemainder = 0;
    assertEq(keccak256(abi.encode(this.readBatch(address(mock)))), keccak256(abi.encode(expected)));
  }

  // ┌─ readBatch ─────
  function readBatch(address market) external view returns (WithdrawalBatch memory) {
    return MarketAccountingReader.withdrawalBatch(WildcatMarket(market), 123);
  }

  // ░░▒▒▓▓██ [ MALFORMED RESPONSES ] ──────────────────────────────────────────

  // ┌─ test_rejectsTruncatedAndDirtyResponsesAndBubblesReverts ─────
  function test_rejectsTruncatedAndDirtyResponsesAndBubblesReverts() external {
    AccountingResponseMock mock = new AccountingResponseMock();
    mock.set(new bytes(0x1df), false);
    vm.expectRevert();
    this.readState(address(mock), false);
    mock.set(new bytes(0x7f), false);
    vm.expectRevert();
    this.readBatch(address(mock));
    bytes memory dirty = new bytes(0x60);
    assembly {
      mstore(add(dirty, 0x20), shl(128, 1))
    }
    mock.set(dirty, false);
    vm.expectRevert();
    this.readBatch(address(mock));
    mock.set('', true);
    vm.expectRevert(abi.encodeWithSignature('Error(string)', 'market revert'));
    this.readState(address(mock), true);
  }
}

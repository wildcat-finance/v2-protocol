// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // TransitionAllocatorHarness
// ║  ██▀▀     ▀▀██   Transition arena layout, initialization, and guard checks.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  TRANSITION ALLOCATION
// ║  compareWithSolidity(...)
// ╚═════

import { WildcatMarketBase } from 'src/market/WildcatMarketBase.sol';
import { LifecycleTransition, LifecycleAccrual } from 'src/libraries/MarketLifecycle.sol';
import { FunctionTypeCasts } from 'src/libraries/FunctionTypeCasts.sol';

// ┌─ TransitionAllocatorHarness ───────────────────────────────────────────────
contract TransitionAllocatorHarness is WildcatMarketBase {
  using FunctionTypeCasts for *;

  // ░░▒▒▓▓██ [ TRANSITION ALLOCATION ] ────────────────────────────────────────

  // ┌─ compareWithSolidity ─────
  function compareWithSolidity(LifecycleTransition calldata input)
    external
    pure
    returns (bool zeroed, bool matches, bool guardsIntact, uint256 allocatedBytes)
  {
    uint256 start;
    // poison the free region, with a guard on each side of the arena. no zero-memory assumption.
    assembly {
      let left := mload(0x40)
      mstore(left, 0x12345678)
      start := add(left, 0x20)
      mstore(0x40, start)
      for {
        let offset := 0
      } lt(offset, 0x540) {
        offset := add(offset, 0x20)
      } {
        mstore(add(start, offset), not(0))
      }
      mstore(add(start, 0x540), 0x87654321)
    }
    LifecycleTransition memory actual = _allocateTransition.asTransitionAllocator()();
    assembly {
      let end := mload(0x40)
      allocatedBytes := sub(end, start)
      // reserve the right guard before Solidity allocates the independent reference structs.
      mstore(0x40, add(end, 0x20))
    }

    LifecycleTransition memory empty;
    // the production transition loads these two objects separately too.
    actual.state = empty.state;
    actual.lifecycle = empty.lifecycle;
    zeroed = keccak256(abi.encode(actual)) == keccak256(abi.encode(empty));

    LifecycleTransition memory expected = input;
    actual.state = input.state;
    actual.lifecycle = input.lifecycle;
    // write fields through the arena's existing pointers. replacing the nested structs would
    // hide a bad batch/record pointer or alias between records.
    actual.batch.scaledTotalAmount = input.batch.scaledTotalAmount;
    actual.batch.scaledAmountBurned = input.batch.scaledAmountBurned;
    actual.batch.normalizedAmountPaid = input.batch.normalizedAmountPaid;
    actual.batch.paymentRemainder = input.batch.paymentRemainder;
    actual.batchExpiry = input.batchExpiry;
    actual.batchExpired = input.batchExpired;
    actual.expiryAfterAccrual = input.expiryAfterAccrual;
    actual.accrualCount = input.accrualCount;
    actual.closedAt = input.closedAt;
    actual.repaymentActivated = input.repaymentActivated;
    for (uint256 i; i < 4; ++i) {
      LifecycleAccrual memory record = actual.accruals[i];
      record.from = input.accruals[i].from;
      record.to = input.accruals[i].to;
      record.scaleFactor = input.accruals[i].scaleFactor;
      record.baseInterestRay = input.accruals[i].baseInterestRay;
      record.delinquencyFeeRay = input.accruals[i].delinquencyFeeRay;
      record.protocolFee = input.accruals[i].protocolFee;
    }
    matches = keccak256(abi.encode(actual)) == keccak256(abi.encode(expected));
    assembly {
      guardsIntact := and(eq(mload(sub(start, 0x20)), 0x12345678), eq(mload(add(start, 0x540)), 0x87654321))
    }
  }
}

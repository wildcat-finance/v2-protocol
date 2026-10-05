// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ReentrancyGuard.t
//  \ ^ /   Stateful and view reentrancy protection and recovery.
//    V
//
//  FIXTURE
//  _newHarness()
//
//  REENTRANCY GUARDS
//  test_guard_AllowsOrdinaryStatefulAndViewCalls()
//  test_guard_RejectsStateChangingReentrancyAndRecovers()
//  test_guard_RejectsViewReentrancyAndRecovers()
// ═════

import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';
import { ReentrancyHarness } from '../mocks/ReentrancyHarness.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ ReentrancyGuardTest ──────────────────────────────────────────────────────
contract ReentrancyGuardTest is TestKernel {
  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ _newHarness ─────
  function _newHarness() internal returns (ReentrancyHarness harness) {
    harness = ReentrancyHarness(_deployCode('test/mocks/ReentrancyHarness.sol:ReentrancyHarness'));
  }

  // ░░▒▒▓▓██ [ REENTRANCY GUARDS ] ────────────────────────────────────────────

  // ┌─ test_guard_AllowsOrdinaryStatefulAndViewCalls ─────
  function test_guard_AllowsOrdinaryStatefulAndViewCalls() external {
    ReentrancyHarness harness = _newHarness();

    assertEq(harness.readIndex(), 0);
    assertEq(harness.increment(), 0);
    assertEq(harness.callIncrement(), 1);
    assertEq(harness.callRead(), 2);
    assertEq(harness.increment(), 2);
    assertEq(harness.readIndex(), 3);
  }

  // ┌─ test_guard_RejectsStateChangingReentrancyAndRecovers ─────
  function test_guard_RejectsStateChangingReentrancyAndRecovers() external {
    ReentrancyHarness harness = _newHarness();

    vm.expectRevert(ReentrancyGuard.NoReentrantCalls.selector);
    harness.reenterStateful();

    assertEq(harness.index(), 0);
    assertEq(harness.increment(), 0);
    assertEq(harness.index(), 1);
  }

  // ┌─ test_guard_RejectsViewReentrancyAndRecovers ─────
  function test_guard_RejectsViewReentrancyAndRecovers() external {
    ReentrancyHarness harness = _newHarness();

    vm.expectRevert(ReentrancyGuard.NoReentrantCalls.selector);
    harness.reenterView();

    assertEq(harness.index(), 0);
    assertEq(harness.readIndex(), 0);
  }
}

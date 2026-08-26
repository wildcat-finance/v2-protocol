// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';
import { ReentrancyHarness } from '../mocks/ReentrancyHarness.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract ReentrancyGuardTest is TestKernel {
  function _newHarness() internal returns (ReentrancyHarness harness) {
    harness = ReentrancyHarness(
      _deployCode('test/mocks/ReentrancyHarness.sol:ReentrancyHarness')
    );
  }

  function test_guard_AllowsOrdinaryStatefulAndViewCalls() external {
    ReentrancyHarness harness = _newHarness();

    assertEq(harness.readIndex(), 0);
    assertEq(harness.increment(), 0);
    assertEq(harness.callIncrement(), 1);
    assertEq(harness.callRead(), 2);
    assertEq(harness.increment(), 2);
    assertEq(harness.readIndex(), 3);
  }

  function test_guard_RejectsStateChangingReentrancyAndRecovers() external {
    ReentrancyHarness harness = _newHarness();

    vm.expectRevert(ReentrancyGuard.NoReentrantCalls.selector);
    harness.reenterStateful();

    assertEq(harness.index(), 0);
    assertEq(harness.increment(), 0);
    assertEq(harness.index(), 1);
  }

  function test_guard_RejectsViewReentrancyAndRecovers() external {
    ReentrancyHarness harness = _newHarness();

    vm.expectRevert(ReentrancyGuard.NoReentrantCalls.selector);
    harness.reenterView();

    assertEq(harness.index(), 0);
    assertEq(harness.readIndex(), 0);
  }
}

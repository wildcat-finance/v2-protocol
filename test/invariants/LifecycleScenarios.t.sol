// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { LifecycleFixture } from './LifecycleFixture.sol';

contract LifecycleScenariosTest is LifecycleFixture {
  function setUp() external {
    _setupLifecycle();
  }

  function test_seededMatrixMatchesIndependentOracle() external view {
    _assertLifecycle();
  }

  function test_idleDateAndDeadlineCrossingMatchesOracle() external {
    vm.warp(vm.getBlockTimestamp() + 160 days);
    _assertLifecycle();
    lifecycle.updateState();
    _assertLifecycle();
  }
}

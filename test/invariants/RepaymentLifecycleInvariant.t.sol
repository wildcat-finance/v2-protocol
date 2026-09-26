// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { LifecycleFixture } from './LifecycleFixture.sol';

/// forge-config: default.invariant.fail-on-revert = true
/// forge-config: research.invariant.fail-on-revert = true
contract RepaymentLifecycleInvariantTest is LifecycleFixture, StdInvariant {
  function setUp() external {
    _setupLifecycle();
    lifecycle.beginExploration();
    targetContract(address(lifecycle));
    targetSelector(FuzzSelector({ addr: address(lifecycle), selectors: _lifecycleSelectors() }));
  }

  function invariant_repaymentTimelineAndAccounting() external view {
    _assertLifecycle();
  }

  function afterInvariant() external {
    _finishLifecycle('repayment');
  }
}

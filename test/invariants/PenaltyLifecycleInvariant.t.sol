// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { PenaltyLifecycleFixture } from './LifecycleFixture.sol';

/// forge-config: default.invariant.fail-on-revert = true
/// forge-config: research.invariant.fail-on-revert = true
contract PenaltyLifecycleInvariantTest is PenaltyLifecycleFixture, StdInvariant {
  function setUp() external {
    _setupPenaltyLifecycle();
    lifecycle.beginExploration();
    targetContract(address(lifecycle));
    targetSelector(FuzzSelector({ addr: address(lifecycle), selectors: _lifecycleSelectors() }));
  }

  function invariant_penaltyTimelineAndAccounting() external view {
    _assertLifecycle();
  }

  function afterInvariant() external {
    _finishLifecycle('penalty');
  }
}

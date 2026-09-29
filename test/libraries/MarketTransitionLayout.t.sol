// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketFixture } from '../shared/MarketFixture.sol';
import { TransitionAllocatorHarness } from '../mocks/TransitionAllocatorHarness.sol';
import { LifecycleTransition } from 'src/libraries/MarketLifecycle.sol';

contract MarketTransitionLayoutTest is MarketFixture {
  TransitionAllocatorHarness internal harness;

  function setUp() external {
    Fixture memory fixture = _newMarket(HooksKind.OpenTerm);
    harness = TransitionAllocatorHarness(
      fixture.factory.deployMarket(
        vm.getCode('test/mocks/TransitionAllocatorHarness.sol:TransitionAllocatorHarness')
      )
    );
  }

  function testFuzz_allocatorMatchesSolidityStructs(
    LifecycleTransition memory input
  ) external view {
    (bool zeroed, bool matches, bool guardsIntact, uint256 allocatedBytes) = harness
      .compareWithSolidity(input);
    assertEq(allocatedBytes, 0x540, 'arena reservation');
    assertTrue(zeroed, 'dirty memory cleared');
    assertTrue(matches, 'all fields match independent Solidity allocation');
    assertTrue(guardsIntact, 'no writes outside the arena');
  }
}

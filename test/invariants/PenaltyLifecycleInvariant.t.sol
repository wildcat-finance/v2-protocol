// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // PenaltyLifecycleInvariant.t
//  \ ^ /   Stateful penalty timeline, accounting, and scheduled-drain invariants.
//    V
//
//  CAMPAIGN SETUP
//  setUp()
//
//  PENALTY INVARIANT
//  invariant_penaltyTimelineAndAccounting()
//
//  FINAL DRAIN
//  afterInvariant()
// ═════

import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { PenaltyLifecycleFixture } from './LifecycleFixture.sol';

// ┌─ PenaltyLifecycleInvariantTest ────────────────────────────────────────────
/// forge-config: default.invariant.fail-on-revert = true
contract PenaltyLifecycleInvariantTest is PenaltyLifecycleFixture, StdInvariant {
  // ░░▒▒▓▓██ [ CAMPAIGN SETUP ] ───────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    _setupPenaltyLifecycle();
    lifecycle.beginExploration();
    targetContract(address(lifecycle));
    targetSelector(FuzzSelector({ addr: address(lifecycle), selectors: _lifecycleSelectors() }));
  }

  // ░░▒▒▓▓██ [ PENALTY INVARIANT ] ────────────────────────────────────────────

  // ┌─ invariant_penaltyTimelineAndAccounting ─────
  function invariant_penaltyTimelineAndAccounting() external view {
    _assertLifecycle();
  }

  // ░░▒▒▓▓██ [ FINAL DRAIN ] ──────────────────────────────────────────────────

  // ┌─ afterInvariant ─────
  function afterInvariant() external {
    _finishLifecycle('penalty');
  }
}

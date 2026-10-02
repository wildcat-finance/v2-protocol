// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // RepaymentLifecycleInvariant.t
// ║  ██▀▀     ▀▀██   Stateful repayment timeline, accounting, and scheduled-drain invariants.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CAMPAIGN SETUP
// ║  setUp()
// ║
// ║  REPAYMENT INVARIANT
// ║  invariant_repaymentTimelineAndAccounting()
// ║
// ║  FINAL DRAIN
// ║  afterInvariant()
// ╚═════

import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { LifecycleFixture } from './LifecycleFixture.sol';

// ┌─ RepaymentLifecycleInvariantTest ──────────────────────────────────────────
/// forge-config: default.invariant.fail-on-revert = true
contract RepaymentLifecycleInvariantTest is LifecycleFixture, StdInvariant {
  // ░░▒▒▓▓██ [ CAMPAIGN SETUP ] ───────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    _setupLifecycle();
    lifecycle.beginExploration();
    targetContract(address(lifecycle));
    targetSelector(FuzzSelector({ addr: address(lifecycle), selectors: _lifecycleSelectors() }));
  }

  // ░░▒▒▓▓██ [ REPAYMENT INVARIANT ] ──────────────────────────────────────────

  // ┌─ invariant_repaymentTimelineAndAccounting ─────
  function invariant_repaymentTimelineAndAccounting() external view {
    _assertLifecycle();
  }

  // ░░▒▒▓▓██ [ FINAL DRAIN ] ──────────────────────────────────────────────────

  // ┌─ afterInvariant ─────
  function afterInvariant() external {
    _finishLifecycle('repayment');
  }
}

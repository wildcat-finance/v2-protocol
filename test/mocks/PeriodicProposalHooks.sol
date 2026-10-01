// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // PeriodicProposalHooks
// ║  ██▀▀     ▀▀██   Test-only periodic proposal-window constraints.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  PROPOSAL LIMITS
// ║  constructor(...)
// ║  setProposalWindow(...)
// ║
// ║  PROPOSAL VALIDATION
// ║  _checkPeriodicProposal(...)
// ╚═════

import { AprValidationHooks } from './AprValidationHooks.sol';

// ┌─ PeriodicProposalHooks ────────────────────────────────────────────────────
/// @dev test-only proposal limits. reuse the APR floor and leave proposal management inherited.
contract PeriodicProposalHooks is AprValidationHooks {
  error InvalidProposalWindow(address market, uint32 responseStart, uint32 responseEnd);

  struct ProposalWindow {
    uint32 earliestStart;
    uint32 latestEnd;
  }

  mapping(address => ProposalWindow) public proposalWindows;

  // ░░▒▒▓▓██ [ PROPOSAL LIMITS ] ──────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address administrator) AprValidationHooks(administrator) { }

  // ┌─ setProposalWindow ─────
  function setProposalWindow(address market, uint32 earliestStart, uint32 latestEnd) external {
    proposalWindows[market] = ProposalWindow(earliestStart, latestEnd);
  }

  // ░░▒▒▓▓██ [ PROPOSAL VALIDATION ] ──────────────────────────────────────────

  // ┌─ _checkPeriodicProposal ─────
  function _checkPeriodicProposal(
    address market,
    uint16 proposedApr,
    uint32 responseStart,
    uint32 responseEnd
  )
    internal
    view
    override
  {
    if (proposedApr < minimumApr) revert AprBelowFloor(proposedApr);
    ProposalWindow memory window = proposalWindows[market];
    if (responseStart < window.earliestStart || responseEnd > window.latestEnd) {
      revert InvalidProposalWindow(market, responseStart, responseEnd);
    }
  }
}

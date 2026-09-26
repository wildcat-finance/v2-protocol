// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { AprValidationHooks } from './AprValidationHooks.sol';

/// @dev test-only proposal limits. reuse the APR floor and leave proposal management inherited.
contract PeriodicProposalHooks is AprValidationHooks {
  error InvalidProposalWindow(address market, uint32 responseStart, uint32 responseEnd);

  struct ProposalWindow {
    uint32 earliestStart;
    uint32 latestEnd;
  }

  mapping(address => ProposalWindow) public proposalWindows;

  constructor(address administrator) AprValidationHooks(administrator) {}

  function setProposalWindow(address market, uint32 earliestStart, uint32 latestEnd) external {
    proposalWindows[market] = ProposalWindow(earliestStart, latestEnd);
  }

  function _checkPeriodicProposal(
    address market,
    uint16 proposedApr,
    uint32 responseStart,
    uint32 responseEnd
  ) internal view override {
    if (proposedApr < minimumApr) revert AprBelowFloor(proposedApr);
    ProposalWindow memory window = proposalWindows[market];
    if (responseStart < window.earliestStart || responseEnd > window.latestEnd) {
      revert InvalidProposalWindow(market, responseStart, responseEnd);
    }
  }
}

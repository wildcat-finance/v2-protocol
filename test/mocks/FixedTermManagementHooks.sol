// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';

/// @dev test-only notice floor and reduction budget. use the production setter unchanged.
contract FixedTermManagementHooks is FixedTermHooks {
  error InsufficientTermNotice();
  error TermReductionBudgetExceeded();
  error UnexpectedStoredTerm(uint32 expected, uint32 actual);

  event TermReductionRecorded(
    address indexed market,
    uint32 previousTime,
    uint32 newTime,
    uint32 totalReduction
  );

  mapping(address => uint32) public earliestTermEnd;
  mapping(address => uint32) public reductionBudget;
  mapping(address => uint32) public totalTermReduction;

  constructor(address administrator) FixedTermHooks(administrator, '') {}

  function setTermChangeLimits(address market, uint32 earliestTime, uint32 budget) external {
    earliestTermEnd[market] = earliestTime;
    reductionBudget[market] = budget;
  }

  function _validateFixedTermChange(
    address market,
    uint32 previousTime,
    uint32 newTime
  ) internal view override {
    uint32 storedTime = _hookedMarkets[market].fixedTermEndTime;
    if (storedTime != previousTime) revert UnexpectedStoredTerm(previousTime, storedTime);
    if (newTime < earliestTermEnd[market]) revert InsufficientTermNotice();
  }

  function _afterFixedTermChange(
    address market,
    uint32 previousTime,
    uint32 newTime
  ) internal override {
    uint32 storedTime = _hookedMarkets[market].fixedTermEndTime;
    if (storedTime != newTime) revert UnexpectedStoredTerm(newTime, storedTime);
    // charge the reduction actually stored, so calling this before the maturity write fails.
    uint32 totalReduction = totalTermReduction[market] + (previousTime - storedTime);
    totalTermReduction[market] = totalReduction;
    emit TermReductionRecorded(market, previousTime, storedTime, totalReduction);
    // reject after the feature write too; both owners' state must roll back.
    if (totalReduction > reductionBudget[market]) revert TermReductionBudgetExceeded();
  }
}

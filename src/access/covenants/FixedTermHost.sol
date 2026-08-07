// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../../libraries/MarketState.sol';

/**
 * @title FixedTermHost
 * @dev Host-behaviour mixin: lenders cannot queue withdrawals before a fixed
 *      term end. Mirrors the withdrawal gating of `FixedTermHooks` for
 *      covenant-bearing templates, which need `CovenantHooksCore` as their
 *      base and so can't derive from the standard template.
 *
 *      Term behaviour isn't a covenant. It has no library, holds one word of
 *      storage per market, and declares its own errors and events here rather
 *      than in `ICovenantEvents`, deliberately: editing that shared file
 *      shifts the metadata hash of every covenant library that imports it,
 *      which moves all their CREATE2 addresses at once.
 *
 *      Deliberately minimal relative to `FixedTermHooks`: no term reduction
 *      and no early-closure switches. Add those as a follow-up if a borrower
 *      asks; each is an owner surface and this mixin ships with none.
 */
abstract contract FixedTermHost {
  event FixedTermSet(address indexed market, uint32 fixedTermEndTime);
  error InvalidFixedTerm();
  error WithdrawBeforeTermEnd();

  uint32 public constant MaximumLoanTerm = 365 days;

  mapping(address => uint32) internal _fixedTermEndTime;

  function _initFixedTermHost(address market, uint32 fixedTermEndTime) internal {
    if (
      fixedTermEndTime < block.timestamp ||
      (fixedTermEndTime - block.timestamp) > MaximumLoanTerm
    ) {
      revert InvalidFixedTerm();
    }
    _fixedTermEndTime[market] = fixedTermEndTime;
    emit FixedTermSet(market, fixedTermEndTime);
  }

  /// @dev Wire into `_beforeQueueWithdrawal`. Closed markets always pass:
  ///      closure settles the facility and holding lenders past it protects
  ///      nobody.
  function _fixedTermBeforeQueueWithdrawal(address market, MarketState calldata state) internal view {
    if (!state.isClosed && block.timestamp < _fixedTermEndTime[market]) {
      revert WithdrawBeforeTermEnd();
    }
  }

  function getFixedTermEndTime(address market) external view returns (uint32) {
    return _fixedTermEndTime[market];
  }
}

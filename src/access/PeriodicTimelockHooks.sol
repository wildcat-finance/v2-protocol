// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/PeriodicTermHost.sol';
import './covenants/DrawTimelockCovenant.sol';

/**
 * @title PeriodicTimelockHooks
 * @dev Deployable template: periodic-window revolving hooks plus the draw
 *      timelock. This is the window-aware version the naive design gets
 *      wrong: on a periodic market a fixed delay in seconds no longer
 *      implies exit opportunity, so an announcement here isn't executable
 *      until the end of the first full withdrawal window after it, plus one
 *      batch duration. Even a lender who needs the whole window to react is
 *      out before the money moves.
 *
 *      Covenant words on `hooksData`:
 *        0x40  uint128  threshold    cumulative unannounced headroom
 *        0x60  uint32   delay        seconds; 0 disables; floor is the
 *                                    withdrawal batch duration
 *        0x80  uint32   grace        execution window length
 *        0xa0  uint32   firstWithdrawalWindowStart
 *        0xc0  uint32   periodDuration
 *        0xe0  uint32   withdrawalWindowDuration
 */
contract PeriodicTimelockHooks is CovenantHooksCore, PeriodicTermHost, DrawTimelockCovenant {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'PeriodicTimelockHooks';
  }

  function _timelockBorrower() internal view override returns (address) {
    return borrower;
  }

  /// @dev End of the first full window after `from`, plus one batch duration:
  ///      the earliest moment every announcement-time objector is guaranteed
  ///      out. `executableAt = nextWindowStartAfter(from) + windowDuration
  ///      + batchDuration`, per the covenant map's scoping.
  function _timelockExitFloor(
    address market,
    uint256 from,
    uint32 batchDuration
  ) internal view override returns (uint256) {
    return
      _nextWindowStartAfter(market, from) +
      _periodicTerm[market].withdrawalWindowDuration +
      batchDuration;
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return
      EmptyHooksConfig.setFlag(Bit_Enabled_Borrow).setFlag(Bit_Enabled_QueueWithdrawal);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override {
    _initPeriodicTermHost(
      marketAddress,
      _readUint32Cd(hooksData, 0xa0),
      _readUint32Cd(hooksData, 0xc0),
      _readUint32Cd(hooksData, 0xe0)
    );
    _initDrawTimelockCovenant(
      marketAddress,
      _readUint128Cd(hooksData, 0x40),
      _readUint32Cd(hooksData, 0x60),
      _readUint32Cd(hooksData, 0x80),
      parameters.withdrawalBatchDuration
    );
  }

  function _beforeQueueWithdrawal(
    address market,
    MarketState calldata state
  ) internal view override {
    _periodicBeforeQueueWithdrawal(market, state);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = _covenantDrawnBefore(state);
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _drawTimelockOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; this template has no repayment logic.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}

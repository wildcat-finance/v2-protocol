// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/DrawTimelockCovenant.sol';

/**
 * @title RevolvingTimelockHooks
 * @dev Deployable template: open-term revolving hooks plus the draw timelock.
 *      Draws above a cumulative headroom threshold must be announced at least
 *      one full withdrawal batch duration ahead, so an objecting lender is out
 *      before the money moves.
 *
 *      Covenant words on `hooksData`:
 *        0x40  uint128  threshold   cumulative unannounced headroom per window
 *        0x60  uint32   delay       seconds; 0 disables; floor enforced at
 *                                   creation against `withdrawalBatchDuration`
 *        0x80  uint32   grace       execution window length
 */
contract RevolvingTimelockHooks is CovenantHooksCore, DrawTimelockCovenant {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'RevolvingTimelockHooks';
  }

  function _timelockBorrower() internal view override returns (address) {
    return borrower;
  }

  /// @dev Open-term: exit is continuous and the delay floor (at least one
  ///      batch duration, enforced at creation) already guarantees it.
  function _timelockExitFloor(
    address,
    uint256 from,
    uint32
  ) internal view override returns (uint256) {
    return from;
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override {
    _initDrawTimelockCovenant(
      marketAddress,
      _readUint128Cd(hooksData, 0x40),
      _readUint32Cd(hooksData, 0x60),
      _readUint32Cd(hooksData, 0x80),
      parameters.withdrawalBatchDuration
    );
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = ICovenantMarket(msg.sender).drawnAmount();
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _drawTimelockOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; this covenant has no repayment logic.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}

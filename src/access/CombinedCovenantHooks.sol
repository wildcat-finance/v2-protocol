// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/CleanDownCovenant.sol';
import './covenants/CrossMarketDelinquencyCovenant.sol';

/**
 * @title CombinedCovenantHooks
 * @dev Revolving-market hooks template composing both shipped covenants:
 *      clean-down and the cross-market delinquency gate. Access control is
 *      identical to `OpenTermHooks`.
 *
 *      `hooksData` layout:
 *        0x00  uint128 minimumDeposit
 *        0x20  bool    transfersDisabled
 *        0x40  uint32  cleanDownDuration      (0 disables the covenant)
 *        0x60  uint32  cleanDownInterval      (must exceed duration if set)
 *        0x80  bool    crossMarketGateEnabled
 *        0xa0  bool    gateOnPenaltyOnly      (requires the gate)
 *
 *      All words are optional; omitted trailing words read as zero, and
 *      all-zero covenant words deploy a market with open-term behaviour.
 */
contract CombinedCovenantHooks is
  CovenantHooksCore,
  CleanDownCovenant,
  CrossMarketDelinquencyCovenant
{
  constructor(
    address _deployer,
    bytes memory args
  ) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'CombinedCovenantHooks';
  }

  /// @dev Clean-down observes every draw and every repayment; the gate
  ///      observes every draw.
  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow).setFlag(Bit_Enabled_Repay);
  }

  function _covenantBorrower() internal view override returns (address) {
    return borrower;
  }

  function _covenantArchController() internal view override returns (address) {
    return archControllerAddress;
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override {
    _initCleanDownCovenant(
      marketAddress,
      parameters.asset,
      _readUint32Cd(hooksData, 0x40),
      _readUint32Cd(hooksData, 0x60)
    );
    _initCrossMarketCovenant(
      marketAddress,
      _readBoolCd(hooksData, 0x80),
      _readBoolCd(hooksData, 0xa0)
    );
  }

  /**
   * @dev Covenant enforcement point. Runs before the market updates its drawn
   *      amount or transfers assets.
   *
   *      A draw that leaves the drawn amount at zero — reclaiming the
   *      borrower's own over-repayment — is not credit, and is exempt from
   *      both covenants.
   */
  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _cleanDownOnBorrow(state, drawnAfter);
    if (drawnAfter > 0) _crossMarketOnBorrow(state);
  }

  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata state,
    bytes calldata /* hooksData */
  ) external override {
    _cleanDownOnRepay(state, _drawnAfterRepay(state));
  }
}

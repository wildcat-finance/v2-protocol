// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/CleanDownCovenant.sol';

/**
 * @title CleanDownHooks
 * @dev Revolving-market hooks template with the clean-down covenant only.
 *
 *      Exists to demonstrate — and keep tested — that covenants compose
 *      individually: this template carries no watch-list, no cross-market
 *      storage, and none of the gate's bytecode or borrow-path iteration.
 *
 *      `hooksData` layout:
 *        0x00  uint128 minimumDeposit
 *        0x20  bool    transfersDisabled
 *        0x40  uint32  cleanDownDuration
 *        0x60  uint32  cleanDownInterval
 */
contract CleanDownHooks is CovenantHooksCore, CleanDownCovenant {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'CleanDownHooks';
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow).setFlag(Bit_Enabled_Repay);
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
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    _cleanDownOnBorrow(state, _drawnAfterBorrow(state, normalizedAmount));
  }

  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata state,
    bytes calldata /* hooksData */
  ) external override {
    _cleanDownOnRepay(state, _drawnAfterRepay(state));
  }
}

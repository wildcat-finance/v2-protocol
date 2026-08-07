// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/CrossMarketExposureCapCovenant.sol';

/**
 * @title ExposureCapHooks
 * @dev Deployable template: open-term revolving hooks plus the aggregate
 *      exposure cap. Watches the borrower's other markets through the shared
 *      permissionless watch-list and gates any draw that would take total
 *      debt across them above the cap.
 *
 *      Covenant words on `hooksData`:
 *        0x40  uint128  cap   aggregate debt ceiling; 0 disables
 */
contract ExposureCapHooks is CovenantHooksCore, CrossMarketExposureCapCovenant {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'ExposureCapHooks';
  }

  function _covenantBorrower() internal view override returns (address) {
    return borrower;
  }

  function _covenantArchController() internal view override returns (address) {
    return archControllerAddress;
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata,
    bytes calldata hooksData
  ) internal override {
    _initExposureCapCovenant(marketAddress, _readUint128Cd(hooksData, 0x40));
    CrossMarketGateLib.watch(_watchedMarkets, isWatchedMarket, marketAddress);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = _covenantDrawnBefore(state);
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _exposureCapOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; this covenant has no repayment logic.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}

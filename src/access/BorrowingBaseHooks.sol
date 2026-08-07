// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/BorrowingBaseCovenant.sol';

/**
 * @title BorrowingBaseHooks
 * @dev Deployable template: open-term revolving hooks plus the borrowing
 *      base. Static-haircut variant: per-token advance rates fixed at market
 *      creation, collateral valued at face in asset terms, no oracle.
 *
 *      `hooksData` is standard ABI encoding of
 *      `(uint128 minimumDeposit, bool transfersDisabled, address[] tokens,
 *        uint16[] advanceRatesBips)`. Empty arrays disable the covenant.
 */
contract BorrowingBaseHooks is CovenantHooksCore, BorrowingBaseCovenant {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'BorrowingBaseHooks';
  }

  function _borrowingBaseBorrower() internal view override returns (address) {
    return borrower;
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata,
    bytes calldata hooksData
  ) internal override {
    address[] memory tokens;
    uint16[] memory rates;
    if (hooksData.length > 0x40) {
      (, , tokens, rates) = abi.decode(hooksData, (uint128, bool, address[], uint16[]));
    }
    _initBorrowingBaseCovenant(marketAddress, tokens, rates);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = _covenantDrawnBefore(state);
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _borrowingBaseOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; this covenant has no repayment logic.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}

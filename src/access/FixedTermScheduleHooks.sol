// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/FixedTermHost.sol';
import './covenants/CommitmentScheduleCovenant.sol';

/**
 * @title FixedTermScheduleHooks
 * @dev Deployable template: fixed-term revolving hooks plus the
 *      commitment-reduction schedule. This is the amortising fixed-term
 *      revolver: lenders are locked until term end, and the schedule is what
 *      gives them a de-risking path while they are, since the borrower's
 *      drawn exposure has to step down on the agreed dates regardless.
 *
 *      `hooksData` is standard ABI encoding of
 *      `(uint128 minimumDeposit, bool transfersDisabled,
 *        uint32 fixedTermEndTime, uint40[] steps, uint128[] ceilings)`.
 *      The three fixed heads land at offsets `0x00`, `0x20` and `0x40`;
 *      the term is mandatory, the schedule optional (empty arrays disable
 *      it, leaving a plain fixed-term covenant host).
 */
contract FixedTermScheduleHooks is
  CovenantHooksCore,
  FixedTermHost,
  CommitmentScheduleCovenant
{
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'FixedTermScheduleHooks';
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return
      EmptyHooksConfig.setFlag(Bit_Enabled_Borrow).setFlag(Bit_Enabled_QueueWithdrawal);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata,
    bytes calldata hooksData
  ) internal override {
    uint40[] memory steps;
    uint128[] memory ceilings;
    if (hooksData.length > 0x60) {
      (, , , steps, ceilings) = abi.decode(
        hooksData,
        (uint128, bool, uint32, uint40[], uint128[])
      );
    }
    _initFixedTermHost(marketAddress, _readUint32Cd(hooksData, 0x40));
    _initCommitmentScheduleCovenant(marketAddress, steps, ceilings);
  }

  function _beforeQueueWithdrawal(
    address market,
    MarketState calldata state
  ) internal view override {
    _fixedTermBeforeQueueWithdrawal(market, state);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = _covenantDrawnBefore(state);
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _commitmentScheduleOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; this template has no repayment logic.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}

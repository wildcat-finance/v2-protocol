// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './covenants/CovenantHooksCore.sol';
import './covenants/CommitmentScheduleCovenant.sol';

/**
 * @title RevolvingScheduleHooks
 * @dev Deployable template: open-term revolving hooks plus the
 *      commitment-reduction schedule covenant. Implements amortising revolvers
 *      and, as the schedule's terminal case, availability-period expiry.
 *
 *      `hooksData` is standard ABI encoding of
 *      `(uint128 minimumDeposit, bool transfersDisabled, uint40[] steps,
 *        uint128[] ceilings)`. The two fixed heads land at the offsets
 *      `CovenantHooksCore` reads for its own fields, and empty arrays disable
 *      the covenant.
 */
contract RevolvingScheduleHooks is CovenantHooksCore, CommitmentScheduleCovenant {
  constructor(address _deployer, bytes memory args) CovenantHooksCore(_deployer, args) {}

  function version() external pure override returns (string memory) {
    return 'RevolvingScheduleHooks';
  }

  function _requiredCovenantFlags() internal pure override returns (HooksConfig) {
    return EmptyHooksConfig.setFlag(Bit_Enabled_Borrow);
  }

  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata,
    bytes calldata hooksData
  ) internal override {
    uint40[] memory steps;
    uint128[] memory ceilings;
    if (hooksData.length > 0x40) {
      (, , steps, ceilings) = abi.decode(hooksData, (uint128, bool, uint40[], uint128[]));
    }
    _initCommitmentScheduleCovenant(marketAddress, steps, ceilings);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata /* extraData */
  ) external override {
    uint256 drawnBefore = ICovenantMarket(msg.sender).drawnAmount();
    uint256 drawnAfter = _drawnAfterBorrow(state, normalizedAmount);
    _commitmentScheduleOnBorrow(drawnBefore, drawnAfter);
  }

  /// @dev Required by `IHooks`; this covenant has no repayment logic.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}
}

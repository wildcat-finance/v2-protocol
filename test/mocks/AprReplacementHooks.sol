// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { AprChange } from 'src/access/BaseHooks.sol';
import { TemporaryReserveRatio } from 'src/access/MarketConstraintHooks.sol';
import { AprValidationPolicy } from './AprValidationPolicy.sol';
import { AprReplacementPolicy } from './AprReplacementPolicy.sol';
import { OpenTransferPolicy } from './TransferFeatureHooks.sol';
import { FixedTransferPolicy } from './TransferFeatureHooks.sol';
import { PeriodicTransferPolicy } from './TransferFeatureHooks.sol';

/// @dev replace only the default calculation; shared routing stays intact.
contract OpenAprReplacementHooks is OpenTransferPolicy, AprReplacementPolicy {
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_QueueWithdrawal
        ),
        EmptyHooksConfig.setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_SetAnnualInterestAndReserveRatioBips
        )
      )
    )
  {}

  function setValidationBounds(
    uint16 aprFloor,
    uint16 reserveCeiling
  ) public override onlyAdministrator {
    AprValidationPolicy.setValidationBounds(aprFloor, reserveCeiling);
  }

  /// @dev harness-only setup for proving the skipped default leaves nonzero state alone.
  function seedTemporaryReserve(
    address market,
    TemporaryReserveRatio calldata value
  ) external onlyAdministrator {
    _requireHookedMarket(market);
    temporaryExcessReserveRatio[market] = value;
  }

  function _applyDefaultAprUpdate(
    uint16 annualInterestBips,
    MarketState calldata
  ) internal override returns (uint16 effectiveApr, uint16 effectiveReserve) {
    // open APR callbacks have no caller guard. authenticate before _selectAprUpdate writes state.
    _requireHookedMarket(msg.sender);
    // replacing this helper also replaces its bounds check. keep the existing APR range explicit.
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );
    return _selectAprUpdate(annualInterestBips);
  }

  function _checkAprChange(
    AprChange memory change,
    MarketState calldata,
    bytes calldata
  ) internal view override {
    _validateAprChange(change);
  }

  function version() external pure override returns (string memory) {
    return 'OpenAprReplacementHooks';
  }
}

/// @dev replace only the default calculation; fixed maturity still runs first.
contract FixedAprReplacementHooks is FixedTransferPolicy, AprReplacementPolicy {
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
      )
    )
  {}

  function setValidationBounds(
    uint16 aprFloor,
    uint16 reserveCeiling
  ) public override onlyAdministrator {
    AprValidationPolicy.setValidationBounds(aprFloor, reserveCeiling);
  }

  /// @dev harness-only setup for proving the skipped default leaves nonzero state alone.
  function seedTemporaryReserve(
    address market,
    TemporaryReserveRatio calldata value
  ) external onlyAdministrator {
    _requireHookedMarket(market);
    temporaryExcessReserveRatio[market] = value;
  }

  function _applyDefaultAprUpdate(
    uint16 annualInterestBips,
    MarketState calldata
  ) internal override returns (uint16 effectiveApr, uint16 effectiveReserve) {
    // fixed APR callbacks have no caller guard either. this replacement writes feature state.
    _requireHookedMarket(msg.sender);
    // replacing this helper also replaces its bounds check. keep the existing APR range explicit.
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );
    return _selectAprUpdate(annualInterestBips);
  }

  function _checkAprChange(
    AprChange memory change,
    MarketState calldata,
    bytes calldata
  ) internal view override {
    _validateAprChange(change);
  }

  function version() external pure override returns (string memory) {
    return 'FixedAprReplacementHooks';
  }
}

/// @dev replace only the default calculation; proposal reductions still bypass it.
contract PeriodicAprReplacementHooks is PeriodicTransferPolicy, AprReplacementPolicy {
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
          .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction)
      )
    )
  {}

  function setValidationBounds(
    uint16 aprFloor,
    uint16 reserveCeiling
  ) public override onlyAdministrator {
    AprValidationPolicy.setValidationBounds(aprFloor, reserveCeiling);
  }

  /// @dev harness-only setup for proving the skipped default leaves nonzero state alone.
  function seedTemporaryReserve(
    address market,
    TemporaryReserveRatio calldata value
  ) external onlyAdministrator {
    _requireHookedMarket(market);
    temporaryExcessReserveRatio[market] = value;
  }

  function _applyDefaultAprUpdate(
    uint16 annualInterestBips,
    MarketState calldata
  ) internal override returns (uint16 effectiveApr, uint16 effectiveReserve) {
    // replacing this helper also replaces its bounds check. keep the existing APR range explicit.
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );
    return _selectAprUpdate(annualInterestBips);
  }

  function _checkAprChange(
    AprChange memory change,
    MarketState calldata,
    bytes calldata
  ) internal view override {
    _validateAprChange(change);
  }

  function version() external pure override returns (string memory) {
    return 'PeriodicAprReplacementHooks';
  }
}

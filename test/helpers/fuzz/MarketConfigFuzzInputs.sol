// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MarketState } from 'src/libraries/MarketState.sol';
import '../../shared/TestConstants.sol';
import { bound } from '../../helpers/VmUtils.sol';
import { MarketInputParameters } from '../../shared/Test.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';

using LibMarketConfigFuzzInputs for MarketConfigFuzzInputs global;

// Used for fuzzing market deployment parameters
struct MarketConfigFuzzInputs {
  bool isAccessControlHooks;
  uint128 maxTotalSupply;
  uint16 protocolFeeBips;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  address feeRecipient;
  uint128 minimumDeposit;
  bool useOnDeposit;
  bool useOnQueueWithdrawal;
  bool useOnExecuteWithdrawal;
  bool useOnTransfer;
  bool transfersDisabled;
  bool allowForceBuyBacks;
  uint16 fixedTermDuration;
  bool allowClosureBeforeTerm;
  bool allowTermReduction;
}

library LibMarketConfigFuzzInputs {
  function constrain(MarketConfigFuzzInputs memory inputs) internal pure {
    inputs.annualInterestBips = uint16(
      bound(inputs.annualInterestBips, MinimumAnnualInterestBips, MaximumAnnualInterestBips)
    );
    inputs.delinquencyFeeBips = uint16(
      bound(inputs.delinquencyFeeBips, MinimumDelinquencyFeeBips, MaximumDelinquencyFeeBips)
    );
    inputs.withdrawalBatchDuration = uint32(
      bound(
        inputs.withdrawalBatchDuration,
        MinimumWithdrawalBatchDuration,
        MaximumWithdrawalBatchDuration
      )
    );
    inputs.reserveRatioBips = uint16(
      bound(inputs.reserveRatioBips, MinimumReserveRatioBips, 9_999)
    );
    inputs.delinquencyGracePeriod = uint32(
      bound(
        inputs.delinquencyGracePeriod,
        MinimumDelinquencyGracePeriod,
        MaximumDelinquencyGracePeriod
      )
    );
    inputs.maxTotalSupply = uint128(bound(inputs.maxTotalSupply, 100, type(uint104).max));
    inputs.minimumDeposit = uint128(bound(inputs.minimumDeposit, 0, inputs.maxTotalSupply));
    inputs.protocolFeeBips = uint16(bound(inputs.protocolFeeBips, 0, 1_000));
    if (inputs.protocolFeeBips > 0) {
      inputs.feeRecipient = address(
        uint160(bound(uint160(inputs.feeRecipient), 1, type(uint160).max))
      );
    }
    if (inputs.isAccessControlHooks) {
      inputs.allowClosureBeforeTerm = false;
      inputs.allowTermReduction = false;
      inputs.fixedTermDuration = 0;
    } else {
      inputs.allowForceBuyBacks = false;
      inputs.fixedTermDuration = uint16(bound(inputs.fixedTermDuration, 1, type(uint16).max));
    }
  }

  function updateParameters(
    MarketConfigFuzzInputs memory inputs,
    MarketInputParameters storage parameters,
    address accessControlTemplate,
    address fixedTermHooksTemplate
  ) internal {
    inputs.constrain();
    parameters.hooksConfig = HooksConfig.wrap(0);

    parameters.feeRecipient = inputs.feeRecipient;
    parameters.maxTotalSupply = inputs.maxTotalSupply;
    parameters.protocolFeeBips = inputs.protocolFeeBips;
    parameters.annualInterestBips = inputs.annualInterestBips;
    parameters.delinquencyFeeBips = inputs.delinquencyFeeBips;
    parameters.withdrawalBatchDuration = inputs.withdrawalBatchDuration;
    parameters.reserveRatioBips = inputs.reserveRatioBips;
    parameters.delinquencyGracePeriod = inputs.delinquencyGracePeriod;
    parameters.hooksTemplate = inputs.isAccessControlHooks
      ? accessControlTemplate
      : fixedTermHooksTemplate;
    parameters.deployMarketHooksData = '';
    parameters.minimumDeposit = inputs.minimumDeposit;
    parameters.transfersDisabled = inputs.transfersDisabled;
    parameters.allowForceBuyBack = inputs.allowForceBuyBacks;
    parameters.fixedTermEndTime = inputs.isAccessControlHooks
      ? 0
      : uint32(inputs.fixedTermDuration + block.timestamp);
    parameters.allowClosureBeforeTerm = inputs.allowClosureBeforeTerm;
    parameters.allowTermReduction = inputs.allowTermReduction;
  }
}

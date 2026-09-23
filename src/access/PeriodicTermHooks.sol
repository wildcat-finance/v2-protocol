// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './PeriodicTermPolicy.sol';
import { HookedMarket } from './types/PeriodicTermHookTypes.sol';
import { PendingAprChange } from './types/PeriodicTermHookTypes.sol';
import { PendingAprChangeStorage } from './types/PeriodicTermHookTypes.sol';
import { IMarketApr } from './types/PeriodicTermHookTypes.sol';

/// @title PeriodicTermHooks
/// @notice credential policy with recurring windows for queueing withdrawals.
/// @dev closing a market removes the window restriction. APR reductions need advance notice: the
///      next window is fixed as the lender response window, and execution is available after it
///      closes until the following window begins, provided no pending withdrawals remain unpaid.
///      entry with a valid credential permanently marks a lender known on that market. the hooks
///      administrator can block deposits wherever `onDeposit` is enabled.
contract PeriodicTermHooks is PeriodicTermPolicy {
  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /// @param _administrator initial hooks administrator. this does not grant provider authority.
  /// @param args optional ABI-encoded `NameAndProviderInputs` for the name and initial providers.
  constructor(
    address _administrator,
    bytes memory args
  )
    BaseHooks(
      _administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
          .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction)
      )
    )
  {}

  function version() external pure override returns (string memory) {
    return 'PeriodicTermHooks';
  }

  /// @notice returns this template's ABI revision.
  /// @dev `version()` stays `PeriodicTermHooks` because integrations match that exact string.
  function templateVersion() external pure returns (uint256) {
    return 2;
  }

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  /// @notice returns the periodic-term configuration stored for `marketAddress`.
  /// @dev an unattached market returns the zero-value struct.
  function getHookedMarket(address marketAddress) external view returns (HookedMarket memory) {
    return _hookedMarkets[marketAddress];
  }

  /// @notice batch version of `getHookedMarket`, preserving input order.
  function getHookedMarkets(
    address[] calldata marketAddresses
  ) external view returns (HookedMarket[] memory hookedMarkets) {
    hookedMarkets = new HookedMarket[](marketAddresses.length);
    for (uint256 i = 0; i < marketAddresses.length; i++) {
      hookedMarkets[i] = _hookedMarkets[marketAddresses[i]];
    }
  }
}

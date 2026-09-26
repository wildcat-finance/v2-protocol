// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './FixedTermPolicy.sol';
import { HookedMarket } from './types/FixedTermHookTypes.sol';

/// @title FixedTermHooks
/// @notice credential policy with one maturity timestamp before which queueing is blocked.
/// @dev maturity may move earlier when configured, but never later. entry with a valid credential
///      marks a lender permanently known on that market, so losing the credential can't trap an
///      existing position after maturity. the hooks administrator can still block deposits wherever
///      `onDeposit` is enabled.
contract FixedTermHooks is FixedTermPolicy {
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
      )
    )
  {}

  function version() external pure override returns (string memory) {
    return 'FixedTermHooks';
  }

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  /// @notice returns the fixed-term configuration stored for `marketAddress`.
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

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './OpenTermPolicy.sol';
import { HookedMarket } from './types/OpenTermHookTypes.sol';

/// @title OpenTermHooks
/// @notice credential and transfer policy without maturity or periodic withdrawal windows.
/// @dev each market chooses whether deposits and transfers require credentials and whether
///      withdrawals are credential-gated. a lender that enters a market with a valid credential
///      becomes permanently known there, so losing the credential can't trap an existing position.
///      the hooks administrator can still block deposits wherever `onDeposit` is enabled.
contract OpenTermHooks is OpenTermPolicy {
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
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_QueueWithdrawal
        ),
        EmptyHooksConfig.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
      )
    )
  {}

  function version() external pure override returns (string memory) {
    return 'OpenTermHooks';
  }

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  /// @notice returns the open-term configuration stored for `marketAddress`.
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

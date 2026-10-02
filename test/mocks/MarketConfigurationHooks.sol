// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketConfigurationHooks
//  \ ^ /   Market-configuration capture and rejection hooks.
//    V
//
//  CONFIGURATION SETUP
//  constructor(...)
//  setRejectConfiguration(...)
//
//  MARKET CONFIGURATION
//  _onMarketConfigured(...)
// ═════

import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { AccessConfig } from 'src/access/BaseHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';

// ┌─ MarketConfigurationHooks ─────────────────────────────────────────────────
/// @dev check registration before market code exists. rejection must roll back the whole setup.
contract MarketConfigurationHooks is PeriodicTermHooks {
  error ConfigurationRejected();
  error MarketAlreadyDeployed();

  bool public rejectConfiguration;
  address public configuredMarket;
  uint128 public configuredMinimum;
  HooksConfig public configuredFlags;

  // ░░▒▒▓▓██ [ CONFIGURATION SETUP ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address administrator) PeriodicTermHooks(administrator, '') { }

  // ┌─ setRejectConfiguration ─────
  function setRejectConfiguration(bool reject) external {
    rejectConfiguration = reject;
  }

  // ░░▒▒▓▓██ [ MARKET CONFIGURATION ] ─────────────────────────────────────────

  // ┌─ _onMarketConfigured ─────
  function _onMarketConfigured(
    address,
    address market,
    DeployMarketInputs calldata,
    bytes calldata,
    HooksConfig effective
  )
    internal
    override
  {
    if (market.code.length != 0) revert MarketAlreadyDeployed();
    AccessConfig memory access = _requireHookedMarket(market);
    configuredMarket = market;
    configuredMinimum = access.minimumDeposit;
    configuredFlags = effective;
    if (rejectConfiguration) revert ConfigurationRejected();
  }
}

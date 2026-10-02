// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // TransferFeatureHooks
// ║  ██▀▀     ▀▀██   Transfer-feature integrations across term-policy families.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  OPEN TRANSFER POLICY
// ║  _authorizeFeatureManagement(...)
// ║  _onMarketConfigured(...)
// ║  _checkTransfer(...)
// ║  _featureTransferRecipientAllowed(...)
// ║  getHookedMarket(...)
// ║  getHookedMarkets(...)
// ║
// ║  OPEN TRANSFER HOOKS
// ║  constructor(...)
// ║  version()
// ║
// ║  FIXED TRANSFER POLICY
// ║  _authorizeFeatureManagement(...)
// ║  _onMarketConfigured(...)
// ║  _checkTransfer(...)
// ║  _featureTransferRecipientAllowed(...)
// ║  getHookedMarket(...)
// ║  getHookedMarkets(...)
// ║
// ║  FIXED TRANSFER HOOKS
// ║  constructor(...)
// ║  version()
// ║
// ║  PERIODIC TRANSFER POLICY
// ║  _authorizeFeatureManagement(...)
// ║  _onMarketConfigured(...)
// ║  _checkTransfer(...)
// ║  _featureTransferRecipientAllowed(...)
// ║  getHookedMarket(...)
// ║  getHookedMarkets(...)
// ║
// ║  PERIODIC TRANSFER HOOKS
// ║  constructor(...)
// ║  version()
// ╚═════

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { OpenTermPolicy } from 'src/access/OpenTermPolicy.sol';
import { FixedTermPolicy } from 'src/access/FixedTermPolicy.sol';
import { PeriodicTermPolicy } from 'src/access/PeriodicTermPolicy.sol';
import { HookedMarket as OpenMarket } from 'src/access/types/OpenTermHookTypes.sol';
import { HookedMarket as FixedMarket } from 'src/access/types/FixedTermHookTypes.sol';
import { HookedMarket as PeriodicMarket } from 'src/access/types/PeriodicTermHookTypes.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { TransferFeatures } from './TransferFeaturePolicies.sol';

// ┌─ OpenTransferPolicy ───────────────────────────────────────────────────────
/// @dev test-only open assembly. each callback selects its feature helpers explicitly.
abstract contract OpenTransferPolicy is OpenTermPolicy, TransferFeatures {
  // ░░▒▒▓▓██ [ OPEN TRANSFER POLICY ] ─────────────────────────────────────────

  // ┌─ _authorizeFeatureManagement ─────
  function _authorizeFeatureManagement(address market) internal view override onlyAdministrator {
    _requireHookedMarket(market);
  }

  // ┌─ _onMarketConfigured ─────
  function _onMarketConfigured(
    address,
    address market,
    DeployMarketInputs calldata parameters,
    bytes calldata,
    HooksConfig
  )
    internal
    virtual
    override
  {
    // the initial scale factor is RAY. use maxTotalSupply as this probe's initial scaled limit.
    // the market isn't deployed yet; all inputs come from the creation callback.
    _setTransferAmountLimit(market, parameters.maxTotalSupply);
  }

  // ┌─ _checkTransfer ─────
  function _checkTransfer(
    address,
    address,
    address to,
    uint256 scaledAmount,
    MarketState calldata,
    bytes calldata
  )
    internal
    virtual
    override
  {
    _applyTransferFeatures(msg.sender, to, scaledAmount);
  }

  // ┌─ _featureTransferRecipientAllowed ─────
  function _featureTransferRecipientAllowed(
    address market,
    address recipient
  )
    internal
    view
    virtual
    override
    returns (bool)
  {
    return _recipientAllowed(market, recipient);
  }

  // ┌─ getHookedMarket ─────
  function getHookedMarket(address market) external view returns (OpenMarket memory) {
    return _hookedMarkets[market];
  }

  // ┌─ getHookedMarkets ─────
  function getHookedMarkets(address[] calldata markets) external view returns (OpenMarket[] memory result) {
    result = new OpenMarket[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      result[i] = _hookedMarkets[markets[i]];
    }
  }
}

// ┌─ OpenTransferHooks ────────────────────────────────────────────────────────
contract OpenTransferHooks is OpenTransferPolicy {
  // ░░▒▒▓▓██ [ OPEN TRANSFER HOOKS ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit)
          .setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_QueueWithdrawal),
        EmptyHooksConfig.setFlag(Bit_Enabled_Transfer).setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
      )
    )
  { }

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'OpenTransferHooks';
  }
}

// ┌─ FixedTransferPolicy ──────────────────────────────────────────────────────
/// @dev test-only fixed assembly. each callback selects its feature helpers explicitly.
abstract contract FixedTransferPolicy is FixedTermPolicy, TransferFeatures {
  // ░░▒▒▓▓██ [ FIXED TRANSFER POLICY ] ────────────────────────────────────────

  // ┌─ _authorizeFeatureManagement ─────
  function _authorizeFeatureManagement(address market) internal view override onlyAdministrator {
    _requireHookedMarket(market);
  }

  // ┌─ _onMarketConfigured ─────
  function _onMarketConfigured(
    address,
    address market,
    DeployMarketInputs calldata parameters,
    bytes calldata,
    HooksConfig
  )
    internal
    virtual
    override
  {
    // the initial scale factor is RAY. use maxTotalSupply as this probe's initial scaled limit.
    // the market isn't deployed yet; all inputs come from the creation callback.
    _setTransferAmountLimit(market, parameters.maxTotalSupply);
  }

  // ┌─ _checkTransfer ─────
  function _checkTransfer(
    address,
    address,
    address to,
    uint256 scaledAmount,
    MarketState calldata,
    bytes calldata
  )
    internal
    virtual
    override
  {
    _applyTransferFeatures(msg.sender, to, scaledAmount);
  }

  // ┌─ _featureTransferRecipientAllowed ─────
  function _featureTransferRecipientAllowed(
    address market,
    address recipient
  )
    internal
    view
    virtual
    override
    returns (bool)
  {
    return _recipientAllowed(market, recipient);
  }

  // ┌─ getHookedMarket ─────
  function getHookedMarket(address market) external view returns (FixedMarket memory) {
    return _hookedMarkets[market];
  }

  // ┌─ getHookedMarkets ─────
  function getHookedMarkets(address[] calldata markets) external view returns (FixedMarket[] memory result) {
    result = new FixedMarket[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      result[i] = _hookedMarkets[markets[i]];
    }
  }
}

// ┌─ FixedTransferHooks ───────────────────────────────────────────────────────
contract FixedTransferHooks is FixedTransferPolicy {
  // ░░▒▒▓▓██ [ FIXED TRANSFER HOOKS ] ─────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig.setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
      )
    )
  { }

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'FixedTransferHooks';
  }
}

// ┌─ PeriodicTransferPolicy ───────────────────────────────────────────────────
/// @dev test-only periodic assembly. each callback selects its feature helpers explicitly.
abstract contract PeriodicTransferPolicy is PeriodicTermPolicy, TransferFeatures {
  // ░░▒▒▓▓██ [ PERIODIC TRANSFER POLICY ] ─────────────────────────────────────

  // ┌─ _authorizeFeatureManagement ─────
  function _authorizeFeatureManagement(address market) internal view override onlyAdministrator {
    _requireHookedMarket(market);
  }

  // ┌─ _onMarketConfigured ─────
  function _onMarketConfigured(
    address,
    address market,
    DeployMarketInputs calldata parameters,
    bytes calldata,
    HooksConfig
  )
    internal
    virtual
    override
  {
    // the initial scale factor is RAY. use maxTotalSupply as this probe's initial scaled limit.
    // the market isn't deployed yet; all inputs come from the creation callback.
    _setTransferAmountLimit(market, parameters.maxTotalSupply);
  }

  // ┌─ _checkTransfer ─────
  function _checkTransfer(
    address,
    address,
    address to,
    uint256 scaledAmount,
    MarketState calldata,
    bytes calldata
  )
    internal
    virtual
    override
  {
    _applyTransferFeatures(msg.sender, to, scaledAmount);
  }

  // ┌─ _featureTransferRecipientAllowed ─────
  function _featureTransferRecipientAllowed(
    address market,
    address recipient
  )
    internal
    view
    virtual
    override
    returns (bool)
  {
    return _recipientAllowed(market, recipient);
  }

  // ┌─ getHookedMarket ─────
  function getHookedMarket(address market) external view returns (PeriodicMarket memory) {
    return _hookedMarkets[market];
  }

  // ┌─ getHookedMarkets ─────
  function getHookedMarkets(address[] calldata markets) external view returns (PeriodicMarket[] memory result) {
    result = new PeriodicMarket[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      result[i] = _hookedMarkets[markets[i]];
    }
  }
}

// ┌─ PeriodicTransferHooks ────────────────────────────────────────────────────
contract PeriodicTransferHooks is PeriodicTransferPolicy {
  // ░░▒▒▓▓██ [ PERIODIC TRANSFER HOOKS ] ──────────────────────────────────────

  // ┌─ constructor ─────
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig.setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
          .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction)
      )
    )
  { }

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'PeriodicTransferHooks';
  }
}

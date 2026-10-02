// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketMocks
// ║  ██▀▀     ▀▀██   Protocol-fee read probes and market APR callback responses.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  FEE PROBE SETUP
// ║  version()
// ║  config()
// ║  _onCreateMarket(...)
// ║
// ║  DEPOSIT FEE PROBE
// ║  onDeposit(...)
// ║
// ║  FEE PROBE PASSIVE CALLBACKS
// ║  onTransfer(...)
// ║  onQueueWithdrawal(...)
// ║  onExecuteWithdrawal(...)
// ║  onBorrow(...)
// ║  onRepay(...)
// ║  onCloseMarket(...)
// ║  onSetMaxTotalSupply(...)
// ║  onSetProtocolFeeBips(...)
// ║  onNukeFromOrbit(...)
// ║  onSetAnnualInterestAndReserveRatioBips(...)
// ║
// ║  APR HOOK SETUP
// ║  version()
// ║  config()
// ║  _onCreateMarket(...)
// ║
// ║  APR UPDATES
// ║  setAprAndReserveRatioReturn(...)
// ║  onSetAnnualInterestAndReserveRatioBips(...)
// ║
// ║  PENDING APR REDUCTIONS
// ║  setPendingAnnualInterestBipsReduction(...)
// ║  executePendingAnnualInterestBipsReduction(...)
// ║
// ║  APR HOOK PASSIVE CALLBACKS
// ║  onDeposit(...)
// ║  onTransfer(...)
// ║  onQueueWithdrawal(...)
// ║  onExecuteWithdrawal(...)
// ║  onBorrow(...)
// ║  onRepay(...)
// ║  onCloseMarket(...)
// ║  onSetMaxTotalSupply(...)
// ║  onSetProtocolFeeBips(...)
// ║  onNukeFromOrbit(...)
// ╚═════

import { IHooks } from 'src/access/IHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { Bit_Enabled_Deposit, EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig, encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';

// ┌─ ProtocolFeeReadOnDepositHooks ────────────────────────────────────────────
contract ProtocolFeeReadOnDepositHooks is IHooks {
  bool public protocolFeeReadSucceeded;
  uint128 public protocolFeeReadValue;
  bytes4 public protocolFeeReadRevertSelector;

  // ░░▒▒▓▓██ [ FEE PROBE SETUP ] ──────────────────────────────────────────────

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'ProtocolFeeReadOnDepositHooks';
  }

  // ┌─ config ─────
  function config() public pure override returns (HooksDeploymentConfig) {
    return encodeHooksDeploymentConfig(EmptyHooksConfig.setFlag(Bit_Enabled_Deposit), EmptyHooksConfig);
  }

  // ┌─ _onCreateMarket ─────
  function _onCreateMarket(
    address,
    address,
    DeployMarketInputs calldata parameters,
    bytes calldata
  )
    internal
    pure
    override
    returns (HooksConfig)
  {
    return parameters.hooks.mergeFlags(config());
  }

  // ░░▒▒▓▓██ [ DEPOSIT FEE PROBE ] ────────────────────────────────────────────

  // ┌─ onDeposit ─────
  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override {
    (bool success, bytes memory data) = msg.sender.staticcall(abi.encodeWithSignature('withdrawableProtocolFees()'));
    protocolFeeReadSucceeded = success;
    if (success && data.length >= 32) {
      protocolFeeReadValue = abi.decode(data, (uint128));
    } else if (data.length >= 4) {
      bytes4 selector;
      assembly {
        selector := mload(add(data, 0x20))
      }
      protocolFeeReadRevertSelector = selector;
    }
  }

  // ░░▒▒▓▓██ [ FEE PROBE PASSIVE CALLBACKS ] ──────────────────────────────────

  // ┌─ onTransfer ─────
  function onTransfer(address, address, address, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onQueueWithdrawal ─────
  function onQueueWithdrawal(address, uint32, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onExecuteWithdrawal ─────
  function onExecuteWithdrawal(address, uint32, uint128, MarketState calldata, bytes calldata) external override { }

  // ┌─ onBorrow ─────
  function onBorrow(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onRepay ─────
  function onRepay(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onCloseMarket ─────
  function onCloseMarket(MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetMaxTotalSupply ─────
  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetProtocolFeeBips ─────
  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override { }

  // ┌─ onNukeFromOrbit ─────
  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  )
    external
    pure
    override
    returns (uint16, uint16)
  {
    return (annualInterestBips, reserveRatioBips);
  }
}

// ┌─ MarketConfigHooks ────────────────────────────────────────────────────────
contract MarketConfigHooks is IHooks {
  bool private _replaceAprAndReserveRatio;
  uint16 private _annualInterestBips;
  uint16 private _reserveRatioBips;

  uint16 public pendingAnnualInterestBipsReduction;
  uint16 public lastIntermediateAnnualInterestBips;
  uint16 public lastIntermediateReserveRatioBips;

  // ░░▒▒▓▓██ [ APR HOOK SETUP ] ───────────────────────────────────────────────

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'MarketConfigHooks';
  }

  // ┌─ config ─────
  function config() public pure override returns (HooksDeploymentConfig) {
    return encodeHooksDeploymentConfig(
      EmptyHooksConfig,
      EmptyHooksConfig.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
        .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction)
    );
  }

  // ┌─ _onCreateMarket ─────
  function _onCreateMarket(
    address,
    address,
    DeployMarketInputs calldata parameters,
    bytes calldata
  )
    internal
    pure
    override
    returns (HooksConfig)
  {
    return parameters.hooks.mergeFlags(config());
  }

  // ░░▒▒▓▓██ [ APR UPDATES ] ──────────────────────────────────────────────────

  // ┌─ setAprAndReserveRatioReturn ─────
  function setAprAndReserveRatioReturn(uint16 annualInterestBips, uint16 reserveRatioBips) external {
    _replaceAprAndReserveRatio = true;
    _annualInterestBips = annualInterestBips;
    _reserveRatioBips = reserveRatioBips;
  }

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  )
    external
    view
    override
    returns (uint16, uint16)
  {
    if (_replaceAprAndReserveRatio) return (_annualInterestBips, _reserveRatioBips);
    return (annualInterestBips, reserveRatioBips);
  }

  // ░░▒▒▓▓██ [ PENDING APR REDUCTIONS ] ───────────────────────────────────────

  // ┌─ setPendingAnnualInterestBipsReduction ─────
  function setPendingAnnualInterestBipsReduction(uint16 annualInterestBips) external {
    pendingAnnualInterestBipsReduction = annualInterestBips;
  }

  // ┌─ executePendingAnnualInterestBipsReduction ─────
  function executePendingAnnualInterestBipsReduction(MarketState calldata intermediateState)
    external
    returns (uint16 annualInterestBips)
  {
    lastIntermediateAnnualInterestBips = intermediateState.annualInterestBips;
    lastIntermediateReserveRatioBips = intermediateState.reserveRatioBips;
    return pendingAnnualInterestBipsReduction;
  }

  // ░░▒▒▓▓██ [ APR HOOK PASSIVE CALLBACKS ] ───────────────────────────────────

  // ┌─ onDeposit ─────
  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onTransfer ─────
  function onTransfer(address, address, address, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onQueueWithdrawal ─────
  function onQueueWithdrawal(address, uint32, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onExecuteWithdrawal ─────
  function onExecuteWithdrawal(address, uint32, uint128, MarketState calldata, bytes calldata) external override { }

  // ┌─ onBorrow ─────
  function onBorrow(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onRepay ─────
  function onRepay(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onCloseMarket ─────
  function onCloseMarket(MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetMaxTotalSupply ─────
  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetProtocolFeeBips ─────
  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override { }

  // ┌─ onNukeFromOrbit ─────
  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override { }
}

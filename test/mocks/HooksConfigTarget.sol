// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HooksConfigTarget
//  \ ^ /   Exact callback-calldata recording and malformed responses.
//    V
//
//  HOOK SETUP
//  version()
//  config()
//  setShouldRevert(...)
//  _onCreateMarket(...)
//
//  LENDER CALLBACKS
//  onDeposit(...)
//  onTransfer(...)
//  onQueueWithdrawal(...)
//  onExecuteWithdrawal(...)
//
//  BORROWER CALLBACKS
//  onBorrow(...)
//  onRepay(...)
//  onCloseMarket(...)
//
//  CONFIGURATION CALLBACKS
//  onSetMaxTotalSupply(...)
//  setAnnualInterestAndReserveRatioBips(...)
//  onSetAnnualInterestAndReserveRatioBips(...)
//  onSetProtocolFeeBips(...)
//  onNukeFromOrbit(...)
//
//  CALL RECORDING
//  _recordCall()
//
//  SHORT RESPONSES
//  fallback()
// ═════

import { IHooks } from 'src/access/IHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';

// ┌─ HooksConfigTarget ────────────────────────────────────────────────────────
/// @dev record LibHooksConfig's exact calldata. deploy from the artifact so the test contract
///      doesn't embed this target's creation code alongside every hook path.
contract HooksConfigTarget is IHooks {
  error ForcedRevert();

  bytes32 public lastCalldataHash;
  uint16 public annualInterestBipsToReturn;
  uint16 public reserveRatioBipsToReturn;
  bool public shouldRevert;

  // ░░▒▒▓▓██ [ HOOK SETUP ] ───────────────────────────────────────────────────

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'test-hooks';
  }

  // ┌─ config ─────
  function config() external pure override returns (HooksDeploymentConfig) {
    return encodeHooksDeploymentConfig(EmptyHooksConfig, EmptyHooksConfig);
  }

  // ┌─ setShouldRevert ─────
  function setShouldRevert(bool value) external {
    shouldRevert = value;
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
    return parameters.hooks;
  }

  // ░░▒▒▓▓██ [ LENDER CALLBACKS ] ─────────────────────────────────────────────

  // ┌─ onDeposit ─────
  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ onTransfer ─────
  function onTransfer(address, address, address, uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ onQueueWithdrawal ─────
  function onQueueWithdrawal(address, uint32, uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ onExecuteWithdrawal ─────
  function onExecuteWithdrawal(address, uint32, uint128, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ░░▒▒▓▓██ [ BORROWER CALLBACKS ] ───────────────────────────────────────────

  // ┌─ onBorrow ─────
  function onBorrow(uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ onRepay ─────
  function onRepay(uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ onCloseMarket ─────
  function onCloseMarket(MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ░░▒▒▓▓██ [ CONFIGURATION CALLBACKS ] ──────────────────────────────────────

  // ┌─ onSetMaxTotalSupply ─────
  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ setAnnualInterestAndReserveRatioBips ─────
  function setAnnualInterestAndReserveRatioBips(uint16 annualInterestBips, uint16 reserveRatioBips) external {
    annualInterestBipsToReturn = annualInterestBips;
    reserveRatioBipsToReturn = reserveRatioBips;
  }

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  function onSetAnnualInterestAndReserveRatioBips(
    uint16,
    uint16,
    MarketState calldata,
    bytes calldata
  )
    external
    override
    returns (uint16, uint16)
  {
    _recordCall();
    return (annualInterestBipsToReturn, reserveRatioBipsToReturn);
  }

  // ┌─ onSetProtocolFeeBips ─────
  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override {
    _recordCall();
  }

  // ┌─ onNukeFromOrbit ─────
  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  // ░░▒▒▓▓██ [ CALL RECORDING ] ───────────────────────────────────────────────

  // ┌─ _recordCall ─────
  function _recordCall() private {
    if (shouldRevert) revert ForcedRevert();
    lastCalldataHash = keccak256(msg.data);
  }
}

// ┌─ HooksConfigShortReturnTarget ─────────────────────────────────────────────
contract HooksConfigShortReturnTarget {
  // ░░▒▒▓▓██ [ SHORT RESPONSES ] ──────────────────────────────────────────────

  // ┌─ fallback ─────
  fallback() external { }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // AprValidationHooks
// ║  ██▀▀     ▀▀██   Effective APR validation and callback-state capture.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  VALIDATION SETUP
// ║  constructor(...)
// ║  seedTemporaryReserve(...)
// ║
// ║  APR VALIDATION
// ║  _checkAprChange(...)
// ║  lastChange()
// ╚═════

import { AprChange } from 'src/access/BaseHooks.sol';
import { TemporaryReserveRatio } from 'src/access/MarketConstraintHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { AprValidationPolicy } from './AprValidationPolicy.sol';

// ┌─ AprValidationHooks ───────────────────────────────────────────────────────
/// @dev test-only effective-value constraint. keep the production APR strategies intact.
contract AprValidationHooks is PeriodicTermHooks, AprValidationPolicy {
  AprChange internal _lastChange;
  bytes32 public lastStateHash;
  bytes public lastData;
  uint32 public proposalTimestampAtValidation;

  // ░░▒▒▓▓██ [ VALIDATION SETUP ] ─────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address administrator) PeriodicTermHooks(administrator, '') { }

  // ┌─ seedTemporaryReserve ─────
  /// @dev seed nonzero default state so a reduction can't hide an accidental default call.
  function seedTemporaryReserve(address market, TemporaryReserveRatio calldata value) external {
    temporaryExcessReserveRatio[market] = value;
  }

  // ░░▒▒▓▓██ [ APR VALIDATION ] ───────────────────────────────────────────────

  // ┌─ _checkAprChange ─────
  function _checkAprChange(
    AprChange memory change,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    override
  {
    _validateAprChange(change);
    _lastChange = change;
    lastStateHash = keccak256(abi.encode(state));
    lastData = extraData;
    proposalTimestampAtValidation = _pendingAprChanges[change.market].proposalTimestamp;
  }

  // ┌─ lastChange ─────
  function lastChange() external view returns (AprChange memory) {
    return _lastChange;
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { AprChange } from 'src/access/BaseHooks.sol';
import { TemporaryReserveRatio } from 'src/access/MarketConstraintHooks.sol';
import { PeriodicTermHooks } from 'src/access/PeriodicTermHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';

/// @dev test-only effective-value constraint. keep the production APR strategies intact.
contract AprValidationHooks is PeriodicTermHooks {
  error AprBelowFloor(uint16 actual);
  error ReserveAboveCeiling(uint16 actual);

  uint16 public minimumApr;
  uint16 public maximumReserve = 10_000;
  AprChange internal _lastChange;
  bytes32 public lastStateHash;
  bytes public lastData;
  uint32 public proposalTimestampAtValidation;

  constructor(address administrator) PeriodicTermHooks(administrator, '') {}

  function setValidationBounds(uint16 aprFloor, uint16 reserveCeiling) external {
    minimumApr = aprFloor;
    maximumReserve = reserveCeiling;
  }

  /// @dev seed nonzero default state so a reduction can't hide an accidental default call.
  function seedTemporaryReserve(address market, TemporaryReserveRatio calldata value) external {
    temporaryExcessReserveRatio[market] = value;
  }

  function lastChange() external view returns (AprChange memory) {
    return _lastChange;
  }

  function _checkAprChange(
    AprChange memory change,
    MarketState calldata state,
    bytes calldata extraData
  ) internal override {
    if (change.effectiveApr < minimumApr) revert AprBelowFloor(change.effectiveApr);
    if (change.effectiveReserve > maximumReserve)
      revert ReserveAboveCeiling(change.effectiveReserve);
    _lastChange = change;
    lastStateHash = keccak256(abi.encode(state));
    lastData = extraData;
    proposalTimestampAtValidation = _pendingAprChanges[change.market].proposalTimestamp;
  }
}

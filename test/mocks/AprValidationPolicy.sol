// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // AprValidationPolicy
//  \ ^ /   Shared APR floor and reserve ceiling test constraints.
//    V
//
//  APR BOUNDS
//  setValidationBounds(...)
//  _validateAprChange(...)
// ═════

import { AprChange } from 'src/access/BaseHooks.sol';

// ┌─ AprValidationPolicy ──────────────────────────────────────────────────────
/// @dev shared test validator. assemblies decide who may configure it and when to call it.
abstract contract AprValidationPolicy {
  error AprBelowFloor(uint16 actual);
  error ReserveAboveCeiling(uint16 actual);

  uint16 public minimumApr;
  uint16 public maximumReserve = 10_000;

  // ░░▒▒▓▓██ [ APR BOUNDS ] ───────────────────────────────────────────────────

  // ┌─ setValidationBounds ─────
  function setValidationBounds(uint16 aprFloor, uint16 reserveCeiling) public virtual {
    minimumApr = aprFloor;
    maximumReserve = reserveCeiling;
  }

  // ┌─ _validateAprChange ─────
  function _validateAprChange(AprChange memory change) internal view {
    if (change.effectiveApr < minimumApr) revert AprBelowFloor(change.effectiveApr);
    if (change.effectiveReserve > maximumReserve) {
      revert ReserveAboveCeiling(change.effectiveReserve);
    }
  }
}

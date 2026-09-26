// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { AprChange } from 'src/access/BaseHooks.sol';

/// @dev shared test validator. assemblies decide who may configure it and when to call it.
abstract contract AprValidationPolicy {
  error AprBelowFloor(uint16 actual);
  error ReserveAboveCeiling(uint16 actual);

  uint16 public minimumApr;
  uint16 public maximumReserve = 10_000;

  function setValidationBounds(uint16 aprFloor, uint16 reserveCeiling) public virtual {
    minimumApr = aprFloor;
    maximumReserve = reserveCeiling;
  }

  function _validateAprChange(AprChange memory change) internal view {
    if (change.effectiveApr < minimumApr) revert AprBelowFloor(change.effectiveApr);
    if (change.effectiveReserve > maximumReserve)
      revert ReserveAboveCeiling(change.effectiveReserve);
  }
}

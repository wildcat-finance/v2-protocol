// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { AprValidationPolicy } from './AprValidationPolicy.sol';

/// @dev test-only replacement calculation. term routing and APR bounds belong to the assembly.
abstract contract AprReplacementPolicy is AprValidationPolicy {
  event AprDefaultSelected(
    address indexed market,
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  );

  mapping(address => uint16) public lastSelectedApr;

  function _selectAprUpdate(
    uint16 annualInterestBips
  ) internal returns (uint16 effectiveApr, uint16 effectiveReserve) {
    // deliberately differs from the temporary-reserve calculation. don't call that default first.
    lastSelectedApr[msg.sender] = annualInterestBips;
    emit AprDefaultSelected(msg.sender, annualInterestBips, 3_333);
    return (annualInterestBips, 3_333);
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

contract PeriodicAprMarketMock {
  uint256 public annualInterestBips;

  constructor(uint256 initialAnnualInterestBips) {
    annualInterestBips = initialAnnualInterestBips;
  }

  function setAnnualInterestBips(uint256 newAnnualInterestBips) external {
    annualInterestBips = newAnnualInterestBips;
  }
}

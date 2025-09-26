// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

contract MockChainalysisContract {
  mapping(address => bool) public isSanctioned;

  function sanction(address account) external {
    isSanctioned[account] = true;
  }

  function unsanction(address account) external {
    isSanctioned[account] = false;
  }
}
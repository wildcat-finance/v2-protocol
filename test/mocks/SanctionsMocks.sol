// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

contract SanctionsListMock {
  mapping(address account => bool sanctioned) public isSanctioned;

  function sanction(address account) external {
    isSanctioned[account] = true;
  }

  function unsanction(address account) external {
    isSanctioned[account] = false;
  }
}

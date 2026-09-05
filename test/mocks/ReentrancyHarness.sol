// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ReentrancyGuard } from 'src/ReentrancyGuard.sol';

contract ReentrancyHarness is ReentrancyGuard {
  uint256 public index;

  function increment() external nonReentrant returns (uint256 previous) {
    previous = index++;
  }

  function readIndex() external view nonReentrantView returns (uint256) {
    return index;
  }

  function callIncrement() external returns (uint256) {
    return this.increment();
  }

  function callRead() external view returns (uint256) {
    return this.readIndex();
  }

  function reenterStateful() external nonReentrant returns (uint256) {
    return this.increment();
  }

  function reenterView() external nonReentrant returns (uint256) {
    return this.readIndex();
  }
}

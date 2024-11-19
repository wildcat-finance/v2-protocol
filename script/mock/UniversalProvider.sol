// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'src/access/IRoleProvider.sol';

contract UniversalProvider is IRoleProvider {
  bool public constant override isPullProvider = true;

  function getCredential(address) external view returns (uint32 timestamp) {
    return uint32(block.timestamp);
  }

  function validateCredential(
    address,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return uint32(block.timestamp);
  }
}

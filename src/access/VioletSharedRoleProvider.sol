// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import 'ethereum-access-token/AccessTokenConsumer.sol';
// import '

contract VioletRoleProviderForBorrower is AccessTokenConsumer {
  address public immutable controller;

  string public name = "Shared Wildcat Role Provider - Violet";

  function isPullProvider() external pure returns (bool) {
    return false;
  }

  constructor(
    address accessTokenVerifier,
    address wildcatMarketController
  ) AccessTokenConsumer(accessTokenVerifier) {
    controller = wildcatMarketController;
  }

  function verifyRole(uint8 v, bytes32 r, bytes32 s) external requiresAuth {
    
  }
}

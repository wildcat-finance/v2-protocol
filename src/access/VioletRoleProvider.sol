// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import 'ethereum-access-token/AccessTokenConsumer.sol';

contract VioletRoleProvider is AccessTokenConsumer {
  function isPullProvider() external pure returns (bool) {
    return false;
  }

  constructor(
    address accessTokenVerifier
  ) AccessTokenConsumer(accessTokenVerifier) {
  }

  /**
   * @dev Function used by a hooks contract passing along data
   *      (Violet access token) to avoid an extra transaction.
   */
  function validateCredential(address account) external returns (bytes4) {
    // @todo - use assembly, update library to be able to provide
    // signature, sender and parameters pointers manually
    // Signature is 65 bytes + 4 bytes for function selector and 32 bytes for account
    // Signature packed into the end of the calldata
    require(msg.data.length >= 0x65);
    // _validateAccessToken(signaturePointer = 0x24, parametersPointer = 0x00, parametersLength = 0x00, caller = account);
    return VioletRoleProvider.validateCredential.selector;
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IRoleProvider {
  function canPull() external view returns (bool);

  function getCredential(address account) external view returns (uint32 timestamp);

  /// @dev The extra bytes are packed into the end of the calldata
  function validateCredential(address account) external returns (bytes4 magicValue);
}

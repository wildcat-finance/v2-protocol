// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/IRoleProvider.sol';

contract MockRoleProvider is IRoleProvider {
  bool public override isPullProvider;

  mapping(address => uint32) public override getCredential;
  mapping(bytes32 => uint32) public validateCredentialTimestamp;

  function setIsPullProvider(bool value) external {
    isPullProvider = value;
  }

  function setCredential(address account, uint32 timestamp) external {
    getCredential[account] = timestamp;
  }

  function setValidateCredentialTimestamp(bytes32 dataHash, uint32 timestamp) external {
    validateCredentialTimestamp[dataHash] = timestamp;
  }

  function validateCredential(
    address account,
    bytes calldata data
  ) external override returns (uint32 timestamp) {
    bytes32 dataHash = keccak256(data);
    timestamp = validateCredentialTimestamp[dataHash];
  }
}

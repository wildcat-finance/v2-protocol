// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'src/access/IRoleProvider.sol';

contract MockRoleProvider is IRoleProvider {
  error BadCredential();

  bool public callShouldRevert;
  bool public override isPullProvider;
  bool public callShouldReturnCorruptedData;

  mapping(address => uint32) public credentialsByAccount;
  mapping(bytes32 => uint32) public credentialsByHash;

  function setIsPullProvider(bool value) external {
    isPullProvider = value;
  }

  function setCallShouldRevert(bool value) external {
    callShouldRevert = value;
  }

  function setCallShouldReturnCorruptedData(bool value) external {
    callShouldReturnCorruptedData = value;
  }

  function setCredential(address account, uint32 timestamp) external {
    credentialsByAccount[account] = timestamp;
  }

  function approveCredentialData(bytes32 dataHash, uint32 timestamp) external {
    credentialsByHash[dataHash] = timestamp;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    if (callShouldRevert) revert BadCredential();
    if (callShouldReturnCorruptedData) {
      assembly {
        return(0, 0)
      }
    }
    return credentialsByAccount[account];
  }

  function validateCredential(
    address account,
    bytes calldata data
  ) external override returns (uint32 timestamp) {
    if (callShouldRevert) revert BadCredential();
    if (callShouldReturnCorruptedData) {
      assembly {
        return(0, 0)
      }
    }
    bytes32 dataHash = keccak256(data);
    timestamp = credentialsByHash[dataHash];
  }
}

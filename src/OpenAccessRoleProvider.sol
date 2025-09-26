// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IChainalysis {
  function isSanctioned(address) external view returns (bool);
}

contract OpenAccessRoleProvider {
  IChainalysis public immutable chainalysisOracle;

  constructor(address _chainalysisOracle) {
    chainalysisOracle = IChainalysis(_chainalysisOracle);
  }

  function isPullProvider() public pure returns (bool) {
    return true;
  }

  // return 0 if sanctioned
  function getCredential(address account) public view returns (uint32) {
    if (chainalysisOracle.isSanctioned(account)) {
      return 0;
    } else {
      return uint32(block.timestamp);
    }
  }

  function validateCredential(address account, bytes calldata) public view returns (uint32) {
    return getCredential(account);
  }
}

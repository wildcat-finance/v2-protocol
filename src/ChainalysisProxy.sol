// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'solady/auth/Ownable.sol';

contract ChainalysisProxy is Ownable {
  address public sanctionsRegistry;

  function setSanctionsRegistry(address _sanctionsRegistry) external onlyOwner {
    sanctionsRegistry = _sanctionsRegistry;
  }

  constructor() {
    _initializeOwner(msg.sender);
  }

  function isSanctioned(address account) external view returns (bool) {
    if (sanctionsRegistry == address(0)) {
      return false;
    }
    return ChainalysisProxy(sanctionsRegistry).isSanctioned(account);
  }
}

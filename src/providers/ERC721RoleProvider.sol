// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';

interface IERC721 {
  function balanceOf(address owner) external view returns (uint256);
}

contract ERC721RoleProvider is IRoleProvider {
  address public immutable token;

  constructor(address _token) {
    token = _token;
  }

  function isPullProvider() external pure override returns (bool) {
    return true;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function _credentialTimestamp(address account) internal view returns (uint32) {
    if (IERC721(token).balanceOf(account) > 0) {
      return uint32(block.timestamp);
    }
    return 0;
  }
}

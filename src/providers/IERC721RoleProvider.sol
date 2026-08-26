// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';

interface IERC721RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC721();

  function token() external view returns (address);
}

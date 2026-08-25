// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../access/IRoleProvider.sol';

interface IERC1155RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC1155();

  function token() external view returns (address);

  function tokenId() external view returns (uint256);
}

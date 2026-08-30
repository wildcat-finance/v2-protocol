// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';

/// @notice pull provider that accepts accounts holding any token from an ERC721 collection.
interface IERC721RoleProvider is IRoleProvider {
  /// @dev the token address has no code.
  error InvalidTokenAddress();
  /// @dev the token failed the deployment-time ERC165 or ERC721 checks.
  error InvalidERC721();

  /// @notice collection queried for balances.
  function token() external view returns (address);
}

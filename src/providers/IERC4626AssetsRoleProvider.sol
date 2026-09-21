// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../access/IRoleProvider.sol';

/// @notice pull provider that accepts accounts whose ERC4626 shares represent enough assets.
interface IERC4626AssetsRoleProvider is IRoleProvider {
  /// @dev the vault address has no code.
  error InvalidVaultAddress();
  /// @dev the qualifying underlying-asset value is zero.
  error InvalidMinimumAssets();

  /// @notice vault queried for share balances and asset conversion.
  function vault() external view returns (address);

  /// @notice qualifying value in underlying-asset base units.
  function minAssets() external view returns (uint256);
}

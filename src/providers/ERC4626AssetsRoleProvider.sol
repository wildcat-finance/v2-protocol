// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import { IERC4626Assets } from './TokenInterfaces.sol';

/// @notice Grants credentials while an account's vault shares represent at least `minAssets`.
/// @dev `minAssets` uses base units of the ERC4626 underlying asset.
contract ERC4626AssetsRoleProvider is IRoleProvider {
  error InvalidVaultAddress();
  error InvalidMinimumAssets();

  address public immutable vault;
  uint256 public immutable minAssets;

  constructor(address vault_, uint256 minAssets_) {
    if (vault_.code.length == 0) revert InvalidVaultAddress();
    if (minAssets_ == 0) revert InvalidMinimumAssets();
    vault = vault_;
    minAssets = minAssets_;
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
    uint256 shares = IERC4626Assets(vault).balanceOf(account);
    if (shares == 0) return 0;
    uint256 assets = IERC4626Assets(vault).convertToAssets(shares);
    if (assets >= minAssets) {
      return uint32(block.timestamp);
    }
    return 0;
  }
}

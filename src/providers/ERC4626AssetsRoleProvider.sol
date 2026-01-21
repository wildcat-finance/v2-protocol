// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';

interface IERC4626 {
  function balanceOf(address account) external view returns (uint256);
  function convertToAssets(uint256 shares) external view returns (uint256);
}

/// @notice ERC4626 role provider; gates on convertToAssets(balanceOf(lender)) >= minAssets.
/// @dev minAssets is in base units of the ERC4626 underlying asset.
contract ERC4626AssetsRoleProvider is IRoleProvider {
  error InvalidVaultAddress();

  address public immutable vault;
  uint256 public immutable minAssets;

  constructor(address _vault, uint256 _minAssets) {
    if (_vault.code.length == 0) revert InvalidVaultAddress();
    vault = _vault;
    minAssets = _minAssets;
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
    uint256 shares = IERC4626(vault).balanceOf(account);
    if (shares == 0) return 0;
    uint256 assets = IERC4626(vault).convertToAssets(shares);
    if (assets >= minAssets) {
      return uint32(block.timestamp);
    }
    return 0;
  }
}

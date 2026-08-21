// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../libraries/SafeCastLib.sol';
import './IERC4626AssetsRoleProvider.sol';
import { IERC4626Assets, TokenQueryLib } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

/// @notice Grants credentials while an account's vault shares represent at least `minAssets`.
/// @dev `minAssets` uses base units of the ERC4626 underlying asset.
contract ERC4626AssetsRoleProvider is IERC4626AssetsRoleProvider {
  bool public constant override isPullProvider = true;

  address public immutable override vault;
  uint256 public immutable override minAssets;

  constructor(address vault_, uint256 minAssets_) {
    if (vault_.code.length == 0) revert InvalidVaultAddress();
    if (minAssets_ == 0) revert InvalidMinimumAssets();
    vault = vault_;
    minAssets = minAssets_;
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
    uint256 shares = TokenQueryLib.readWordOrRevert(
      vault,
      IERC4626Assets.balanceOf.selector,
      uint160(account)
    );
    if (shares == 0) return 0;
    uint256 assets = TokenQueryLib.readWordOrRevert(
      vault,
      IERC4626Assets.convertToAssets.selector,
      shares
    );
    if (assets >= minAssets) {
      return block.timestamp.toUint32();
    }
    return 0;
  }
}

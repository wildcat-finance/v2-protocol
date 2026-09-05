// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../libraries/SafeCastLib.sol';
import './IERC4626AssetsRoleProvider.sol';
import { IERC4626Assets } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

/// @notice grants credentials while an account's ERC4626 shares convert to at least `minAssets`.
/// @dev the immutable threshold uses underlying-asset base units. this trusts the vault's balance
///      and conversion answers; it does not check redeemability, liquidity, fees, or holding
///      history.
contract ERC4626AssetsRoleProvider is IERC4626AssetsRoleProvider {
  bool public constant override isPullProvider = true;

  address public immutable override vault;
  uint256 public immutable override minAssets;

  /// @param vault_ contract queried for share balances and asset conversion.
  /// @param minAssets_ nonzero qualifying value in underlying-asset base units.
  constructor(address vault_, uint256 minAssets_) {
    if (vault_.code.length == 0) revert InvalidVaultAddress();
    if (minAssets_ == 0) revert InvalidMinimumAssets();
    vault = vault_;
    minAssets = minAssets_;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  /// @notice runs the live share-value check for `account`; caller data is ignored.
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
      return block.timestamp.toUint32();
    }
    return 0;
  }
}

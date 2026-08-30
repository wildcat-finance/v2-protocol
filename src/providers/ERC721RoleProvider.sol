// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../libraries/SafeCastLib.sol';
import './IERC721RoleProvider.sol';
import { IERC165SupportsInterface, IERC721BalanceOf } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

/// @notice grants credentials while an account holds any token from one ERC721 collection.
/// @dev the collection is immutable and no specific token ID is required. `skipInterfaceCheck`
///      skips deployment-time ERC165 and ERC721 checks; it can't repair an incompatible
///      `balanceOf`.
contract ERC721RoleProvider is IERC721RoleProvider {
  bool public constant override isPullProvider = true;

  bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant INVALID_INTERFACE_ID = 0xffffffff;

  address public immutable override token;

  /// @param token_ collection queried for balances.
  /// @param skipInterfaceCheck whether to skip ERC165 and ERC721 checks during deployment.
  constructor(address token_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (
      !skipInterfaceCheck &&
      (!_supportsERC165(token_) || !_supportsInterface(token_, ERC721_INTERFACE_ID))
    ) {
      revert InvalidERC721();
    }
    token = token_;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  /// @notice runs the live collection-balance check for `account`; caller data is ignored.
  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function _credentialTimestamp(address account) internal view returns (uint32) {
    if (IERC721BalanceOf(token).balanceOf(account) > 0) {
      return block.timestamp.toUint32();
    }
    return 0;
  }

  function _supportsERC165(address target) internal view returns (bool) {
    return
      _supportsInterface(target, ERC165_INTERFACE_ID) &&
      !_supportsInterface(target, INVALID_INTERFACE_ID);
  }

  function _supportsInterface(
    address target,
    bytes4 interfaceId
  ) internal view returns (bool) {
    try IERC165SupportsInterface(target).supportsInterface(interfaceId) returns (bool supported) {
      return supported;
    } catch {
      return false;
    }
  }
}

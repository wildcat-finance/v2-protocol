// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import { IERC165SupportsInterface, IERC721BalanceOf } from './TokenInterfaces.sol';

/// @notice Grants credentials while an account holds a token from an ERC721 collection.
/// @dev Deploy with `skipInterfaceCheck` for collections that do not implement ERC165.
contract ERC721RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC721();

  bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant INVALID_INTERFACE_ID = 0xffffffff;

  address public immutable token;

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
    if (IERC721BalanceOf(token).balanceOf(account) > 0) {
      return uint32(block.timestamp);
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

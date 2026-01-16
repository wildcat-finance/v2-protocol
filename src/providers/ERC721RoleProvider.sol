// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';

interface IERC721 {
  function balanceOf(address owner) external view returns (uint256);
}

interface IERC165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

contract ERC721RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC721();

  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;

  address public immutable token;

  constructor(address _token, bool skipInterfaceCheck) {
    if (_token.code.length == 0) revert InvalidTokenAddress();
    if (!skipInterfaceCheck && !_supportsInterface(_token, ERC721_INTERFACE_ID)) {
      revert InvalidERC721();
    }
    token = _token;
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
    if (IERC721(token).balanceOf(account) > 0) {
      return uint32(block.timestamp);
    }
    return 0;
  }

  function _supportsInterface(
    address target,
    bytes4 interfaceId
  ) internal view returns (bool) {
    try IERC165(target).supportsInterface(interfaceId) returns (bool supported) {
      return supported;
    } catch {
      return false;
    }
  }
}

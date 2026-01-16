// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';

interface IERC1155 {
  function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IERC165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

contract ERC1155RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC1155();

  bytes4 private constant ERC1155_INTERFACE_ID = 0xd9b67a26;

  address public immutable token;
  uint256 public immutable tokenId;

  constructor(address _token, uint256 _tokenId) {
    if (_token.code.length == 0) revert InvalidTokenAddress();
    if (!_supportsInterface(_token, ERC1155_INTERFACE_ID)) revert InvalidERC1155();
    token = _token;
    tokenId = _tokenId;
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
    if (IERC1155(token).balanceOf(account, tokenId) > 0) {
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

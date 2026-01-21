// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';

interface IERC721 {
  function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC5192 {
  function locked(uint256 tokenId) external view returns (bool);
}

/// @notice ERC5192 role provider; validates ownership of a specific tokenId.
/// @dev If `requireLocked` is true, `locked(tokenId)` must return true.
///      hooksData must be `abi.encodePacked(provider, abi.encode(tokenId))`.
///      Deploy with skipInterfaceCheck for non-ERC165 tokens.
contract ERC5192RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC5192();

  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant ERC5192_INTERFACE_ID = 0xb45a3c0e;

  address public immutable token;
  bool public immutable requireLocked;

  constructor(address _token, bool _requireLocked, bool skipInterfaceCheck) {
    if (_token.code.length == 0) revert InvalidTokenAddress();
    if (
      !skipInterfaceCheck &&
      (!_supportsInterface(_token, ERC721_INTERFACE_ID) ||
        !_supportsInterface(_token, ERC5192_INTERFACE_ID))
    ) {
      revert InvalidERC5192();
    }
    token = _token;
    requireLocked = _requireLocked;
  }

  function isPullProvider() external pure override returns (bool) {
    return false;
  }

  function getCredential(address) external pure override returns (uint32 timestamp) {
    return 0;
  }

  function validateCredential(
    address account,
    bytes calldata data
  ) external view override returns (uint32 timestamp) {
    if (data.length != 0x20) return 0;
    uint256 tokenId;
    assembly {
      tokenId := calldataload(data.offset)
    }
    return _credentialTimestamp(account, tokenId);
  }

  function _credentialTimestamp(address account, uint256 tokenId) internal view returns (uint32) {
    address owner;
    try IERC721(token).ownerOf(tokenId) returns (address tokenOwner) {
      owner = tokenOwner;
    } catch {
      return 0;
    }
    if (owner != account) return 0;
    if (requireLocked) {
      try IERC5192(token).locked(tokenId) returns (bool isLocked) {
        if (!isLocked) return 0;
      } catch {
        return 0;
      }
    }
    return uint32(block.timestamp);
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

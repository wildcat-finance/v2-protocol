// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';

interface IERC721 {
  function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC5484 {
  function burnAuth(uint256 tokenId) external view returns (uint256);
}

/// @notice ERC5484 role provider; validates ownership of a specific tokenId.
/// @dev `allowedBurnAuthMask` is a bitmask of allowed burnAuth values:
///      bit 0: IssuerOnly, bit 1: OwnerOnly, bit 2: Both, bit 3: Neither.
///      hooksData must be `abi.encodePacked(provider, abi.encode(tokenId))`.
///      Deploy with skipInterfaceCheck for non-ERC165 tokens.
contract ERC5484RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC5484();
  error InvalidBurnAuthMask();

  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant ERC5484_INTERFACE_ID = 0x0489b56f;

  address public immutable token;
  uint8 public immutable allowedBurnAuthMask;

  constructor(address _token, uint8 _allowedBurnAuthMask, bool skipInterfaceCheck) {
    if (_token.code.length == 0) revert InvalidTokenAddress();
    if (_allowedBurnAuthMask == 0) revert InvalidBurnAuthMask();
    if (
      !skipInterfaceCheck &&
      (!_supportsInterface(_token, ERC721_INTERFACE_ID) ||
        !_supportsInterface(_token, ERC5484_INTERFACE_ID))
    ) {
      revert InvalidERC5484();
    }
    token = _token;
    allowedBurnAuthMask = _allowedBurnAuthMask;
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

    uint256 burnAuthValue;
    try IERC5484(token).burnAuth(tokenId) returns (uint256 value) {
      burnAuthValue = value;
    } catch {
      return 0;
    }
    if (burnAuthValue > 3) return 0;
    if ((uint256(allowedBurnAuthMask) & (uint256(1) << burnAuthValue)) == 0) {
      return 0;
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

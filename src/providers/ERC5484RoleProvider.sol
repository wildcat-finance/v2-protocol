// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import 'src/access/IRoleProvider.sol';
import {
  IERC165SupportsInterface,
  IERC5484BurnAuth,
  IERC721OwnerOf
} from './TokenInterfaces.sol';

/// @notice Validates ownership of a supplied token ID from an ERC5484 collection.
/// @dev `allowedBurnAuthMask` is a bitmask of allowed burnAuth values:
///      bit 0: IssuerOnly, bit 1: OwnerOnly, bit 2: Both, bit 3: Neither.
///      hooksData must be `abi.encodePacked(provider, abi.encode(tokenId))`.
///      Deploy with `skipInterfaceCheck` for collections that do not implement ERC165.
contract ERC5484RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC5484();
  error InvalidBurnAuthMask();

  bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant ERC5484_INTERFACE_ID = 0x0489b56f;
  bytes4 private constant INVALID_INTERFACE_ID = 0xffffffff;

  address public immutable token;
  uint8 public immutable allowedBurnAuthMask;

  constructor(address token_, uint8 allowedBurnAuthMask_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (allowedBurnAuthMask_ == 0 || allowedBurnAuthMask_ > 0x0f) {
      revert InvalidBurnAuthMask();
    }
    if (
      !skipInterfaceCheck &&
      (!_supportsERC165(token_) ||
        !_supportsInterface(token_, ERC721_INTERFACE_ID) ||
        !_supportsInterface(token_, ERC5484_INTERFACE_ID))
    ) {
      revert InvalidERC5484();
    }
    token = token_;
    allowedBurnAuthMask = allowedBurnAuthMask_;
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
    try IERC721OwnerOf(token).ownerOf(tokenId) returns (address tokenOwner) {
      owner = tokenOwner;
    } catch {
      return 0;
    }
    if (owner != account) return 0;

    uint256 burnAuthValue;
    try IERC5484BurnAuth(token).burnAuth(tokenId) returns (uint256 value) {
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

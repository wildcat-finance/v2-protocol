// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IRoleProvider.sol';
import {
  ERC165QueryLib,
  IERC5192Locked,
  IERC721OwnerOf,
  TokenQueryLib
} from './TokenInterfaces.sol';

/// @notice Validates ownership of a supplied token ID from an ERC5192 collection.
/// @dev If `requireLocked` is true, `locked(tokenId)` must return true.
///      hooksData must be `abi.encodePacked(provider, abi.encode(tokenId))`.
///      Deploy with `skipInterfaceCheck` for collections that do not implement ERC165.
contract ERC5192RoleProvider is IRoleProvider {
  error InvalidTokenAddress();
  error InvalidERC5192();

  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant ERC5192_INTERFACE_ID = 0xb45a3c0e;

  address public immutable token;
  bool public immutable requireLocked;

  constructor(address token_, bool requireLocked_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (
      !skipInterfaceCheck &&
      (!ERC165QueryLib.supportsERC165(token_) ||
        !ERC165QueryLib.supportsInterface(token_, ERC721_INTERFACE_ID) ||
        !ERC165QueryLib.supportsInterface(token_, ERC5192_INTERFACE_ID))
    ) {
      revert InvalidERC5192();
    }
    token = token_;
    requireLocked = requireLocked_;
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
    (bool success, uint256 value) = TokenQueryLib.readWord(
      token,
      IERC721OwnerOf.ownerOf.selector,
      tokenId
    );
    if (!success || value != uint160(account)) return 0;
    if (requireLocked) {
      (success, value) = TokenQueryLib.readWord(
        token,
        IERC5192Locked.locked.selector,
        tokenId
      );
      if (!success || value != 1) return 0;
    }
    return uint32(block.timestamp);
  }

}

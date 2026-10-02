// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ERC5192RoleProvider
//  \ ^ /   Token ownership and lock-status credentials.
//    V
//
//  SETUP
//  constructor(...)
//  _supportsERC165(...)
//  _supportsInterface(...)
//
//  DISCOVERY
//  isPullProvider()
//
//  CREDENTIALS
//  getCredential(...)
//  validateCredential(...)
//  _credentialTimestamp(...)
// ═════

import 'src/access/IRoleProvider.sol';
import { IERC165SupportsInterface, IERC5192Locked, IERC721OwnerOf } from './TokenInterfaces.sol';

// ┌─ ERC5192RoleProvider ──────────────────────────────────────────────────────
/// @notice validate ownership of a caller-supplied token ID from one ERC5192 collection.
///
/// @dev hook data is `abi.encodePacked(provider, abi.encode(tokenId))`. when `requireLocked` is
///      true, the token must also report itself locked. malformed input, missing tokens, and failed
///      token queries return zero. `skipInterfaceCheck` skips deployment-time ERC165, ERC721, and
///      ERC5192 checks.
contract ERC5192RoleProvider is IRoleProvider {
  /// @dev the token address has no code.
  error InvalidTokenAddress();

  /// @dev the token failed the deployment-time ERC165, ERC721, or ERC5192 checks.
  error InvalidERC5192();

  bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
  bytes4 private constant ERC5192_INTERFACE_ID = 0xb45a3c0e;
  bytes4 private constant INVALID_INTERFACE_ID = 0xffffffff;

  /// @notice collection queried for ownership and lock status.
  address public immutable token;

  /// @notice whether a qualifying token must currently report itself locked.
  bool public immutable requireLocked;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param token_             collection queried for ownership and lock status.
  /// @param requireLocked_     whether a qualifying token must report `locked(tokenId) == true`.
  /// @param skipInterfaceCheck whether to skip ERC165, ERC721, and ERC5192 checks.
  constructor(address token_, bool requireLocked_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (
      !skipInterfaceCheck
        && (!_supportsERC165(token_)
          || !_supportsInterface(token_, ERC721_INTERFACE_ID)
          || !_supportsInterface(token_, ERC5192_INTERFACE_ID))
    ) {
      revert InvalidERC5192();
    }
    token = token_;
    requireLocked = requireLocked_;
  }

  // ┌─ _supportsERC165 ─────
  function _supportsERC165(address target) internal view returns (bool) {
    return _supportsInterface(target, ERC165_INTERFACE_ID) && !_supportsInterface(target, INVALID_INTERFACE_ID);
  }

  // ┌─ _supportsInterface ─────
  function _supportsInterface(address target, bytes4 interfaceId) internal view returns (bool) {
    try IERC165SupportsInterface(target).supportsInterface(interfaceId) returns (bool supported) {
      return supported;
    } catch {
      return false;
    }
  }

  // ░░▒▒▓▓██ [ DISCOVERY ] ────────────────────────────────────────────────────

  // ┌─ isPullProvider ─────
  /// @dev callers must supply a token ID, so this provider cannot use the pull path.
  function isPullProvider() external pure override returns (bool) {
    return false;
  }

  // ░░▒▒▓▓██ [ CREDENTIALS ] ──────────────────────────────────────────────────

  // ┌─ getCredential ─────
  /// @dev token ownership can't be checked without caller-supplied data.
  function getCredential(address) external pure override returns (uint32 timestamp) {
    return 0;
  }

  // ┌─ validateCredential ─────
  /// @return timestamp current timestamp when `account` owns the supplied qualifying token, else
  ///         zero.
  function validateCredential(address account, bytes calldata data) external view override returns (uint32 timestamp) {
    if (data.length != 0x20) return 0;
    uint256 tokenId;
    assembly {
      tokenId := calldataload(data.offset)
    }
    return _credentialTimestamp(account, tokenId);
  }

  // ┌─ _credentialTimestamp ─────
  function _credentialTimestamp(address account, uint256 tokenId) internal view returns (uint32) {
    address owner;
    try IERC721OwnerOf(token).ownerOf(tokenId) returns (address tokenOwner) {
      owner = tokenOwner;
    } catch {
      return 0;
    }
    if (owner != account) return 0;
    if (requireLocked) {
      try IERC5192Locked(token).locked(tokenId) returns (bool isLocked) {
        if (!isLocked) return 0;
      } catch {
        return 0;
      }
    }
    return uint32(block.timestamp);
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // ERC1155RoleProvider
// ║  ██▀▀     ▀▀██   Token-ID balance credentials with optional ERC165 checks.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  constructor(...)
// ║  _supportsERC165(...)
// ║  _supportsInterface(...)
// ║
// ║  CREDENTIALS
// ║  getCredential(...)
// ║  validateCredential(...)
// ║  _credentialTimestamp(...)
// ╚═════

import '../libraries/SafeCastLib.sol';
import './IERC1155RoleProvider.sol';
import { IERC1155BalanceOf, IERC165SupportsInterface } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

// ┌─ ERC1155RoleProvider ──────────────────────────────────────────────────────
/// @notice grant credentials while an account holds one configured ERC1155 token ID.
///
/// @dev balances of every other ID are ignored. `skipInterfaceCheck` skips deployment-time ERC165
///      and ERC1155 checks; it can't repair an incompatible `balanceOf`.
contract ERC1155RoleProvider is IERC1155RoleProvider {
  bool public constant override isPullProvider = true;

  bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
  bytes4 private constant ERC1155_INTERFACE_ID = 0xd9b67a26;
  bytes4 private constant INVALID_INTERFACE_ID = 0xffffffff;

  address public immutable override token;
  uint256 public immutable override tokenId;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param token_             collection queried for balances.
  /// @param tokenId_           only token ID that qualifies.
  /// @param skipInterfaceCheck whether to skip ERC165 and ERC1155 checks during deployment.
  constructor(address token_, uint256 tokenId_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (!skipInterfaceCheck && (!_supportsERC165(token_) || !_supportsInterface(token_, ERC1155_INTERFACE_ID))) {
      revert InvalidERC1155();
    }
    token = token_;
    tokenId = tokenId_;
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

  // ░░▒▒▓▓██ [ CREDENTIALS ] ──────────────────────────────────────────────────

  // ┌─ getCredential ─────
  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  // ┌─ validateCredential ─────
  /// @notice run the live token-ID balance check for `account`; caller data is ignored.
  function validateCredential(address account, bytes calldata) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  // ┌─ _credentialTimestamp ─────
  function _credentialTimestamp(address account) internal view returns (uint32) {
    if (IERC1155BalanceOf(token).balanceOf(account, tokenId) > 0) {
      return block.timestamp.toUint32();
    }
    return 0;
  }
}

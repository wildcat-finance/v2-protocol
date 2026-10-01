// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // TokenData
// ║  ██▀▀     ▀▀██   Token metadata and optional mock-marker queries.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  TOKEN METADATA
// ║  fill(...)
// ║  checkIsMock(...)
// ╚═════

import '../libraries/LibERC20.sol';
import '../interfaces/IERC20.sol';

using LibERC20 for address;
using TokenMetadataLib for TokenMetadata global;

/// @notice ERC-20 metadata used in lens responses; token identity is its chain and address.
///
/// @dev empty name/symbol can mean valid empty text or an unavailable cosmetic read.
struct TokenMetadata {
  address token;
  string name;
  string symbol;
  uint256 decimals;
  bool isMock;
}

// ┌─ TokenMetadataLib ─────────────────────────────────────────────────────────
/// @notice metadata readers used by the lens data fillers.
library TokenMetadataLib {
  // ░░▒▒▓▓██ [ TOKEN METADATA ] ───────────────────────────────────────────────

  // ┌─ fill ─────
  /// @notice fills metadata for `tokenAddress`, with best-effort cosmetic labels.
  ///
  /// @dev a zero address leaves the struct empty. decimals remain strict; failed,
  ///      malformed, oversized or gas-limited name/symbol reads yield empty text.
  function fill(TokenMetadata memory data, address tokenAddress) internal view {
    if (tokenAddress == address(0)) {
      return;
    }
    data.token = tokenAddress;
    data.name = queryStringOrBytes32AsStringOrEmpty(tokenAddress, 0x06fdde03);
    data.symbol = queryStringOrBytes32AsStringOrEmpty(tokenAddress, 0x95d89b41);
    data.decimals = tokenAddress.decimals();
    data.isMock = checkIsMock(tokenAddress);
  }

  // ┌─ checkIsMock ─────
  /// @notice probes the optional `isMock()` marker without making it a required token interface.
  function checkIsMock(address tokenAddress) internal view returns (bool isMock) {
    assembly {
      mstore(0, 0x28ccaa29)
      let success := staticcall(50000, tokenAddress, 0x1c, 4, 0, 32)
      isMock := and(success, and(eq(returndatasize(), 32), eq(mload(0), 1)))
    }
  }
}

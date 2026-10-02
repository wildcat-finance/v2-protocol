// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LibERC20
// ║  ██▀▀     ▀▀██   Safe token transfers, balances, and metadata queries.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  TRANSFERS
// ║  safeTransfer(...)
// ║  safeTransferFrom(...)
// ║  safeTransferAll(...)
// ║
// ║  BALANCES
// ║  balanceOf(...)
// ║
// ║  METADATA
// ║  name(...)
// ║  symbol(...)
// ║  decimals(...)
// ╚═════

import './StringQuery.sol';

// ┌─ LibERC20 ─────────────────────────────────────────────────────────────────
/// @notice safe ERC20 transfers and metadata reads.
///
/// @author d1ll0n
///
/// @notice Changes from solady:
///   - Removed Permit2 and ETH functions
///   - `balanceOf(address)` reverts if the call fails or does not return >=32 bytes
///   - Added queries for `name`, `symbol`, `decimals`
///   - Set name to LibERC20 as it has queries unrelated to transfers and ETH functions were removed
///
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibERC20.sol)
/// @author Previously modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibERC20.sol)
///
/// @dev callers must check that the token has code. this library doesn't.
library LibERC20 {
  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev the ERC20 `transferFrom` has failed.
  error TransferFromFailed();

  /// @dev the ERC20 `transfer` has failed.
  error TransferFailed();

  /// @dev the ERC20 `balanceOf` call has failed.
  error BalanceOfFailed();

  /// @dev the ERC20 `name` call has failed.
  error NameFailed();

  /// @dev the ERC20 `symbol` call has failed.
  error SymbolFailed();

  /// @dev the ERC20 `decimals` call has failed.
  error DecimalsFailed();

  // ░░▒▒▓▓██ [ TRANSFERS ] ────────────────────────────────────────────────────

  // ┌─ safeTransfer ─────
  /// @dev send `amount` of ERC20 `token` from this contract to `to`. revert on failure.
  function safeTransfer(address token, address to, uint256 amount) internal {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x14, to)
      mstore(0x34, amount)
      mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
      if iszero(
        and(
          // `and` evaluates right to left: call first, then inspect returndata.
          or(eq(mload(0x00), 1), iszero(returndatasize())), // accept 1 or no returndata.
          call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x34, 0) // restore the overwritten part of the free memory pointer.
    }
  }

  // ┌─ safeTransferFrom ─────
  /// @dev send `amount` of ERC20 `token` from `from` to `to`. revert on failure.
  ///      `from` must have approved this contract for at least `amount`.
  function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
    /// @solidity memory-safe-assembly
    assembly {
      let m := mload(0x40) // preserve the free memory pointer before borrowing its slot.
      mstore(0x60, amount)
      mstore(0x40, to)
      mstore(0x2c, shl(96, from))
      mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
      if iszero(
        and(
          // `and` evaluates right to left: call first, then inspect returndata.
          or(eq(mload(0x00), 1), iszero(returndatasize())), // accept 1 or no returndata.
          call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x60, 0) // restore the zero slot.
      mstore(0x40, m) // restore the free memory pointer.
    }
  }

  // ┌─ safeTransferAll ─────
  /// @dev send this contract's entire ERC20 `token` balance to `to`. revert on failure.
  function safeTransferAll(address token, address to) internal returns (uint256 amount) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, 0x70a08231) // balanceOf(address)
      mstore(0x20, address())
      if iszero(
        and(
          // `and` evaluates right to left: call first, then inspect returndata.
          gt(returndatasize(), 0x1f), // require at least 32 bytes.
          staticcall(gas(), token, 0x1c, 0x24, 0x34, 0x20)
        )
      ) {
        mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x14, to)
      amount := mload(0x34) // the balance call put the return amount at 0x34.
      mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
      if iszero(
        and(
          // `and` evaluates right to left: call first, then inspect returndata.
          or(eq(mload(0x00), 1), iszero(returndatasize())), // accept 1 or no returndata.
          call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x34, 0) // restore the overwritten part of the free memory pointer.
    }
  }

  // ░░▒▒▓▓██ [ BALANCES ] ─────────────────────────────────────────────────────

  // ┌─ balanceOf ─────
  /// @dev read `account`'s ERC20 `token` balance. revert if the call fails or returns fewer than 32 bytes.
  function balanceOf(address token, address account) internal view returns (uint256 amount) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, 0x70a08231) // balanceOf(address)
      mstore(0x20, account)
      if iszero(
        and(
          // `and` evaluates right to left: call first, then inspect returndata.
          gt(returndatasize(), 0x1f), // require at least 32 bytes.
          staticcall(gas(), token, 0x1c, 0x24, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x4963f6d5) // `BalanceOfFailed()`.
        revert(0x1c, 0x04)
      }
      amount := mload(0x00)
    }
  }

  // ░░▒▒▓▓██ [ METADATA ] ─────────────────────────────────────────────────────

  // ┌─ name ─────
  /// @dev read ERC20 `token`'s name as a string or legacy bytes32. a failed call or malformed encoding reverts.
  function name(address token) internal view returns (string memory) {
    // name(): 0x06fdde03.
    // NameFailed(): 0x2ed09f54.
    return queryStringOrBytes32AsString(token, 0x06fdde03, 0x2ed09f54);
  }

  // ┌─ symbol ─────
  /// @dev read ERC20 `token`'s symbol as a string or legacy bytes32. a failed call or malformed encoding reverts.
  function symbol(address token) internal view returns (string memory) {
    // symbol(): 0x95d89b41.
    // SymbolFailed(): 0x3ddcc60a.
    return queryStringOrBytes32AsString(token, 0x95d89b41, 0x3ddcc60a);
  }

  // ┌─ decimals ─────
  /// @dev read ERC20 `token`'s decimals. require a successful call and exactly one clean uint8 ABI word.
  function decimals(address token) internal view returns (uint8 _decimals) {
    assembly {
      // decimals() occupies the last four bytes of the scratch word.
      mstore(0, 0x313ce567)
      // reuse scratch for the return word. require success, exactly 32 bytes, and a value below 256.
      if iszero(
        and(and(eq(returndatasize(), 0x20), lt(mload(0), 0x100)), staticcall(gas(), token, 0x1c, 0x04, 0, 0x20))
      ) {
        mstore(0x00, 0x3394d170) // `DecimalsFailed()`.
        revert(0x1c, 0x04)
      }
      _decimals := mload(0)
    }
  }
}

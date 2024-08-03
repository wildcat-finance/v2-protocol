// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Safe ERC20 transfer library that gracefully handles missing return values.
/// @author d1ll0n
/// @notice Changes from solady:
///   - Removed Permit2 and ETH functions
///   - `balanceOf(address)` reverts if the call fails or does not return >=32 bytes
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// @author Previously modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol)
///
/// @dev Note:
/// - For ERC20s, this implementation won't check that a token has code,
///   responsibility is delegated to the caller.
library SafeTransferLib {
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       CUSTOM ERRORS                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @dev The ERC20 `transferFrom` has failed.
  error TransferFromFailed();

  /// @dev The ERC20 `transfer` has failed.
  error TransferFailed();

  /// @dev The ERC20 `balanceOf` call has failed.
  error BalanceOfFailed();

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                      ERC20 OPERATIONS                      */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
  /// Reverts upon failure.
  ///
  /// The `from` account must have at least `amount` approved for
  /// the current contract to manage.
  function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
    /// @solidity memory-safe-assembly
    assembly {
      let m := mload(0x40) // Cache the free memory pointer.
      mstore(0x60, amount) // Store the `amount` argument.
      mstore(0x40, to) // Store the `to` argument.
      mstore(0x2c, shl(96, from)) // Store the `from` argument.
      mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
      // Perform the transfer, reverting upon failure.
      if iszero(
        and(
          // The arguments of `and` are evaluated from right to left.
          or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
          call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x60, 0) // Restore the zero slot to zero.
      mstore(0x40, m) // Restore the free memory pointer.
    }
  }

  /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
  /// Reverts upon failure.
  function safeTransfer(address token, address to, uint256 amount) internal {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x14, to) // Store the `to` argument.
      mstore(0x34, amount) // Store the `amount` argument.
      mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
      // Perform the transfer, reverting upon failure.
      if iszero(
        and(
          // The arguments of `and` are evaluated from right to left.
          or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
          call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
    }
  }

  /// @dev Sends all of ERC20 `token` from the current contract to `to`.
  /// Reverts upon failure.
  function safeTransferAll(address token, address to) internal returns (uint256 amount) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, 0x70a08231) // Store the function selector of `balanceOf(address)`.
      mstore(0x20, address()) // Store the address of the current contract.
      // Read the balance, reverting upon failure.
      if iszero(
        and(
          // The arguments of `and` are evaluated from right to left.
          gt(returndatasize(), 0x1f), // At least 32 bytes returned.
          staticcall(gas(), token, 0x1c, 0x24, 0x34, 0x20)
        )
      ) {
        mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x14, to) // Store the `to` argument.
      amount := mload(0x34) // The `amount` is already at 0x34. We'll need to return it.
      mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
      // Perform the transfer, reverting upon failure.
      if iszero(
        and(
          // The arguments of `and` are evaluated from right to left.
          or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
          call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
        revert(0x1c, 0x04)
      }
      mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
    }
  }

  /// @dev Returns the amount of ERC20 `token` owned by `account`.
  /// Reverts if the call to `balanceOf` reverts or returns less than 32 bytes.
  function balanceOf(address token, address account) internal view returns (uint256 amount) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, 0x70a08231) // Store the function selector of `balanceOf(address)`.
      mstore(0x20, account) // Store the `account` argument.
      // Read the balance, reverting upon failure.
      if iszero(
        and(
          // The arguments of `and` are evaluated from right to left.
          gt(returndatasize(), 0x1f), // At least 32 bytes returned.
          staticcall(gas(), token, 0x1c, 0x24, 0x00, 0x20)
        )
      ) {
        mstore(0x00, 0x4963f6d5) // `BalanceOfFailed()`.
        revert(0x1c, 0x04)
      }
      amount := mload(0x00)
    }
  }
}

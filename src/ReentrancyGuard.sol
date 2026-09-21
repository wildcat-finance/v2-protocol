// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @dev Selector for `error NoReentrantCalls()`
uint256 constant NoReentrantCalls_ErrorSelector = 0x7fa8a987;

uint256 constant _REENTRANCY_GUARD_SLOT = 0x929eee14;

/// @title transient reentrancy guard
/// @author d1ll0n
/// @author modified from Seaport by 0age
/// @custom:source https://github.com/ProjectOpenSea/seaport-1.6
/// @notice blocks nested calls with one transaction-scoped storage slot.
/// @dev assumes EIP-1153 support. the original runtime support probe was removed.
contract ReentrancyGuard {
  /// @dev declared for the ABI; the assembly paths use its selector directly.
  error NoReentrantCalls();

  uint256 private constant _NOT_ENTERED = 0;
  uint256 private constant _ENTERED = 1;

  /// @dev sets the guard for a state-changing function and clears it afterward.
  modifier nonReentrant() {
    _setReentrancyGuard();
    _;
    _clearReentrancyGuard();
  }

  /// @dev rejects a view call made while a guarded state-changing call is active.
  modifier nonReentrantView() {
    _assertNonReentrant();
    _;
  }

  /// @dev reverts if entered, then marks the transaction as entered.
  function _setReentrancyGuard() internal {
    assembly {
      // Retrieve the current value of the reentrancy guard slot.
      let _reentrancyGuard := tload(_REENTRANCY_GUARD_SLOT)

      // Ensure that the reentrancy guard is not already set.
      // Equivalent to `if (_reentrancyGuard != _NOT_ENTERED) revert NoReentrantCalls();`
      if _reentrancyGuard {
        mstore(0, NoReentrantCalls_ErrorSelector)
        revert(0x1c, 0x04)
      }

      // Set the reentrancy guard.
      // Equivalent to `_reentrancyGuard = _ENTERED;`
      tstore(_REENTRANCY_GUARD_SLOT, _ENTERED)
    }
  }

  /// @dev clears the transaction-scoped guard.
  function _clearReentrancyGuard() internal {
    assembly {
      // Equivalent to `_reentrancyGuard = _NOT_ENTERED;`
      tstore(_REENTRANCY_GUARD_SLOT, _NOT_ENTERED)
    }
  }

  /// @dev reverts if a guarded call is active in this transaction.
  function _assertNonReentrant() internal view {
    assembly {
      // Ensure that the reentrancy guard is not currently set.
      // Equivalent to `if (_reentrancyGuard != _NOT_ENTERED) revert NoReentrantCalls();`
      if tload(_REENTRANCY_GUARD_SLOT) {
        mstore(0, NoReentrantCalls_ErrorSelector)
        revert(0x1c, 0x04)
      }
    }
  }
}

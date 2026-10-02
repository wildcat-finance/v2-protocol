// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ReentrancyGuard
//  \ ^ /   Transaction-scoped guards for state-changing and view calls.
//    V
//
//  STATE-CHANGING GUARD
//  nonReentrant()
//  _setReentrancyGuard()
//  _clearReentrancyGuard()
//
//  VIEW GUARD
//  nonReentrantView()
//  _assertNonReentrant()
// ═════

/// @dev selector for `error NoReentrantCalls()`.
uint256 constant NoReentrantCalls_ErrorSelector = 0x7fa8a987;

uint256 constant _REENTRANCY_GUARD_SLOT = 0x929eee14;

// ┌─ ReentrancyGuard ──────────────────────────────────────────────────────────
/// @title transient reentrancy guard
///
/// @author d1ll0n
/// @author modified from Seaport by 0age
///
/// @custom:source https://github.com/ProjectOpenSea/seaport-1.6
///
/// @notice block nested calls with one transaction-scoped storage slot.
///
/// @dev assumes EIP-1153 support. the original runtime support probe was removed.
contract ReentrancyGuard {
  /// @dev declared for the ABI; the assembly paths use its selector directly.
  error NoReentrantCalls();

  uint256 private constant _NOT_ENTERED = 0;
  uint256 private constant _ENTERED = 1;

  // ░░▒▒▓▓██ [ STATE-CHANGING GUARD ] ─────────────────────────────────────────

  // ┌─ nonReentrant ─────
  /// @dev guard a state-changing call, then clear the slot so later calls can proceed.
  modifier nonReentrant() {
    _setReentrancyGuard();
    _;
    _clearReentrancyGuard();
  }

  // ┌─ _setReentrancyGuard ─────
  /// @dev reject nested entry, then mark this transaction's guard active.
  function _setReentrancyGuard() internal {
    assembly {
      let _reentrancyGuard := tload(_REENTRANCY_GUARD_SLOT)

      if _reentrancyGuard {
        mstore(0, NoReentrantCalls_ErrorSelector)
        revert(0x1c, 0x04)
      }

      tstore(_REENTRANCY_GUARD_SLOT, _ENTERED)
    }
  }

  // ┌─ _clearReentrancyGuard ─────
  /// @dev clear the transaction-scoped guard.
  function _clearReentrancyGuard() internal {
    assembly {
      tstore(_REENTRANCY_GUARD_SLOT, _NOT_ENTERED)
    }
  }

  // ░░▒▒▓▓██ [ VIEW GUARD ] ───────────────────────────────────────────────────

  // ┌─ nonReentrantView ─────
  /// @dev reject a view call made while a guarded state-changing call is active.
  modifier nonReentrantView() {
    _assertNonReentrant();
    _;
  }

  // ┌─ _assertNonReentrant ─────
  /// @dev revert if a guarded call is active in this transaction.
  function _assertNonReentrant() internal view {
    assembly {
      if tload(_REENTRANCY_GUARD_SLOT) {
        mstore(0, NoReentrantCalls_ErrorSelector)
        revert(0x1c, 0x04)
      }
    }
  }
}

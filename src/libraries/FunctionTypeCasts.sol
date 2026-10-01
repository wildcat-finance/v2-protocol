// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // FunctionTypeCasts
// ║  ██▀▀     ▀▀██   Typed views of existing market memory allocations.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DEPLOYMENT PARAMETERS
// ║  asReturnsMarketParameters(...)
// ║
// ║  STATE AND BATCH VIEWS
// ║  asReturnsMarketState(...)
// ║  asReturnsPointers(...)
// ║
// ║  TRANSITION ALLOCATION
// ║  asTransitionAllocator(...)
// ╚═════

import { MarketParameters } from '../interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from '../libraries/MarketState.sol';
import { WithdrawalBatch } from '../libraries/Withdrawal.sol';
import { LifecycleTransition } from './MarketLifecycle.sol';

// ┌─ FunctionTypeCasts ────────────────────────────────────────────────────────
/// @dev Type-casts to convert functions returning raw (uint) pointers
///      to functions returning memory pointers of specific types.
///
///      Used to get around solc's over-allocation of memory when
///      dynamic return parameters are re-assigned.
///
///      With `viaIR` enabled, calling any of these functions is a noop.
library FunctionTypeCasts {
  // ░░▒▒▓▓██ [ DEPLOYMENT PARAMETERS ] ────────────────────────────────────────

  // ┌─ asReturnsMarketParameters ─────
  /// @dev Function type cast to avoid duplicate declaration/allocation
  ///      of manually allocated MarketParameters in market constructor.
  function asReturnsMarketParameters(function() internal view returns (uint256) fnIn)
    internal
    pure
    returns (function() internal view returns (MarketParameters memory) fnOut)
  {
    assembly {
      fnOut := fnIn
    }
  }

  // ░░▒▒▓▓██ [ STATE AND BATCH VIEWS ] ────────────────────────────────────────

  // ┌─ asReturnsMarketState ─────
  /// @dev Function type cast to avoid duplicate declaration/allocation
  ///      of MarketState return parameter.
  function asReturnsMarketState(function() internal view returns (uint256) fnIn)
    internal
    pure
    returns (function() internal view returns (MarketState memory) fnOut)
  {
    assembly {
      fnOut := fnIn
    }
  }

  // ┌─ asReturnsPointers ─────
  /// @dev Function type cast to avoid duplicate declaration/allocation
  ///      of MarketState and WithdrawalBatch return parameters.
  function asReturnsPointers(function() internal view returns (MarketState memory, uint32, WithdrawalBatch memory) fnIn)
    internal
    pure
    returns (function() internal view returns (uint256, uint32, uint256) fnOut)
  {
    assembly {
      fnOut := fnIn
    }
  }

  // ░░▒▒▓▓██ [ TRANSITION ALLOCATION ] ────────────────────────────────────────

  // ┌─ asTransitionAllocator ─────
  /// @dev use the allocator's arena; don't allocate a second empty transition.
  function asTransitionAllocator(function() internal pure returns (uint256) fnIn)
    internal
    pure
    returns (function() internal pure returns (LifecycleTransition memory) fnOut)
  {
    assembly {
      fnOut := fnIn
    }
  }
}

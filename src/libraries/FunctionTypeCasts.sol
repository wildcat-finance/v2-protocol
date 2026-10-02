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
/// @dev treat raw uint return pointers as typed memory references. this avoids solc allocating
///      another buffer when dynamic return parameters are reassigned. with `viaIR`, the casts are no-ops.
library FunctionTypeCasts {
  // ░░▒▒▓▓██ [ DEPLOYMENT PARAMETERS ] ────────────────────────────────────────

  // ┌─ asReturnsMarketParameters ─────
  /// @dev reuse the constructor's manually allocated MarketParameters buffer.
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
  /// @dev reuse the returned MarketState buffer instead of allocating another.
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
  /// @dev reuse the MarketState and WithdrawalBatch return buffers.
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

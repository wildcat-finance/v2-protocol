// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IWildcat4626WrapperFactory
//  \ ^ /   Canonical wrapper deployment.
//    V
//
//  OPERATIONS
//  createWrapper(...)
// ═════

// ┌─ IWildcat4626WrapperFactory ──────────────────────────────────────────────
/// @notice deployment shared by canonical wrapper factory generations.
interface IWildcat4626WrapperFactory {
  // ┌─ createWrapper ─────
  function createWrapper(address market) external returns (address wrapper);
}

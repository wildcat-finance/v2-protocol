// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // RoleProviderFactoryMocks
//  \ ^ /   Alternate caller for provider factory tests.
//    V
//
//  FACTORY CALLS
//  createRoleProvider(...)
//
// ═════

import { IRoleProviderFactory } from 'src/access/IRoleProviderFactory.sol';

// ┌─ RoleProviderFactoryCaller ────────────────────────────────────────────────
contract RoleProviderFactoryCaller {
  // ░░▒▒▓▓██ [ FACTORY CALLS ] ────────────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  function createRoleProvider(address factory, bytes calldata data) external returns (address provider) {
    return IRoleProviderFactory(factory).createRoleProvider(data);
  }
}

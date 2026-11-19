// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // SphereXProtectedErrors
//  \ ^ /   Compact reverts for SphereX authority and engine checks.
//    V
//
//  AUTHORITY ERRORS
//  revert_SphereXAdminRequired()
//  revert_SphereXNotPendingAdmin()
//  revert_SphereXOperatorRequired()
//  revert_SphereXOperatorOrAdminRequired()
//
//  ENGINE ERRORS
//  revert_SphereXNotEngine()
// ═════

// ░░▒▒▓▓██ [ AUTHORITY ERRORS ] ───────────────────────────────────────────────

// ┌─ revert_SphereXAdminRequired ─────
function revert_SphereXAdminRequired() pure {
  assembly {
    mstore(0, 0x6222a550)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_SphereXNotPendingAdmin ─────
function revert_SphereXNotPendingAdmin() pure {
  assembly {
    mstore(0, 0x4d28a58e)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_SphereXOperatorRequired ─────
function revert_SphereXOperatorRequired() pure {
  assembly {
    mstore(0, 0x4ee0b8f8)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_SphereXOperatorOrAdminRequired ─────
function revert_SphereXOperatorOrAdminRequired() pure {
  assembly {
    mstore(0, 0xb2dbeb59)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ ENGINE ERRORS ] ──────────────────────────────────────────────────

// ┌─ revert_SphereXNotEngine ─────
function revert_SphereXNotEngine() pure {
  assembly {
    mstore(0, 0x7dcb7ada)
    revert(0x1c, 0x04)
  }
}

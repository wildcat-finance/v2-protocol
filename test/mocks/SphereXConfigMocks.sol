// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // SphereXConfigMocks
// ║  ██▀▀     ▀▀██   Engine configuration and guarded-target test harnesses.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ENGINE CAPABILITIES
// ║  constructor(...)
// ║  supportsInterface(...)
// ║  addAllowedSenderOnChain(...)
// ║
// ║  SENDER REGISTRATION
// ║  constructor(...)
// ║  addSender(...)
// ║
// ║  GUARDED TARGET
// ║  constructor(...)
// ║  setValue(...)
// ╚═════

import { SphereXConfig } from 'src/spherex/SphereXConfig.sol';
import { SphereXProtectedRegisteredBase } from 'src/spherex/SphereXProtectedRegisteredBase.sol';

// ┌─ SphereXEngineMock ────────────────────────────────────────────────────────
contract SphereXEngineMock {
  bool internal immutable supported;

  event NewSenderOnEngine(address sender);

  // ░░▒▒▓▓██ [ ENGINE CAPABILITIES ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(bool _supported) {
    supported = _supported;
  }

  // ┌─ supportsInterface ─────
  function supportsInterface(bytes4) external view returns (bool) {
    return supported;
  }

  // ┌─ addAllowedSenderOnChain ─────
  function addAllowedSenderOnChain(address sender) external {
    emit NewSenderOnEngine(sender);
  }
}

// ┌─ SphereXConfigHarness ─────────────────────────────────────────────────────
contract SphereXConfigHarness is SphereXConfig {
  // ░░▒▒▓▓██ [ SENDER REGISTRATION ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address admin, address operator, address engine) SphereXConfig(admin, operator, engine) { }

  // ┌─ addSender ─────
  function addSender(address sender) external spherexOnlyOperatorOrAdmin {
    _addAllowedSenderOnChain(sender);
  }
}

// ┌─ SphereXRegisteredHarness ─────────────────────────────────────────────────
contract SphereXRegisteredHarness is SphereXProtectedRegisteredBase {
  uint256 public value;

  // ░░▒▒▓▓██ [ GUARDED TARGET ] ───────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address archController, address engine) {
    _archController = archController;
    __SphereXProtectedRegisteredBase_init(engine);
  }

  // ┌─ setValue ─────
  function setValue(uint256 newValue) external sphereXGuardExternal {
    value = newValue;
  }
}

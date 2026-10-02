// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // ArchControllerMocks
//  \ ^ /   Controller registration and engine propagation test targets.
//    V
//
//  REGISTERED TARGET
//  constructor(...)
//  changeSphereXEngine(...)
//
//  ENGINE REGISTRATION
//  addAllowedSenderOnChain(...)
//  supportsInterface(...)
//
//  ENGINE VALIDATION
//  sphereXValidatePre(...)
//  sphereXValidatePost(...)
//  sphereXValidateInternalPre(...)
//  sphereXValidateInternalPost(...)
// ═════

import { ISphereXEngine } from 'src/spherex/ISphereXEngine.sol';

// ┌─ ArchControllerRegisteredTargetMock ───────────────────────────────────────
contract ArchControllerRegisteredTargetMock {
  error ChangeSphereXEngineBlocked();

  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);

  bool internal immutable _blockEngineUpdates;
  address public sphereXEngine;
  uint256 public updateCount;

  // ░░▒▒▓▓██ [ REGISTERED TARGET ] ────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(bool blockEngineUpdates) {
    _blockEngineUpdates = blockEngineUpdates;
  }

  // ┌─ changeSphereXEngine ─────
  function changeSphereXEngine(address newEngine) external {
    if (_blockEngineUpdates) revert ChangeSphereXEngineBlocked();
    address oldEngine = sphereXEngine;
    sphereXEngine = newEngine;
    updateCount++;
    emit ChangedSpherexEngineAddress(oldEngine, newEngine);
  }
}

// ┌─ ArchControllerEngineMock ─────────────────────────────────────────────────
contract ArchControllerEngineMock is ISphereXEngine {
  event NewSenderOnEngine(address sender);

  mapping(address sender => uint256 calls) public allowedSenderCalls;

  // ░░▒▒▓▓██ [ ENGINE REGISTRATION ] ──────────────────────────────────────────

  // ┌─ addAllowedSenderOnChain ─────
  function addAllowedSenderOnChain(address sender) external {
    allowedSenderCalls[sender]++;
    emit NewSenderOnEngine(sender);
  }

  // ┌─ supportsInterface ─────
  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == type(ISphereXEngine).interfaceId;
  }

  // ░░▒▒▓▓██ [ ENGINE VALIDATION ] ────────────────────────────────────────────

  // ┌─ sphereXValidatePre ─────
  function sphereXValidatePre(int256, address, bytes calldata) external pure returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  // ┌─ sphereXValidatePost ─────
  function sphereXValidatePost(int256, uint256, bytes32[] calldata, bytes32[] calldata) external pure { }

  // ┌─ sphereXValidateInternalPre ─────
  function sphereXValidateInternalPre(int256) external pure returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  // ┌─ sphereXValidateInternalPost ─────
  function sphereXValidateInternalPost(int256, uint256, bytes32[] calldata, bytes32[] calldata) external pure { }
}

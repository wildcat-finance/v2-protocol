// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MockRoleProvider
//  \ ^ /   Configurable pull and push credential responses.
//    V
//
//  PROVIDER BEHAVIOR
//  setIsPullProvider(...)
//  setCallShouldRevert(...)
//  setCallShouldReturnCorruptedData(...)
//
//  PULL CREDENTIALS
//  setCredential(...)
//  getCredential(...)
//
//  PUSH CREDENTIALS
//  approveCredentialData(...)
//  validateCredential(...)
// ═════

import { IRoleProvider } from 'src/access/IRoleProvider.sol';

// ┌─ MockRoleProvider ─────────────────────────────────────────────────────────
contract MockRoleProvider is IRoleProvider {
  error BadCredential();

  bool public callShouldRevert;
  bool public override isPullProvider;
  bool public callShouldReturnCorruptedData;

  mapping(address account => uint32 timestamp) public credentialsByAccount;
  mapping(bytes32 dataHash => uint32 timestamp) public credentialsByHash;

  // ░░▒▒▓▓██ [ PROVIDER BEHAVIOR ] ────────────────────────────────────────────

  // ┌─ setIsPullProvider ─────
  function setIsPullProvider(bool value) external {
    isPullProvider = value;
  }

  // ┌─ setCallShouldRevert ─────
  function setCallShouldRevert(bool value) external {
    callShouldRevert = value;
  }

  // ┌─ setCallShouldReturnCorruptedData ─────
  function setCallShouldReturnCorruptedData(bool value) external {
    callShouldReturnCorruptedData = value;
  }

  // ░░▒▒▓▓██ [ PULL CREDENTIALS ] ─────────────────────────────────────────────

  // ┌─ setCredential ─────
  function setCredential(address account, uint32 timestamp) external {
    credentialsByAccount[account] = timestamp;
  }

  // ┌─ getCredential ─────
  function getCredential(address account) external view override returns (uint32 timestamp) {
    if (callShouldRevert) revert BadCredential();
    if (callShouldReturnCorruptedData) {
      assembly {
        return(0, 0)
      }
    }
    return credentialsByAccount[account];
  }

  // ░░▒▒▓▓██ [ PUSH CREDENTIALS ] ─────────────────────────────────────────────

  // ┌─ approveCredentialData ─────
  function approveCredentialData(bytes32 dataHash, uint32 timestamp) external {
    credentialsByHash[dataHash] = timestamp;
  }

  // ┌─ validateCredential ─────
  function validateCredential(address, bytes calldata data) external view override returns (uint32 timestamp) {
    if (callShouldRevert) revert BadCredential();
    if (callShouldReturnCorruptedData) {
      assembly {
        return(0, 0)
      }
    }
    return credentialsByHash[keccak256(data)];
  }
}

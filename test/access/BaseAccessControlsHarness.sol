// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // BaseAccessControlsHarness
//  \ ^ /   Test adapters for credential and recipient-access checks.
//    V
//
//  HARNESS SETUP
//  constructor(...)
//  setIsKnownLender(...)
//
//  ACCESS VALIDATION
//  tryValidateAccess(...)
//  isMarketTransferRecipientAllowed(...)
// ═════

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';

// ┌─ BaseAccessControlsHarness ────────────────────────────────────────────────
contract BaseAccessControlsHarness is BaseAccessControls {
  // ░░▒▒▓▓██ [ HARNESS SETUP ] ────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address administrator, NameAndProviderInputs memory inputs) BaseAccessControls(administrator) {
    _initialize(inputs);
  }

  // ┌─ setIsKnownLender ─────
  function setIsKnownLender(address account, address market, bool isKnownLender) external {
    isKnownLenderOnMarket[account][market] = isKnownLender;
  }

  // ░░▒▒▓▓██ [ ACCESS VALIDATION ] ────────────────────────────────────────────

  // ┌─ tryValidateAccess ─────
  function tryValidateAccess(
    address accountAddress,
    bytes calldata hooksData
  )
    external
    returns (bool hasValidCredential, bool wasUpdated)
  {
    bytes32 beforeHash = keccak256(abi.encode(_lenderStatus[accountAddress]));
    hasValidCredential = _tryValidateAccess(_lenderStatus[accountAddress], accountAddress, hooksData);
    wasUpdated = beforeHash != keccak256(abi.encode(_lenderStatus[accountAddress]));
  }

  // ┌─ isMarketTransferRecipientAllowed ─────
  function isMarketTransferRecipientAllowed(
    address market,
    address recipient,
    bool transferRequiresAccess
  )
    external
    view
    returns (bool)
  {
    return _isMarketTransferRecipientAllowed(market, recipient, transferRequiresAccess);
  }
}

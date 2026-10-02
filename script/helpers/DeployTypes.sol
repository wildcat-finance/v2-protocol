// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // DeployTypes
// ║  ██▀▀     ▀▀██   Development market configuration and hook encoding.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  HOOK ENCODING
// ║  encodeHooksData(...)
// ║  toHooksConfig(...)
// ║
// ║  TOKEN DEPLOYMENT
// ║  deployMockERC20(...)
// ╚═════

import 'src/types/HooksConfig.sol';

struct MarketConfig {
  // token parameters
  string tokenName;
  string tokenSymbol;
  uint8 tokenDecimals;
  // market parameters
  bytes32 salt;
  string namePrefix;
  string symbolPrefix;
  uint128 maxTotalSupply;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  // hooks options
  MarketHooksOptions hooks;
  // derived
  string marketSymbol;
}

/// recipient access required for market-token transfers.
enum TransferAccess {
  /// no transfers allowed.
  /// `transfersDisabled` = true
  Disabled,
  /// recipient needs a credential or known-lender status.
  /// `transfersDisabled` = false, `useOnTransfer` = true (in deployment hooks config)
  RequiresCredential,
  /// anyone can receive a transfer.
  /// `transfersDisabled` = false, `useOnTransfer` = false (in deployment hooks config)
  Open
}

/// lender access required for deposits.
enum DepositAccess {
  /// depositors need a credential.
  /// `useOnDeposit` = true (in deployment hooks config)
  RequiresCredential,
  /// anyone can deposit.
  /// `useOnDeposit` = false (in deployment hooks config)
  Open
}

/// lender access required to queue a withdrawal.
enum WithdrawalAccess {
  /// withdrawer needs a credential or known-lender status.
  /// `useOnQueueWithdrawal` = true (in deployment hooks config)
  RequiresCredential,
  /// anyone can queue a withdrawal.
  /// `useOnQueueWithdrawal` = false (in deployment hooks config)
  Open
}

struct MarketHooksOptions {
  bool isOpenTerm;
  TransferAccess transferAccess;
  DepositAccess depositAccess;
  WithdrawalAccess withdrawalAccess;
  uint128 minimumDeposit;
  uint32 fixedTermEndTime;
  bool allowClosureBeforeTerm;
  bool allowTermReduction;
  string hooksName;
  bool useUniversalProvider;
}

using { encodeHooksData, toHooksConfig } for MarketHooksOptions global;

// ░░▒▒▓▓██ [ HOOK ENCODING ] ──────────────────────────────────────────────────

// ┌─ encodeHooksData ─────
function encodeHooksData(MarketHooksOptions memory options) pure returns (bytes memory) {
  if (options.isOpenTerm) {
    return abi.encode(options.minimumDeposit, options.transferAccess == TransferAccess.Disabled);
  }
  return abi.encode(
    options.fixedTermEndTime,
    options.minimumDeposit,
    options.transferAccess == TransferAccess.Disabled,
    options.allowClosureBeforeTerm,
    options.allowTermReduction
  );
}

// ┌─ toHooksConfig ─────
function toHooksConfig(MarketHooksOptions memory options) pure returns (HooksConfig) {
  return encodeHooksConfig({
    hooksAddress: address(0),
    useOnTransfer: options.transferAccess == TransferAccess.RequiresCredential,
    useOnDeposit: options.depositAccess == DepositAccess.RequiresCredential,
    useOnQueueWithdrawal: options.withdrawalAccess == WithdrawalAccess.RequiresCredential,
    useOnExecuteWithdrawal: false,
    useOnBorrow: false,
    useOnRepay: false,
    useOnCloseMarket: false,
    useOnNukeFromOrbit: false,
    useOnSetMaxTotalSupply: false,
    useOnSetAnnualInterestAndReserveRatioBips: false,
    useOnSetProtocolFeeBips: false
  });
}

// ┌─ IMockERC20Factory ────────────────────────────────────────────────────────
interface IMockERC20Factory {
  // ░░▒▒▓▓██ [ TOKEN DEPLOYMENT ] ─────────────────────────────────────────────

  // ┌─ deployMockERC20 ─────
  function deployMockERC20(string memory name, string memory symbol) external returns (address);
}

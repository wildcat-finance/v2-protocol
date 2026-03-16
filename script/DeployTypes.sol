// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

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

/** Level of access required for accounts to receive a transfer */
enum TransferAccess {
  /**
   * No transfers allowed
   * `transfersDisabled` = true
   */
  Disabled,
  /**
   * Transfer recipient must have a credential or be a known lender
   * `transfersDisabled` = false, `useOnTransfer` = true (in deployment hooks config)
   */
  RequiresCredential,
  /**
   * Anyone can receive a transfer
   * `transfersDisabled` = false, `useOnTransfer` = false (in deployment hooks config)
   */
  Open
}

/** Level of access required for a lender to make a deposit */
enum DepositAccess {
  /**
   * Depositors must have a credential
   * `useOnDeposit` = true (in deployment hooks config)
   */
  RequiresCredential,
  /**
   * Anyone can make a deposit
   * `useOnDeposit` = false (in deployment hooks config)
   */
  Open
}

/** Level of access required for a lender to make a withdrawal request */
enum WithdrawalAccess {
  /**
   * Withdrawing account must have a credential or be a known lender
   * `useOnQueueWithdrawal` = true (in deployment hooks config)
   */
  RequiresCredential,
  /**
   * Anyone can make a withdrawal request
   * `useOnQueueWithdrawal` = false (in deployment hooks config)
   */
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

function encodeHooksData(MarketHooksOptions memory options) pure returns (bytes memory) {
  if (options.isOpenTerm) {
    return
      abi.encode(
        options.minimumDeposit,
        options.transferAccess == TransferAccess.Disabled
      );
  }
  return
    abi.encode(
      options.fixedTermEndTime,
      options.minimumDeposit,
      options.transferAccess == TransferAccess.Disabled,
      options.allowClosureBeforeTerm,
      options.allowTermReduction
    );
}

function toHooksConfig(MarketHooksOptions memory options) pure returns (HooksConfig) {
  return
    encodeHooksConfig({
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
interface IMockERC20Factory {
  function deployMockERC20(string memory name, string memory symbol) external returns (address);
}
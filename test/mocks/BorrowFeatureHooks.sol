// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Borrow } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_CloseMarket } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { BorrowAmountPolicy } from './BorrowAmountPolicy.sol';
import { OpenTransferPolicy } from './TransferFeatureHooks.sol';
import { FixedTransferPolicy } from './TransferFeatureHooks.sol';
import { PeriodicTransferPolicy } from './TransferFeatureHooks.sol';

contract OpenBorrowHooks is OpenTransferPolicy, BorrowAmountPolicy {
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_QueueWithdrawal
        ),
        EmptyHooksConfig.setFlag(Bit_Enabled_Transfer).setFlag(Bit_Enabled_Borrow).setFlag(
          Bit_Enabled_SetAnnualInterestAndReserveRatioBips
        )
      )
    )
  {}

  function _onMarketConfigured(
    address administrator,
    address market,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    HooksConfig hooks
  ) internal override {
    OpenTransferPolicy._onMarketConfigured(administrator, market, parameters, hooksData, hooks);
    // creation runs before the market exists. initialize from parameters, not a market getter.
    _setBorrowAmountLimit(market, parameters.maxTotalSupply);
  }

  function _checkBorrow(
    uint256 normalizedAmount,
    MarketState calldata,
    bytes calldata
  ) internal override {
    // onBorrow has no shared caller guard. authenticate before touching feature state.
    _requireHookedMarket(msg.sender);
    _recordBorrowAmount(msg.sender, normalizedAmount);
  }

  function version() external pure override returns (string memory) {
    return 'OpenBorrowHooks';
  }
}

contract FixedBorrowHooks is FixedTransferPolicy, BorrowAmountPolicy {
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_Borrow)
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
      )
    )
  {}

  function _onMarketConfigured(
    address administrator,
    address market,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    HooksConfig hooks
  ) internal override {
    FixedTransferPolicy._onMarketConfigured(administrator, market, parameters, hooksData, hooks);
    _setBorrowAmountLimit(market, parameters.maxTotalSupply);
  }

  function _checkBorrow(
    uint256 normalizedAmount,
    MarketState calldata,
    bytes calldata
  ) internal override {
    // onBorrow has no shared caller guard. authenticate before touching feature state.
    _requireHookedMarket(msg.sender);
    _recordBorrowAmount(msg.sender, normalizedAmount);
  }

  function version() external pure override returns (string memory) {
    return 'FixedBorrowHooks';
  }
}

contract PeriodicBorrowHooks is PeriodicTransferPolicy, BorrowAmountPolicy {
  constructor(
    address administrator,
    bytes memory args
  )
    BaseHooks(
      administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_Transfer)
          .setFlag(Bit_Enabled_Borrow)
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
          .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction)
      )
    )
  {}

  function _onMarketConfigured(
    address administrator,
    address market,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    HooksConfig hooks
  ) internal override {
    PeriodicTransferPolicy._onMarketConfigured(administrator, market, parameters, hooksData, hooks);
    _setBorrowAmountLimit(market, parameters.maxTotalSupply);
  }

  function _checkBorrow(
    uint256 normalizedAmount,
    MarketState calldata,
    bytes calldata
  ) internal override {
    // onBorrow has no shared caller guard. authenticate before touching feature state.
    _requireHookedMarket(msg.sender);
    _recordBorrowAmount(msg.sender, normalizedAmount);
  }

  function version() external pure override returns (string memory) {
    return 'PeriodicBorrowHooks';
  }
}

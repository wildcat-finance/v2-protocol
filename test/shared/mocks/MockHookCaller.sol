// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/HooksConfig.sol';
import 'src/libraries/MarketState.sol';
import './MockHooks.sol';

contract MockHookCaller {
  HooksConfig internal hooks;
  MarketState internal state;

  function setState(MarketState memory _state) external {
    state = _state;
  }

  function setConfig(HooksConfig _hooks) external {
    hooks = _hooks;
  }

  function deposit(uint256 scaledAmount) external {
    hooks.onDeposit(msg.sender, scaledAmount, state);
  }

  function queueWithdrawal(uint scaledAmount) external {
    hooks.onQueueWithdrawal(msg.sender, scaledAmount, state);
  }

  function executeWithdrawal(address lender, uint128 normalizedAmountWithdrawn) external {
    hooks.onExecuteWithdrawal(lender, normalizedAmountWithdrawn, state, 0x44);
  }

  function transferFrom(address from, address to, uint scaledAmount) external {
    hooks.onTransfer(from, to, scaledAmount, state, 0x64);
  }

  function transfer(address to, uint scaledAmount) external {
    hooks.onTransfer(msg.sender, to, scaledAmount, state, 0x44);
  }

  function borrow(uint normalizedAmount) external {
    hooks.onBorrow(normalizedAmount, state);
  }

  function repay(uint normalizedAmount) external {
    hooks.onRepay(normalizedAmount, state, 0x24);
  }

  event Entered();

  function closeMarket() external {
    emit Entered();
    hooks.onCloseMarket(state);
  }

  function sendAssetsToEscrow(
    address lender,
    address asset,
    address escrow,
    uint scaledAmount
  ) external {
    hooks.onAssetsSentToEscrow(lender, asset, escrow, scaledAmount, state, 0x84);
  }

  function setMaxTotalSupply(uint256 maxTotalSupply) external {
    hooks.onSetMaxTotalSupply(maxTotalSupply, state);
  }

  function setAnnualInterestBips(uint16 annualInterestBips) external {
    hooks.onSetAnnualInterestBips(annualInterestBips, state);
  }
}
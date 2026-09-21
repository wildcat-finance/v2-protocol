// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';

/// @dev Calls LibHooksConfig from normal ABI entry points. Tests append bytes
///      after those arguments to model the market's hook extraData convention.
contract HooksConfigCaller {
  HooksConfig internal hooks;
  MarketState internal state;

  function setState(MarketState calldata newState) external {
    state = newState;
  }

  function setConfig(HooksConfig newHooks) external {
    hooks = newHooks;
  }

  function deposit(uint256 scaledAmount) external {
    hooks.onDeposit(msg.sender, scaledAmount, state);
  }

  function queueWithdrawal(uint32 expiry, uint256 scaledAmount) external {
    hooks.onQueueWithdrawal(msg.sender, expiry, scaledAmount, state, 0x44);
  }

  function executeWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn
  ) external {
    hooks.onExecuteWithdrawal(lender, expiry, normalizedAmountWithdrawn, state, 0x64);
  }

  function transfer(address to, uint256 scaledAmount) external {
    hooks.onTransfer(msg.sender, to, scaledAmount, state, 0x44);
  }

  function borrow(uint256 normalizedAmount) external {
    hooks.onBorrow(normalizedAmount, state);
  }

  function repay(uint256 normalizedAmount) external {
    hooks.onRepay(normalizedAmount, state, 0x24);
  }

  function closeMarket() external {
    hooks.onCloseMarket(state);
  }

  function nukeFromOrbit(address lender) external {
    hooks.onNukeFromOrbit(lender, state);
  }

  function setMaxTotalSupply(uint256 maxTotalSupply) external {
    hooks.onSetMaxTotalSupply(maxTotalSupply, state);
  }

  function setAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  ) external returns (uint16, uint16) {
    return
      hooks.onSetAnnualInterestAndReserveRatioBips(annualInterestBips, reserveRatioBips, state);
  }

  function setProtocolFeeBips(uint16 protocolFeeBips) external {
    hooks.onSetProtocolFeeBips(protocolFeeBips, state);
  }
}

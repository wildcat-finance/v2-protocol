// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/HooksConfig.sol';
import 'forge-std/Test.sol';
import '../helpers/Assertions.sol';
import '../shared/FuzzInputs.sol';

contract MockHook {
  bytes32 public lastCalldataHash;

  fallback() external {}
}

contract MockHookCaller {
  MockHook internal hooks = new MockHook();
  MarketState internal state;

  function setState(MarketState memory _state) external {
    state = _state;
  }

  function deposit(uint256 scaledAmount) external {
    hooks.onDeposit(msg.sender, scaledAmount, state, extraData);
  }

  function queueWithdrawal(uint scaledAmount) external {
    hooks.onQueueWithdrawal(msg.sender, scaledAmount, state);
  }

  function executeWithdrawal(uint128 normalizedAmountWithdrawn) external {
    hooks.onExecuteWithdrawal(msg.sender, normalizedAmountWithdrawn, state);
  }

  function transferFrom(address from, address to, uint scaledAmount) external {
    hooks.onTransfer(msg.sender, from, to, scaledAmount, state, 0x64);
  }

  function transfer(address to, uint scaledAmount) external {
    hooks.onTransfer(msg.sender, msg.sender, to, scaledAmount, state, 0x44);
  }

  function borrow(uint normalizedAmount) external {
    hooks.onBorrow(normalizedAmount, state);
  }

  function repay(uint normalizedAmount) external {
    hooks.onRepay(normalizedAmount, state, 0x24);
  }

  function closeMarket() external {
    hooks.onCloseMarket(state);
  }

}

contract HooksConfigTest is Test, Assertions {
  MockHook internal hooks = new MockHook();

  function testEncode(StandardHooksConfig memory input) external {
    HooksConfig hooks = input.toHooksConfig();
    assertEq(hooks, input);
  }

  function test_onDeposit(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onQueueWithdrawal(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onExecuteWithdrawal(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onTransfer(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onBorrow(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onRepay(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onCloseMarket(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onAssetsSentToEscrow(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onSetMaxTotalSupply(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }

  function test_onSetAnnualInterestBips(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput
  ) external {
    MarketState memory state = stateInput.toState();
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
  }
}

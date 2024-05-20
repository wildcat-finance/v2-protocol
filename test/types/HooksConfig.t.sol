// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/HooksConfig.sol';
import { Test, console2 } from 'forge-std/Test.sol';
import '../helpers/Assertions.sol';
import '../shared/FuzzInputs.sol';
import 'solady/utils/LibString.sol';
import '../shared/mocks/MockHooks.sol';
import '../shared/mocks/MockHookCaller.sol';

using LibString for uint;

contract HooksConfigTest is Test, Assertions {
  MockHooks internal hooks = new MockHooks();
  MockHookCaller internal mockHookCaller = new MockHookCaller();

  function _callMockHookCaller(bytes memory _calldata) internal {
    assembly {
      let success := call(
        gas(),
        sload(mockHookCaller.slot),
        0,
        add(_calldata, 0x20),
        mload(_calldata),
        0,
        0
      )
      if iszero(success) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }

  function prettyPrintBytes(bytes memory data, bool hasSelector) internal {
    uint i;
    if (hasSelector) {
      i = 4;
      uint selector;
      assembly {
        selector := shr(224, mload(add(data, 0x20)))
      }
      console2.log('[0:4]:', selector.toHexString());
    }
    for (; i < data.length; i += 32) {
      uint word;
      assembly {
        word := mload(add(data, add(i, 0x20)))
      }
      uint end = i + 32;
      if (end > data.length) {
        end = data.length;
      }
      string memory prefix = string.concat('[', i.toString(), ':', end.toString(), ']: ');

      console2.log(prefix, word.toHexString());
    }
  }

  function testEncode(StandardHooksConfig memory input) external {
    HooksConfig hooks = input.toHooksConfig();
    assertEq(hooks, input);
  }

  function test_onDeposit(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.deposit.selector, 100),
      extraData
    );
    if (config.useOnDeposit()) {
      vm.expectEmit();
      emit OnDepositCalled(address(this), 100, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnDeposit()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onQueueWithdrawal(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.queueWithdrawal.selector, 100),
      extraData
    );
    if (config.useOnQueueWithdrawal()) {
      vm.expectEmit();
      emit OnQueueWithdrawalCalled(address(this), 100, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnQueueWithdrawal()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onExecuteWithdrawal(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    address lender,
    uint128 normalizedAmountWithdrawn,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(
        mockHookCaller.executeWithdrawal.selector,
        lender,
        normalizedAmountWithdrawn
      ),
      extraData
    );
    if (config.useOnExecuteWithdrawal()) {
      vm.expectEmit();
      emit OnExecuteWithdrawalCalled(lender, normalizedAmountWithdrawn, state, extraData);
    }
    _callMockHookCaller(_calldata);

    if (!config.useOnExecuteWithdrawal()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onTransfer(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    address to,
    uint256 scaledAmount,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);

    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.transfer.selector, to, scaledAmount),
      extraData
    );

    if (config.useOnTransfer()) {
      vm.expectEmit();
      emit OnTransferCalled(address(this), address(this), to, scaledAmount, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnTransfer()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onBorrow(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.borrow.selector, 100),
      extraData
    );
    if (config.useOnBorrow()) {
      vm.expectEmit();
      emit OnBorrowCalled(100, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnBorrow()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onRepay(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.repay.selector, 100),
      extraData
    );
    if (config.useOnRepay()) {
      vm.expectEmit();
      emit OnRepayCalled(100, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnRepay()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onCloseMarket(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.closeMarket.selector),
      extraData
    );
    if (config.useOnCloseMarket()) {
      vm.expectEmit();
      emit OnCloseMarketCalled(state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnCloseMarket()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onAssetsSentToEscrow(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData,
    address lender,
    address asset,
    address escrow,
    uint scaledAmount
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(
        mockHookCaller.sendAssetsToEscrow.selector,
        lender,
        asset,
        escrow,
        scaledAmount
      ),
      extraData
    );
    if (config.useOnAssetsSentToEscrow()) {
      vm.expectEmit();
      emit OnAssetsSentToEscrowCalled(lender, asset, escrow, scaledAmount, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnAssetsSentToEscrow()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onSetMaxTotalSupply(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(mockHookCaller.setMaxTotalSupply.selector, 100),
      extraData
    );
    if (config.useOnSetMaxTotalSupply()) {
      vm.expectEmit();
      emit OnSetMaxTotalSupplyCalled(100, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnSetMaxTotalSupply()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }

  function test_onSetAnnualInterestAndReserveRatioBips(
    StateFuzzInputs memory stateInput,
    StandardHooksConfig memory configInput,
    bytes memory extraData,
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  ) external {
    MarketState memory state = stateInput.toState();
    mockHookCaller.setState(state);
    configInput.hooksAddress = address(hooks);
    HooksConfig config = configInput.toHooksConfig();
    mockHookCaller.setConfig(config);
    bytes memory _calldata = abi.encodePacked(
      abi.encodeWithSelector(
        mockHookCaller.setAnnualInterestAndReserveRatioBips.selector,
        annualInterestBips,
        reserveRatioBips
      ),
      extraData
    );
    if (config.useOnSetAnnualInterestAndReserveRatioBips()) {
      vm.expectEmit();
      emit OnSetAnnualInterestBipsCalled(annualInterestBips, state, extraData);
    }
    _callMockHookCaller(_calldata);
    if (!config.useOnSetAnnualInterestAndReserveRatioBips()) {
      assertEq(hooks.lastCalldataHash(), 0);
    }
  }
}

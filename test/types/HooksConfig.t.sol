// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IHooks } from 'src/access/IHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { HooksConfigCaller } from '../mocks/HooksConfigCaller.sol';
import { HooksConfigTarget } from '../mocks/HooksConfigTarget.sol';
import { TestKernel } from '../shared/TestKernel.sol';
import { StandardHooksConfig, StandardHooksDeploymentConfig } from '../shared/TestStructs.sol';

struct ExecuteWithdrawalInputs {
  address lender;
  uint32 expiry;
  uint128 normalizedAmountWithdrawn;
}

struct AprUpdateInputs {
  uint16 annualInterestBips;
  uint16 reserveRatioBips;
  uint16 annualInterestBipsToReturn;
  uint16 reserveRatioBipsToReturn;
}

contract HooksConfigTest is TestKernel {
  HooksConfigTarget internal hooks;
  HooksConfigCaller internal caller;
  address internal shortReturnHooks;

  function setUp() external {
    hooks = HooksConfigTarget(
      _deployCode('test/mocks/HooksConfigTarget.sol:HooksConfigTarget')
    );
    caller = HooksConfigCaller(
      _deployCode('test/mocks/HooksConfigCaller.sol:HooksConfigCaller')
    );
    shortReturnHooks = _deployCode(
      'test/mocks/HooksConfigTarget.sol:HooksConfigShortReturnTarget'
    );
  }

  function _assertConfig(
    HooksConfig actual,
    StandardHooksConfig memory expected,
    string memory label
  ) internal pure {
    assertEq(actual.hooksAddress(), expected.hooksAddress, string.concat(label, '.hooksAddress'));
    assertEq(actual.useOnDeposit(), expected.useOnDeposit, string.concat(label, '.onDeposit'));
    assertEq(
      actual.useOnQueueWithdrawal(),
      expected.useOnQueueWithdrawal,
      string.concat(label, '.onQueueWithdrawal')
    );
    assertEq(
      actual.useOnExecuteWithdrawal(),
      expected.useOnExecuteWithdrawal,
      string.concat(label, '.onExecuteWithdrawal')
    );
    assertEq(actual.useOnTransfer(), expected.useOnTransfer, string.concat(label, '.onTransfer'));
    assertEq(actual.useOnBorrow(), expected.useOnBorrow, string.concat(label, '.onBorrow'));
    assertEq(actual.useOnRepay(), expected.useOnRepay, string.concat(label, '.onRepay'));
    assertEq(
      actual.useOnCloseMarket(),
      expected.useOnCloseMarket,
      string.concat(label, '.onCloseMarket')
    );
    assertEq(
      actual.useOnNukeFromOrbit(),
      expected.useOnNukeFromOrbit,
      string.concat(label, '.onNukeFromOrbit')
    );
    assertEq(
      actual.useOnSetMaxTotalSupply(),
      expected.useOnSetMaxTotalSupply,
      string.concat(label, '.onSetMaxTotalSupply')
    );
    assertEq(
      actual.useOnSetAnnualInterestAndReserveRatioBips(),
      expected.useOnSetAnnualInterestAndReserveRatioBips,
      string.concat(label, '.onSetAnnualInterestAndReserveRatioBips')
    );
    assertEq(
      actual.useOnSetProtocolFeeBips(),
      expected.useOnSetProtocolFeeBips,
      string.concat(label, '.onSetProtocolFeeBips')
    );
    assertEq(
      actual.useOnExecutePendingAnnualInterestBipsReduction(),
      expected.useOnExecutePendingAnnualInterestBipsReduction,
      string.concat(label, '.onExecutePendingAnnualInterestBipsReduction')
    );
  }

  function _configure(
    MarketState calldata state,
    StandardHooksConfig memory configInput
  ) internal returns (HooksConfig config) {
    caller.setState(state);
    configInput.hooksAddress = address(hooks);
    config = configInput.toHooksConfig();
    caller.setConfig(config);
  }

  function _call(bytes memory callData) internal returns (bytes memory returnData) {
    bool success;
    (success, returnData) = address(caller).call(callData);
    if (!success) {
      assembly {
        revert(add(returnData, 0x20), mload(returnData))
      }
    }
  }

  function _assertHookCall(
    bool enabled,
    bytes memory expectedCalldata,
    uint256 extraDataLength
  ) internal view {
    // LibHooksConfig sends the dynamic bytes without ABI tail padding. Trim the
    // canonical encoding to the exact payload length before comparing it.
    uint256 trailingPadding = (32 - (extraDataLength % 32)) % 32;
    assembly {
      mstore(expectedCalldata, sub(mload(expectedCalldata), trailingPadding))
    }
    assertEq(
      hooks.lastCalldataHash(),
      enabled ? keccak256(expectedCalldata) : bytes32(0),
      enabled ? 'wrong hook calldata' : 'disabled hook was called'
    );
  }

  function testEncode(StandardHooksConfig memory input) external pure {
    _assertConfig(input.toHooksConfig(), input, 'encoded');
  }

  function test_mergeSharedFlags(
    StandardHooksConfig memory aInput,
    StandardHooksConfig memory bInput
  ) external pure {
    StandardHooksConfig memory expected = aInput.mergeSharedFlags(bInput);
    _assertConfig(
      aInput.toHooksConfig().mergeSharedFlags(bInput.toHooksConfig()),
      expected,
      'merged'
    );
  }

  function test_encodeHooksDeploymentConfig(
    StandardHooksDeploymentConfig memory deploymentFlags
  ) external pure {
    deploymentFlags.optional.hooksAddress = address(0);
    deploymentFlags.required.hooksAddress = address(0);
    HooksConfig optional = deploymentFlags.optional.toHooksConfig();
    HooksConfig required = deploymentFlags.required.toHooksConfig();
    HooksDeploymentConfig encoded = encodeHooksDeploymentConfig(optional, required);
    assertEq(HooksConfig.unwrap(encoded.optionalFlags()), HooksConfig.unwrap(optional), 'optional');
    assertEq(HooksConfig.unwrap(encoded.requiredFlags()), HooksConfig.unwrap(required), 'required');
  }

  function test_mergeFlags(
    StandardHooksConfig memory configInput,
    StandardHooksDeploymentConfig memory deploymentFlags
  ) external pure {
    StandardHooksConfig memory expected = configInput.mergeFlags(deploymentFlags);
    HooksDeploymentConfig encoded = deploymentFlags.toHooksDeploymentConfig();
    _assertConfig(configInput.toHooksConfig().mergeFlags(encoded), expected, 'merged');
  }

  function test_configUtilities(
    uint256 aRaw,
    uint256 bRaw,
    address newHooksAddress,
    uint256 bit
  ) external pure {
    uint256 flagMask = type(uint96).max;
    HooksConfig a = HooksConfig.wrap(aRaw);
    HooksConfig b = HooksConfig.wrap(bRaw);

    HooksConfig withNewAddress = a.setHooksAddress(newHooksAddress);
    assertEq(
      HooksConfig.unwrap(withNewAddress),
      (aRaw & flagMask) | (uint256(uint160(newHooksAddress)) << 96),
      'setHooksAddress'
    );

    HooksConfig merged = a.mergeAllFlags(b);
    assertEq(
      HooksConfig.unwrap(merged),
      (aRaw & ~flagMask) | ((aRaw | bRaw) & flagMask),
      'mergeAllFlags'
    );

    bit = bound(bit, 0, 95);
    HooksConfig flagged = a.setFlag(bit);
    assertTrue(flagged.readFlag(bit), 'setFlag/readFlag');
    assertEq(
      HooksConfig.unwrap(flagged),
      aRaw | (uint256(1) << bit),
      'setFlag changed another bit'
    );

    HooksConfig cleared = flagged.clearFlag(bit);
    assertFalse(cleared.readFlag(bit), 'clearFlag/readFlag');
    assertEq(
      HooksConfig.unwrap(cleared),
      aRaw & ~(uint256(1) << bit),
      'clearFlag changed another bit'
    );
  }

  function test_hookRevertBubbles(MarketState calldata state) external {
    StandardHooksConfig memory configInput;
    configInput.useOnDeposit = true;
    _configure(state, configInput);
    hooks.setShouldRevert(true);

    vm.expectRevert(HooksConfigTarget.ForcedRevert.selector);
    caller.deposit(100);
  }

  function test_aprHookRejectsShortReturnData(MarketState calldata state) external {
    StandardHooksConfig memory configInput;
    configInput.hooksAddress = shortReturnHooks;
    configInput.useOnSetAnnualInterestAndReserveRatioBips = true;
    caller.setState(state);
    caller.setConfig(configInput.toHooksConfig());

    vm.expectRevert();
    caller.setAnnualInterestAndReserveRatioBips(100, 200);
  }

  function test_onDeposit(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(abi.encodePacked(abi.encodeWithSelector(caller.deposit.selector, 100), extraData));
    _assertHookCall(
      config.useOnDeposit(),
      abi.encodeWithSelector(IHooks.onDeposit.selector, address(this), 100, state, extraData),
      extraData.length
    );
  }

  function test_onQueueWithdrawal(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    uint256 scaledAmount,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    uint32 expiry = uint32(getTimestamp() + 1 days);
    _call(
      abi.encodePacked(
        abi.encodeWithSelector(caller.queueWithdrawal.selector, expiry, scaledAmount),
        extraData
      )
    );
    _assertHookCall(
      config.useOnQueueWithdrawal(),
      abi.encodeWithSelector(
        IHooks.onQueueWithdrawal.selector,
        address(this),
        expiry,
        scaledAmount,
        state,
        extraData
      ),
      extraData.length
    );
  }

  function test_onExecuteWithdrawal(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    ExecuteWithdrawalInputs calldata inputs,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(
      abi.encodePacked(
        abi.encodeWithSelector(
          caller.executeWithdrawal.selector,
          inputs.lender,
          inputs.expiry,
          inputs.normalizedAmountWithdrawn
        ),
        extraData
      )
    );
    _assertHookCall(
      config.useOnExecuteWithdrawal(),
      abi.encodeWithSelector(
        IHooks.onExecuteWithdrawal.selector,
        inputs.lender,
        inputs.expiry,
        inputs.normalizedAmountWithdrawn,
        state,
        extraData
      ),
      extraData.length
    );
  }

  function test_onTransfer(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    address to,
    uint256 scaledAmount,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(
      abi.encodePacked(
        abi.encodeWithSelector(caller.transfer.selector, to, scaledAmount),
        extraData
      )
    );
    _assertHookCall(
      config.useOnTransfer(),
      abi.encodeWithSelector(
        IHooks.onTransfer.selector,
        address(this),
        address(this),
        to,
        scaledAmount,
        state,
        extraData
      ),
      extraData.length
    );
  }

  function test_onBorrow(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(abi.encodePacked(abi.encodeWithSelector(caller.borrow.selector, 100), extraData));
    _assertHookCall(
      config.useOnBorrow(),
      abi.encodeWithSelector(IHooks.onBorrow.selector, 100, state, extraData),
      extraData.length
    );
  }

  function test_onRepay(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(abi.encodePacked(abi.encodeWithSelector(caller.repay.selector, 100), extraData));
    _assertHookCall(
      config.useOnRepay(),
      abi.encodeWithSelector(IHooks.onRepay.selector, 100, state, extraData),
      extraData.length
    );
  }

  function test_onCloseMarket(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(abi.encodePacked(abi.encodeWithSelector(caller.closeMarket.selector), extraData));
    _assertHookCall(
      config.useOnCloseMarket(),
      abi.encodeWithSelector(IHooks.onCloseMarket.selector, state, extraData),
      extraData.length
    );
  }

  function test_onNukeFromOrbit(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData,
    address lender
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(
      abi.encodePacked(abi.encodeWithSelector(caller.nukeFromOrbit.selector, lender), extraData)
    );
    _assertHookCall(
      config.useOnNukeFromOrbit(),
      abi.encodeWithSelector(IHooks.onNukeFromOrbit.selector, lender, state, extraData),
      extraData.length
    );
  }

  function test_onSetMaxTotalSupply(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(
      abi.encodePacked(abi.encodeWithSelector(caller.setMaxTotalSupply.selector, 100), extraData)
    );
    _assertHookCall(
      config.useOnSetMaxTotalSupply(),
      abi.encodeWithSelector(IHooks.onSetMaxTotalSupply.selector, 100, state, extraData),
      extraData.length
    );
  }

  function test_onSetAnnualInterestAndReserveRatioBips(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData,
    AprUpdateInputs calldata inputs
  ) external {
    hooks.setAnnualInterestAndReserveRatioBips(
      inputs.annualInterestBipsToReturn,
      inputs.reserveRatioBipsToReturn
    );
    HooksConfig config = _configure(state, configInput);
    bytes memory returnData = _call(
      abi.encodePacked(
        abi.encodeWithSelector(
          caller.setAnnualInterestAndReserveRatioBips.selector,
          inputs.annualInterestBips,
          inputs.reserveRatioBips
        ),
        extraData
      )
    );
    _assertHookCall(
      config.useOnSetAnnualInterestAndReserveRatioBips(),
      abi.encodeWithSelector(
        IHooks.onSetAnnualInterestAndReserveRatioBips.selector,
        inputs.annualInterestBips,
        inputs.reserveRatioBips,
        state,
        extraData
      ),
      extraData.length
    );
    (uint16 returnedAnnualInterestBips, uint16 returnedReserveRatioBips) = abi.decode(
      returnData,
      (uint16, uint16)
    );
    assertEq(
      returnedAnnualInterestBips,
      config.useOnSetAnnualInterestAndReserveRatioBips()
        ? inputs.annualInterestBipsToReturn
        : inputs.annualInterestBips,
      'annual interest return'
    );
    assertEq(
      returnedReserveRatioBips,
      config.useOnSetAnnualInterestAndReserveRatioBips()
        ? inputs.reserveRatioBipsToReturn
        : inputs.reserveRatioBips,
      'reserve ratio return'
    );
  }

  function test_onSetProtocolFeeBips(
    MarketState calldata state,
    StandardHooksConfig memory configInput,
    bytes calldata extraData
  ) external {
    HooksConfig config = _configure(state, configInput);
    _call(
      abi.encodePacked(abi.encodeWithSelector(caller.setProtocolFeeBips.selector, 100), extraData)
    );
    _assertHookCall(
      config.useOnSetProtocolFeeBips(),
      abi.encodeWithSelector(IHooks.onSetProtocolFeeBips.selector, 100, state, extraData),
      extraData.length
    );
  }
}

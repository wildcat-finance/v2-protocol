// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IHooks } from 'src/access/IHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { Bit_Enabled_Deposit, EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_ExecutePendingAnnualInterestBipsReduction } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_SetAnnualInterestAndReserveRatioBips } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig, encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';

contract ProtocolFeeReadOnDepositHooks is IHooks {
  bool public protocolFeeReadSucceeded;
  uint128 public protocolFeeReadValue;
  bytes4 public protocolFeeReadRevertSelector;

  function version() external pure override returns (string memory) {
    return 'ProtocolFeeReadOnDepositHooks';
  }

  function config() public pure override returns (HooksDeploymentConfig) {
    return
      encodeHooksDeploymentConfig(EmptyHooksConfig.setFlag(Bit_Enabled_Deposit), EmptyHooksConfig);
  }

  function _onCreateMarket(
    address,
    address,
    DeployMarketInputs calldata parameters,
    bytes calldata
  ) internal pure override returns (HooksConfig) {
    return parameters.hooks.mergeFlags(config());
  }

  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override {
    (bool success, bytes memory data) = msg.sender.staticcall(
      abi.encodeWithSignature('withdrawableProtocolFees()')
    );
    protocolFeeReadSucceeded = success;
    if (success && data.length >= 32) {
      protocolFeeReadValue = abi.decode(data, (uint128));
    } else if (data.length >= 4) {
      bytes4 selector;
      assembly {
        selector := mload(add(data, 0x20))
      }
      protocolFeeReadRevertSelector = selector;
    }
  }

  function onQueueWithdrawal(
    address,
    uint32,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onExecuteWithdrawal(
    address,
    uint32,
    uint128,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onTransfer(
    address,
    address,
    address,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onBorrow(uint256, MarketState calldata, bytes calldata) external override {}

  function onRepay(uint256, MarketState calldata, bytes calldata) external override {}

  function onCloseMarket(MarketState calldata, bytes calldata) external override {}

  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override {}

  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override {}

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  ) external pure override returns (uint16, uint16) {
    return (annualInterestBips, reserveRatioBips);
  }

  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override {}
}

contract MarketConfigHooks is IHooks {
  bool private _replaceAprAndReserveRatio;
  uint16 private _annualInterestBips;
  uint16 private _reserveRatioBips;

  uint16 public pendingAnnualInterestBipsReduction;
  uint16 public lastIntermediateAnnualInterestBips;
  uint16 public lastIntermediateReserveRatioBips;

  function version() external pure override returns (string memory) {
    return 'MarketConfigHooks';
  }

  function config() public pure override returns (HooksDeploymentConfig) {
    return
      encodeHooksDeploymentConfig(
        EmptyHooksConfig,
        EmptyHooksConfig.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips).setFlag(
          Bit_Enabled_ExecutePendingAnnualInterestBipsReduction
        )
      );
  }

  function _onCreateMarket(
    address,
    address,
    DeployMarketInputs calldata parameters,
    bytes calldata
  ) internal pure override returns (HooksConfig) {
    return parameters.hooks.mergeFlags(config());
  }

  function setAprAndReserveRatioReturn(
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  ) external {
    _replaceAprAndReserveRatio = true;
    _annualInterestBips = annualInterestBips;
    _reserveRatioBips = reserveRatioBips;
  }

  function setPendingAnnualInterestBipsReduction(uint16 annualInterestBips) external {
    pendingAnnualInterestBipsReduction = annualInterestBips;
  }

  function executePendingAnnualInterestBipsReduction(
    MarketState calldata intermediateState
  ) external returns (uint16 annualInterestBips) {
    lastIntermediateAnnualInterestBips = intermediateState.annualInterestBips;
    lastIntermediateReserveRatioBips = intermediateState.reserveRatioBips;
    return pendingAnnualInterestBipsReduction;
  }

  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override {}

  function onQueueWithdrawal(
    address,
    uint32,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onExecuteWithdrawal(
    address,
    uint32,
    uint128,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onTransfer(
    address,
    address,
    address,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onBorrow(uint256, MarketState calldata, bytes calldata) external override {}

  function onRepay(uint256, MarketState calldata, bytes calldata) external override {}

  function onCloseMarket(MarketState calldata, bytes calldata) external override {}

  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override {}

  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override {}

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  ) external view override returns (uint16, uint16) {
    if (_replaceAprAndReserveRatio) return (_annualInterestBips, _reserveRatioBips);
    return (annualInterestBips, reserveRatioBips);
  }

  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override {}
}

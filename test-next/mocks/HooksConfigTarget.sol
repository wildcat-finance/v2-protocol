// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';

/// @dev Records the exact calldata produced by LibHooksConfig. Keeping this as
///      an artifact-deployed target avoids embedding its creation code in the
///      test contract that exercises every hook path.
contract HooksConfigTarget is IHooks {
  error ForcedRevert();

  bytes32 public lastCalldataHash;
  uint16 public annualInterestBipsToReturn;
  uint16 public reserveRatioBipsToReturn;
  bool public shouldRevert;

  function version() external pure override returns (string memory) {
    return 'test-next-hooks';
  }

  function config() external pure override returns (HooksDeploymentConfig) {
    return encodeHooksDeploymentConfig(EmptyHooksConfig, EmptyHooksConfig);
  }

  function setAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  ) external {
    annualInterestBipsToReturn = annualInterestBips;
    reserveRatioBipsToReturn = reserveRatioBips;
  }

  function setShouldRevert(bool value) external {
    shouldRevert = value;
  }

  function _onCreateMarket(
    address,
    address,
    DeployMarketInputs calldata parameters,
    bytes calldata
  ) internal pure override returns (HooksConfig) {
    return parameters.hooks;
  }

  function _recordCall() private {
    if (shouldRevert) revert ForcedRevert();
    lastCalldataHash = keccak256(msg.data);
  }

  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  function onQueueWithdrawal(
    address,
    uint32,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {
    _recordCall();
  }

  function onExecuteWithdrawal(
    address,
    uint32,
    uint128,
    MarketState calldata,
    bytes calldata
  ) external override {
    _recordCall();
  }

  function onTransfer(
    address,
    address,
    address,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {
    _recordCall();
  }

  function onBorrow(uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  function onRepay(uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  function onCloseMarket(MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override {
    _recordCall();
  }

  function onSetAnnualInterestAndReserveRatioBips(
    uint16,
    uint16,
    MarketState calldata,
    bytes calldata
  ) external override returns (uint16, uint16) {
    _recordCall();
    return (annualInterestBipsToReturn, reserveRatioBipsToReturn);
  }

  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override {
    _recordCall();
  }
}

contract HooksConfigShortReturnTarget {
  fallback() external {}
}

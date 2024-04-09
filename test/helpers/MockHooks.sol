// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IHooks.sol';

contract MockHooks is IHooks {
  HooksConfig public override config;

  /// @dev Returns the version string of the hooks contract.
  ///      Used to determine what the contract does and how `extraData` is interpreted.
  function version() external view override returns (string memory) {
    return 'mock';
  }

  function setConfig(HooksConfig _config) external {
    config = _config;
  }

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onQueueWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onExecuteWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onTransfer(
    address from,
    address to,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external override {}

  function onBorrow(uint normalizedAmount, bytes calldata extraData) external override {}

  function onRepay(uint normalizedAmount, bytes calldata extraData) external override {}

  function onCloseMarket(bytes calldata extraData) external override {}

  function onAssetsSentToEscrow(
    address lender,
    address escrow,
    uint scaledAmount,
    bytes calldata extraData
  ) external override {}

  function onSetMaxTotalSupply(bytes calldata extraData) external override {}

  function onSetAnnualInterestBips(bytes calldata extraData) external override {}
}

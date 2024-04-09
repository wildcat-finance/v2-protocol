// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../types/HooksConfig.sol';

abstract contract IHooks {
  /// @dev Returns the version string of the hooks contract.
  ///      Used to determine what the contract does and how `extraData` is interpreted.
  function version() external view virtual returns (string memory);

  function config() external view virtual returns (HooksConfig);

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onQueueWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onExecuteWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onTransfer(
    address from,
    address to,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onBorrow(uint normalizedAmount, bytes calldata extraData) external virtual;

  function onRepay(uint normalizedAmount, bytes calldata extraData) external virtual;

  function onCloseMarket(bytes calldata extraData) external virtual;

  function onAssetsSentToEscrow(
    address lender,
    address escrow,
    uint scaledAmount,
    bytes calldata extraData
  ) external virtual;

  function onSetMaxTotalSupply(bytes calldata extraData) external virtual;

  function onSetAnnualInterestBips(bytes calldata extraData) external virtual;
}

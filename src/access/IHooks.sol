// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import '../types/HooksConfig.sol';
import '../libraries/MarketState.sol';
import '../interfaces/IWildcatMarketControllerFactory.sol';

abstract contract IHooks {
  error CallerNotFactory();

  address public immutable factory;

  constructor() {
    factory = msg.sender;
  }

  /// @dev Returns the version string of the hooks contract.
  ///      Used to determine what the contract does and how `extraData` is interpreted.
  function version() external view virtual returns (string memory);

  /// @dev Returns the HooksConfig for the hooks contract, specifying which hooks
  ///      should be invoked by markets using it.
  function config() external view virtual returns (HooksConfig);

  function onCreateMarket(MarketParameters calldata parameters, bytes calldata extraData) external {
    if (msg.sender != factory) revert CallerNotFactory();
    _onCreateMarket(parameters, extraData);
  }

  function _onCreateMarket(
    MarketParameters calldata parameters,
    bytes calldata extraData
  ) internal virtual;

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onQueueWithdrawal(
    address lender,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onExecuteWithdrawal(
    address lender,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onRepay(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onCloseMarket(
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onAssetsSentToEscrow(
    address lender,
    address asset,
    address escrow,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  function onSetAnnualInterestBips(
    uint16 annualInterestBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;
}

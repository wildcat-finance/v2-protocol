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

  function _onCreateMarket(
    MarketParameters calldata parameters,
    bytes calldata extraData
  ) internal virtual override {}

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onQueueWithdrawal(
    address lender,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onExecuteWithdrawal(
    address lender,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onRepay(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onCloseMarket(
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onAssetsSentToEscrow(
    address lender,
    address asset,
    address escrow,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}

  function onSetAnnualInterestBips(
    uint16 annualInterestBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {}
}

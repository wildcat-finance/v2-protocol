// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../types/HooksConfig.sol';
import '../libraries/MarketState.sol';
import '../interfaces/WildcatStructsAndEnums.sol';

abstract contract IHooks {
  error CallerNotFactory();

  address public immutable factory;

  constructor() {
    factory = msg.sender;
  }

  /// @dev Returns the version string of the hooks contract.
  ///      Used to determine what the contract does and how `extraData` is interpreted.
  function version() external view virtual returns (string memory);

  /// @dev Returns the HooksDeploymentConfig type which contains the sets
  ///      of optional and required hooks that this contract implements.
  function config() external view virtual returns (HooksDeploymentConfig);

  /// @dev Factory-only hook called before deploying a market with this hooks contract.
  ///      `administrator` is the principal authorized to configure this hooks instance.
  ///      Reverts if caller is not the factory.
  ///      Returns the hooks config to store on the market.
  function onCreateMarket(
    address administrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata extraData
  ) external returns (HooksConfig) {
    if (msg.sender != factory) revert CallerNotFactory();
    return _onCreateMarket(administrator, marketAddress, parameters, extraData);
  }

  function _onCreateMarket(
    address administrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata extraData
  ) internal virtual returns (HooksConfig);

  /// @dev Market hook called before accepting a lender deposit.
  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before queueing a lender withdrawal.
  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before executing a lender withdrawal from the batch keyed by `expiry`.
  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before transferring market tokens.
  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before the borrower withdraws assets.
  function onBorrow(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called after repayment assets are received.
  function onRepay(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before closing the market.
  function onCloseMarket(
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before queueing a sanctioned lender's balance for withdrawal.
  function onNukeFromOrbit(
    address lender,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before updating max total supply.
  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual;

  /// @dev Market hook called before updating APR and reserve ratio.
  ///      Returns the values the market should apply.
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips);

  /// @dev Market hook called before updating protocol fee bips.
  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState memory intermediateState,
    bytes calldata extraData
  ) external virtual;
}

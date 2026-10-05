// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IHooks
//  \ ^ /   Factory-authenticated creation and market callback surface.
//    V
//
//  SETUP
//  constructor()
//  onCreateMarket(...)
//  _onCreateMarket(...)
//
//  METADATA
//  version()
//  config()
//
//  DEPOSITS
//  onDeposit(...)
//
//  TRANSFERS
//  onTransfer(...)
//
//  BORROWING
//  onBorrow(...)
//
//  REPAYMENT
//  onRepay(...)
//
//  WITHDRAWAL QUEUEING
//  onQueueWithdrawal(...)
//
//  CLAIM COLLECTION
//  onExecuteWithdrawal(...)
//
//  CLOSURE
//  onCloseMarket(...)
//
//  SANCTIONS
//  onNukeFromOrbit(...)
//
//  SUPPLY CAPACITY
//  onSetMaxTotalSupply(...)
//
//  INTEREST AND RESERVES
//  onSetAnnualInterestAndReserveRatioBips(...)
//
//  PROTOCOL FEES
//  onSetProtocolFeeBips(...)
// ═════

import '../types/HooksConfig.sol';
import '../libraries/MarketState.sol';
import '../interfaces/WildcatStructsAndEnums.sol';

// ┌─ IHooks ───────────────────────────────────────────────────────────────────
/// @notice callback surface bound to a market through its immutable `HooksConfig`.
///
/// @dev the factory authenticates market creation here. ordinary callbacks are external, so each
///      implementation is responsible for whatever caller checks its state changes need.
abstract contract IHooks {
  /// @dev a market-creation callback came from somewhere other than this instance's factory.
  error CallerNotFactory();

  /// @notice factory that deployed this hooks instance.
  address public immutable factory;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() {
    factory = msg.sender;
  }

  // ┌─ onCreateMarket ─────
  /// @notice validate a market deployment and return the callbacks the market should store.
  ///
  /// @dev only the creating factory can call this. the factory calls the hook before attempting
  ///      market deployment.
  ///
  /// @param administrator principal resolved by the factory for this deployment.
  /// @param marketAddress address where the market will be deployed.
  /// @param parameters    market parameters proposed to the factory.
  /// @param extraData     template-specific market configuration.
  ///
  /// @return final hooks address and callback flags for the market.
  function onCreateMarket(
    address administrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata extraData
  )
    external
    returns (HooksConfig)
  {
    if (msg.sender != factory) revert CallerNotFactory();
    return _onCreateMarket(administrator, marketAddress, parameters, extraData);
  }

  // ┌─ _onCreateMarket ─────
  function _onCreateMarket(
    address administrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata extraData
  )
    internal
    virtual
    returns (HooksConfig);

  // ░░▒▒▓▓██ [ METADATA ] ─────────────────────────────────────────────────────

  // ┌─ version ─────
  /// @notice return the template's integration-facing version string.
  ///
  /// @dev this is metadata, not implementation identity. it also tells callers how to interpret
  ///      `extraData` for templates that give the string that meaning.
  function version() external view virtual returns (string memory);

  // ┌─ config ─────
  /// @notice return the optional and required callbacks supported by this template.
  function config() external view virtual returns (HooksDeploymentConfig);

  // ░░▒▒▓▓██ [ DEPOSITS ] ─────────────────────────────────────────────────────

  // ┌─ onDeposit ─────
  /// @notice called before the market accepts a deposit.
  ///
  /// @param scaledAmount      amount of market-token shares that the deposit would mint.
  /// @param intermediateState market state after its pre-action update and before the deposit.
  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ TRANSFERS ] ────────────────────────────────────────────────────

  // ┌─ onTransfer ─────
  /// @notice called before market-token balances change.
  ///
  /// @param caller       account that initiated the transfer. this may differ from `from`.
  /// @param scaledAmount amount of shares that would move.
  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ BORROWING ] ────────────────────────────────────────────────────

  // ┌─ onBorrow ─────
  /// @notice called before borrowed assets leave the market.
  function onBorrow(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ REPAYMENT ] ────────────────────────────────────────────────────

  // ┌─ onRepay ─────
  /// @notice called after repayment assets arrive and before repayment accounting is applied.
  function onRepay(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ WITHDRAWAL QUEUEING ] ──────────────────────────────────────────

  // ┌─ onQueueWithdrawal ─────
  /// @notice called before the market adds a lender's shares to a withdrawal batch.
  ///
  /// @dev the market bypasses this callback from an enabled repayment date.
  ///
  /// @param expiry            exact batch expiry selected by the market.
  /// @param scaledAmount      amount of shares that would be queued.
  /// @param intermediateState state before the new request is added to batch totals.
  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ CLAIM COLLECTION ] ─────────────────────────────────────────────

  // ┌─ onExecuteWithdrawal ─────
  /// @notice compatibility callback for collecting a claim from the batch keyed by `expiry`.
  ///
  /// @dev v2.5 markets reject the execute-withdrawal flag and never call this callback.
  ///      `expiry` is the batch being claimed. don't infer it from the current pending batch in
  ///      `intermediateState`.
  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ CLOSURE ] ──────────────────────────────────────────────────────

  // ┌─ onCloseMarket ─────
  /// @notice called before the borrower explicitly closes the market.
  ///
  /// @dev if closure needs a final repayment, the market calls `onRepay` first.
  ///      automatic closure from an enabled repayment date bypasses this callback.
  function onCloseMarket(MarketState calldata intermediateState, bytes calldata extraData) external virtual;

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  // ┌─ onNukeFromOrbit ─────
  /// @notice called before a sanctioned lender's full balance is queued for withdrawal.
  ///
  /// @dev queueing then uses `onQueueWithdrawal`, so term policy can still block it before an
  ///      enabled repayment date. from that date, the market bypasses the queue callback.
  function onNukeFromOrbit(
    address lender,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ SUPPLY CAPACITY ] ──────────────────────────────────────────────

  // ┌─ onSetMaxTotalSupply ─────
  /// @notice called before the market updates its maximum total supply.
  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual;

  // ░░▒▒▓▓██ [ INTEREST AND RESERVES ] ────────────────────────────────────────

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  /// @notice constrain an APR and reserve-ratio update before the market applies it.
  ///
  /// @return updatedAnnualInterestBips APR the market should apply.
  /// @return updatedReserveRatioBips reserve ratio the market should apply.
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips);

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  // ┌─ onSetProtocolFeeBips ─────
  /// @notice called before the market applies a factory-supplied protocol fee.
  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState memory intermediateState,
    bytes calldata extraData
  )
    external
    virtual;
}

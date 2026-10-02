// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IMarketLensCore
//  \ ^ /   Core query surface for tokens, markets, lenders, and claims.
//    V
//
//  TOKEN METADATA
//  getTokenInfo(...)
//  getTokensInfo(...)
//
//  MARKET DATA
//  getMarketData(...)
//  getMarketsData(...)
//  getMarketDataV2(...)
//  getMarketsDataV2(...)
//
//  LENDER DATA
//  getMarketDataWithLenderStatus(...)
//  getMarketsDataWithLenderStatus(...)
//  getLenderAccountData(...)
//  getLenderAccountData(...)
//  getLenderAccountsData(...)
//  queryLenderAccount(...)
//  queryLenderAccounts(...)
//
//  WITHDRAWAL BATCHES
//  getWithdrawalBatchData(...)
//  getWithdrawalBatchesData(...)
//  getWithdrawalBatchDataWithLenderStatus(...)
//  getWithdrawalBatchesDataWithLenderStatus(...)
//  getWithdrawalBatchDataWithLendersStatus(...)
// ═════

import '../LenderAccountData.sol';
import '../MarketData.sol';
import '../TokenData.sol';
import '../WithdrawalBatchData.sol';

// ┌─ IMarketLensCore ──────────────────────────────────────────────────────────
/// @title core market lens reads
///
/// @notice strict, non-aggregated reads for tokens, markets, lenders, and withdrawal batches.
///
/// @dev batch calls preserve input order and revert as a unit if any required dependency read
///      fails.
interface IMarketLensCore {
  // ░░▒▒▓▓██ [ TOKEN METADATA ] ───────────────────────────────────────────────

  // ┌─ getTokenInfo ─────
  /// @notice return strict decimals, best-effort cosmetic labels and the optional mock marker.
  ///
  /// @dev a zero token returns an empty struct. failed cosmetic reads yield empty
  ///      text; malformed or unavailable decimals still revert.
  function getTokenInfo(address token) external view returns (TokenMetadata memory info);

  // ┌─ getTokensInfo ─────
  /// @notice return token metadata in input order.
  function getTokensInfo(address[] calldata tokens) external view returns (TokenMetadata[] memory infos);

  // ░░▒▒▓▓██ [ MARKET DATA ] ──────────────────────────────────────────────────

  // ┌─ getMarketData ─────
  /// @notice return common V2 market data using this lens deployment's return ABI.
  ///
  /// @dev reverts with `NotV2Market` unless `version()` begins with `2`.
  function getMarketData(address market) external view returns (MarketData memory data);

  // ┌─ getMarketsData ─────
  /// @notice return common V2 market data in input order.
  function getMarketsData(address[] calldata markets) external view returns (MarketData[] memory data);

  // ┌─ getMarketDataV2 ─────
  /// @notice return V2.5 identity, lifecycle, liquidity, wrapper, and optional revolving fields.
  function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data);

  // ┌─ getMarketsDataV2 ─────
  /// @notice return V2.5 tuples in market input order.
  function getMarketsDataV2(address[] calldata markets) external view returns (MarketDataV2_5[] memory data);

  // ░░▒▒▓▓██ [ LENDER DATA ] ──────────────────────────────────────────────────

  // ┌─ getMarketDataWithLenderStatus ─────
  /// @notice return full market data and one lender's state.
  function getMarketDataWithLenderStatus(
    address lender,
    address market
  )
    external
    view
    returns (MarketDataWithLenderStatus memory data);

  // ┌─ getMarketsDataWithLenderStatus ─────
  /// @notice return full market and lender data in market input order.
  function getMarketsDataWithLenderStatus(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (MarketDataWithLenderStatus[] memory data);

  // ┌─ getLenderAccountData ─────
  /// @notice return one lender's balances, allowance, and access state in `market`.
  function getLenderAccountData(address lender, address market) external view returns (LenderAccountData memory data);

  // ┌─ getLenderAccountData ─────
  /// @notice return one lender's account data in market input order.
  function getLenderAccountData(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (LenderAccountData[] memory data);

  // ┌─ getLenderAccountsData ─────
  /// @notice return account data for each lender in one market, preserving input order.
  function getLenderAccountsData(
    address marketAddress,
    address[] calldata lenders
  )
    external
    view
    returns (LenderAccountData[] memory data);

  // ┌─ queryLenderAccount ─────
  /// @notice execute one combined market, lender, and withdrawal-batch query.
  function queryLenderAccount(LenderAccountQuery calldata query)
    external
    view
    returns (LenderAccountQueryResult memory result);

  // ┌─ queryLenderAccounts ─────
  /// @notice execute combined lender queries in input order.
  function queryLenderAccounts(LenderAccountQuery[] calldata queries)
    external
    view
    returns (LenderAccountQueryResult[] memory results);

  // ░░▒▒▓▓██ [ WITHDRAWAL BATCHES ] ───────────────────────────────────────────

  // ┌─ getWithdrawalBatchData ─────
  /// @notice return aggregate data for one withdrawal expiry.
  ///
  /// @dev unknown expiries return the market's empty batch representation.
  function getWithdrawalBatchData(address market, uint32 expiry) external view returns (WithdrawalBatchData memory data);

  // ┌─ getWithdrawalBatchesData ─────
  /// @notice return aggregate batch data in expiry input order.
  function getWithdrawalBatchesData(
    address market,
    uint32[] calldata expiries
  )
    external
    view
    returns (WithdrawalBatchData[] memory data);

  // ┌─ getWithdrawalBatchDataWithLenderStatus ─────
  /// @notice return one withdrawal batch and one lender's status in it.
  function getWithdrawalBatchDataWithLenderStatus(
    address market,
    uint32 expiry,
    address lender
  )
    external
    view
    returns (WithdrawalBatchDataWithLenderStatus memory data);

  // ┌─ getWithdrawalBatchesDataWithLenderStatus ─────
  /// @notice return batch and lender status for each expiry in input order.
  function getWithdrawalBatchesDataWithLenderStatus(
    address market,
    uint32[] calldata expiries,
    address lender
  )
    external
    view
    returns (WithdrawalBatchDataWithLenderStatus[] memory data);

  // ┌─ getWithdrawalBatchDataWithLendersStatus ─────
  /// @notice return one batch plus status for each lender in input order.
  function getWithdrawalBatchDataWithLendersStatus(
    address market,
    uint32 expiry,
    address[] calldata lenders
  )
    external
    view
    returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses);
}

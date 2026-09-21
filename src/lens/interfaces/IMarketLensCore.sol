// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../LenderAccountData.sol';
import '../MarketData.sol';
import '../TokenData.sol';
import '../WithdrawalBatchData.sol';

/// @title core market lens reads
/// @notice strict, non-aggregated reads for tokens, markets, lenders, and withdrawal batches.
/// @dev batch calls preserve input order and revert as a unit if any required dependency read
///      fails.
interface IMarketLensCore {
  /// @notice returns required ERC-20 metadata plus the optional mock marker.
  /// @dev a zero token returns an empty struct; malformed required metadata reverts.
  function getTokenInfo(address token) external view returns (TokenMetadata memory info);

  /// @notice returns token metadata in input order.
  function getTokensInfo(
    address[] calldata tokens
  ) external view returns (TokenMetadata[] memory infos);

  /// @notice returns the stable V2 compatibility tuple for `market`.
  /// @dev reverts with `NotV2Market` unless `version()` begins with `2`.
  function getMarketData(address market) external view returns (MarketData memory data);

  /// @notice returns stable V2 compatibility tuples in market input order.
  function getMarketsData(
    address[] calldata markets
  ) external view returns (MarketData[] memory data);

  /// @notice returns the V2.5 tuple, including borrower identity and optional revolving fields.
  function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data);

  /// @notice returns V2.5 tuples in market input order.
  function getMarketsDataV2(
    address[] calldata markets
  ) external view returns (MarketDataV2_5[] memory data);

  /// @notice returns full market data and one lender's state.
  function getMarketDataWithLenderStatus(
    address lender,
    address market
  ) external view returns (MarketDataWithLenderStatus memory data);

  /// @notice returns full market and lender data in market input order.
  function getMarketsDataWithLenderStatus(
    address lender,
    address[] calldata markets
  ) external view returns (MarketDataWithLenderStatus[] memory data);

  /// @notice returns one lender's balances, allowance, and access state in `market`.
  function getLenderAccountData(
    address lender,
    address market
  ) external view returns (LenderAccountData memory data);

  /// @notice returns one lender's account data in market input order.
  function getLenderAccountData(
    address lender,
    address[] calldata markets
  ) external view returns (LenderAccountData[] memory data);

  /// @notice returns account data for each lender in one market, preserving input order.
  function getLenderAccountsData(
    address marketAddress,
    address[] calldata lenders
  ) external view returns (LenderAccountData[] memory data);

  /// @notice executes one combined market, lender, and withdrawal-batch query.
  function queryLenderAccount(
    LenderAccountQuery calldata query
  ) external view returns (LenderAccountQueryResult memory result);

  /// @notice executes combined lender queries in input order.
  function queryLenderAccounts(
    LenderAccountQuery[] calldata queries
  ) external view returns (LenderAccountQueryResult[] memory results);

  /// @notice returns aggregate data for one withdrawal expiry.
  /// @dev unknown expiries return the market's empty batch representation.
  function getWithdrawalBatchData(
    address market,
    uint32 expiry
  ) external view returns (WithdrawalBatchData memory data);

  /// @notice returns aggregate batch data in expiry input order.
  function getWithdrawalBatchesData(
    address market,
    uint32[] calldata expiries
  ) external view returns (WithdrawalBatchData[] memory data);

  /// @notice returns batch and lender status for each expiry in input order.
  function getWithdrawalBatchesDataWithLenderStatus(
    address market,
    uint32[] calldata expiries,
    address lender
  ) external view returns (WithdrawalBatchDataWithLenderStatus[] memory data);

  /// @notice returns one withdrawal batch and one lender's status in it.
  function getWithdrawalBatchDataWithLenderStatus(
    address market,
    uint32 expiry,
    address lender
  ) external view returns (WithdrawalBatchDataWithLenderStatus memory data);

  /// @notice returns one batch plus status for each lender in input order.
  function getWithdrawalBatchDataWithLendersStatus(
    address market,
    uint32 expiry,
    address[] calldata lenders
  )
    external
    view
    returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses);
}

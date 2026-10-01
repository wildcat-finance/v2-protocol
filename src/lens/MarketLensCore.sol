// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketLensCore
// ║  ██▀▀     ▀▀██   Strict token, market, lender, and withdrawal-batch reads.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  constructor(...)
// ║
// ║  TOKEN METADATA
// ║  getTokenInfo(...)
// ║  getTokensInfo(...)
// ║
// ║  MARKET DATA
// ║  getMarketData(...)
// ║  getMarketsData(...)
// ║  getMarketDataV2(...)
// ║  getMarketsDataV2(...)
// ║
// ║  LENDER DATA
// ║  getMarketDataWithLenderStatus(...)
// ║  getMarketsDataWithLenderStatus(...)
// ║  getLenderAccountData(...)
// ║  getLenderAccountData(...)
// ║  getLenderAccountsData(...)
// ║  queryLenderAccount(...)
// ║  queryLenderAccounts(...)
// ║
// ║  WITHDRAWAL BATCHES
// ║  getWithdrawalBatchData(...)
// ║  getWithdrawalBatchesData(...)
// ║  getWithdrawalBatchDataWithLenderStatus(...)
// ║  getWithdrawalBatchesDataWithLenderStatus(...)
// ║  getWithdrawalBatchDataWithLendersStatus(...)
// ╚═════

import '../IHooksFactory.sol';
import '../market/WildcatMarket.sol';
import './MarketData.sol';
import './TokenData.sol';
import './interfaces/IMarketLensCore.sol';

// ┌─ MarketLensCore ───────────────────────────────────────────────────────────
/// @title core market lens helper
///
/// @notice implements strict token, market, lender, and withdrawal reads for the `MarketLens`
///         facade.
contract MarketLensCore is IMarketLensCore {
  /// @notice ArchController configured for this helper.
  WildcatArchController public immutable archController;

  /// @notice default hooks factory configured for this helper.
  IHooksFactory public immutable hooksFactory;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address _archController, address _hooksFactory) {
    archController = WildcatArchController(_archController);
    hooksFactory = IHooksFactory(_hooksFactory);
  }

  // ░░▒▒▓▓██ [ TOKEN METADATA ] ───────────────────────────────────────────────

  // ┌─ getTokenInfo ─────
  function getTokenInfo(address token) external view returns (TokenMetadata memory info) {
    info.fill(token);
  }

  // ┌─ getTokensInfo ─────
  function getTokensInfo(address[] calldata tokens) external view returns (TokenMetadata[] memory info) {
    info = new TokenMetadata[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      info[i].fill(tokens[i]);
    }
  }

  // ░░▒▒▓▓██ [ MARKET DATA ] ──────────────────────────────────────────────────

  // ┌─ getMarketData ─────
  function getMarketData(address market) external view returns (MarketData memory data) {
    data.fill(WildcatMarket(market));
  }

  // ┌─ getMarketsData ─────
  function getMarketsData(address[] calldata markets) external view returns (MarketData[] memory data) {
    data = new MarketData[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]));
    }
  }

  // ┌─ getMarketDataV2 ─────
  function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data) {
    data.fill(WildcatMarket(market));
  }

  // ┌─ getMarketsDataV2 ─────
  function getMarketsDataV2(address[] calldata markets) external view returns (MarketDataV2_5[] memory data) {
    data = new MarketDataV2_5[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]));
    }
  }

  // ░░▒▒▓▓██ [ LENDER DATA ] ──────────────────────────────────────────────────

  // ┌─ getMarketDataWithLenderStatus ─────
  function getMarketDataWithLenderStatus(
    address lender,
    address market
  )
    external
    view
    returns (MarketDataWithLenderStatus memory data)
  {
    data.fill(WildcatMarket(market), lender);
  }

  // ┌─ getMarketsDataWithLenderStatus ─────
  function getMarketsDataWithLenderStatus(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (MarketDataWithLenderStatus[] memory data)
  {
    data = new MarketDataWithLenderStatus[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]), lender);
    }
  }

  // ┌─ getLenderAccountData ─────
  function getLenderAccountData(address lender, address market) external view returns (LenderAccountData memory data) {
    data.fill(WildcatMarket(market), lender);
  }

  // ┌─ getLenderAccountData ─────
  function getLenderAccountData(
    address lender,
    address[] calldata markets
  )
    external
    view
    returns (LenderAccountData[] memory arr)
  {
    arr = new LenderAccountData[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      arr[i].fill(WildcatMarket(markets[i]), lender);
    }
  }

  // ┌─ getLenderAccountsData ─────
  function getLenderAccountsData(
    address marketAddress,
    address[] calldata lenders
  )
    external
    view
    returns (LenderAccountData[] memory data)
  {
    data = new LenderAccountData[](lenders.length);
    WildcatMarket market = WildcatMarket(marketAddress);
    for (uint256 i; i < lenders.length; i++) {
      data[i].fill(market, lenders[i]);
    }
  }

  // ┌─ queryLenderAccount ─────
  function queryLenderAccount(LenderAccountQuery calldata query)
    external
    view
    returns (LenderAccountQueryResult memory result)
  {
    result.fill(query);
  }

  // ┌─ queryLenderAccounts ─────
  function queryLenderAccounts(LenderAccountQuery[] calldata queries)
    external
    view
    returns (LenderAccountQueryResult[] memory result)
  {
    result = new LenderAccountQueryResult[](queries.length);
    for (uint256 i; i < queries.length; i++) {
      result[i].fill(queries[i]);
    }
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL BATCHES ] ───────────────────────────────────────────

  // ┌─ getWithdrawalBatchData ─────
  function getWithdrawalBatchData(
    address market,
    uint32 expiry
  )
    external
    view
    returns (WithdrawalBatchData memory data)
  {
    data.fill(WildcatMarket(market), expiry);
  }

  // ┌─ getWithdrawalBatchesData ─────
  function getWithdrawalBatchesData(
    address market,
    uint32[] calldata expiries
  )
    external
    view
    returns (WithdrawalBatchData[] memory data)
  {
    data = new WithdrawalBatchData[](expiries.length);
    for (uint256 i; i < expiries.length; i++) {
      data[i].fill(WildcatMarket(market), expiries[i]);
    }
  }

  // ┌─ getWithdrawalBatchDataWithLenderStatus ─────
  function getWithdrawalBatchDataWithLenderStatus(
    address market,
    uint32 expiry,
    address lender
  )
    external
    view
    returns (WithdrawalBatchDataWithLenderStatus memory status)
  {
    status.fill(WildcatMarket(market), expiry, lender);
  }

  // ┌─ getWithdrawalBatchesDataWithLenderStatus ─────
  function getWithdrawalBatchesDataWithLenderStatus(
    address market,
    uint32[] calldata expiries,
    address lender
  )
    external
    view
    returns (WithdrawalBatchDataWithLenderStatus[] memory statuses)
  {
    statuses = new WithdrawalBatchDataWithLenderStatus[](expiries.length);
    for (uint256 i; i < expiries.length; i++) {
      statuses[i].fill(WildcatMarket(market), expiries[i], lender);
    }
  }

  // ┌─ getWithdrawalBatchDataWithLendersStatus ─────
  function getWithdrawalBatchDataWithLendersStatus(
    address market,
    uint32 expiry,
    address[] calldata lenders
  )
    external
    view
    returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses)
  {
    batch.fill(WildcatMarket(market), expiry);

    statuses = new WithdrawalBatchLenderStatus[](lenders.length);
    for (uint256 i; i < lenders.length; i++) {
      statuses[i].fill(WildcatMarket(market), batch, lenders[i]);
    }
  }
}

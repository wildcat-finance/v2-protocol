// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import './MarketData.sol';
import './TokenData.sol';
import './HooksInstanceData.sol';
import './HooksDataForBorrower.sol';

contract MarketLens {
  WildcatArchController public immutable archController;
  HooksFactory public immutable hooksFactory;

  constructor(address _archController, address _hooksFactory) {
    archController = WildcatArchController(_archController);
    hooksFactory = HooksFactory(_hooksFactory);
  }

  // ========================================================================== //
  //                         All hooks data for borrower                        //
  // ========================================================================== //

  function getHooksDataForBorrower(
    address borrower
  ) public view returns (HooksDataForBorrower memory data) {
    data.fill(archController, hooksFactory, borrower);
  }

  // ========================================================================== //
  //                        Hooks instances for borrower                        //
  // ========================================================================== //

  function getHooksInstancesForBorrower(
    address borrower
  ) public view returns (HooksInstanceData[] memory arr) {
    address[] memory hooksInstances = hooksFactory.getHooksInstancesForBorrower(borrower);
    arr = new HooksInstanceData[](arr.length);
    for (uint i; i < hooksInstances.length; i++) {
      arr[i].fill(hooksInstances[i], hooksFactory);
    }
  }

  // ========================================================================== //
  //                        Hooks templates for borrower                        //
  // ========================================================================== //

  function getHooksTemplateForBorrower(
    address borrower,
    address hooksTemplate
  ) public view returns (HooksTemplateData memory data) {
    data.fill(hooksFactory, hooksTemplate, borrower);
  }

  function getHooksTemplatesForBorrower(
    address borrower,
    address[] memory hooksTemplates
  ) public view returns (HooksTemplateData[] memory data) {
    data = new HooksTemplateData[](hooksTemplates.length);
    for (uint i; i < hooksTemplates.length; i++) {
      data[i].fill(hooksFactory, hooksTemplates[i], borrower);
    }
  }

  function getAllHooksTemplatesForBorrower(
    address borrower
  ) public view returns (HooksTemplateData[] memory data) {
    address[] memory hooksTemplates = hooksFactory.getHooksTemplates();
    return getHooksTemplatesForBorrower(borrower, hooksTemplates);
  }

  // ========================================================================== //
  //                                 Token info                                 //
  // ========================================================================== //

  function getTokenInfo(address token) public view returns (TokenMetadata memory info) {
    info.fill(token);
  }

  function getTokensInfo(
    address[] memory tokens
  ) public view returns (TokenMetadata[] memory info) {
    info = new TokenMetadata[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      info[i].fill(tokens[i]);
    }
  }

  // ========================================================================== //
  //                                   Markets                                  //
  // ========================================================================== //

  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
    return hooksFactory.getMarketsForHooksTemplateCount(hooksTemplate);
  }

  function getMarketData(address market) public view returns (MarketData memory data) {
    data.fill(WildcatMarket(market));
  }

  function getMarketsData(address[] memory markets) public view returns (MarketData[] memory data) {
    data = new MarketData[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]));
    }
  }

  function getPaginatedMarketsDataForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) public view returns (MarketData[] memory data) {
    address[] memory markets = hooksFactory.getMarketsForHooksTemplate(hooksTemplate, start, end);
    return getMarketsData(markets);
  }

  function getAllMarketsDataForHooksTemplate(
    address hooksTemplate
  ) external view returns (MarketData[] memory data) {
    address[] memory markets = hooksFactory.getMarketsForHooksTemplate(hooksTemplate);
    return getMarketsData(markets);
  }

  // ========================================================================== //
  //                         Markets with lender status                         //
  // ========================================================================== //

  function getMarketDataWithLenderStatus(
    address lender,
    address market
  ) public view returns (MarketDataWithLenderStatus memory data) {
    data.fill(WildcatMarket(market), lender);
  }

  function getMarketsDataWithLenderStatus(
    address lender,
    address[] memory markets
  ) public view returns (MarketDataWithLenderStatus[] memory data) {
    data = new MarketDataWithLenderStatus[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      data[i].fill(WildcatMarket(markets[i]), lender);
    }
  }

  // ========================================================================== //
  //                        Lender status in market only                        //
  // ========================================================================== //

  function getLenderAccountData(
    address lender,
    address market
  ) external view returns (LenderAccountData memory data) {
    data.fill(WildcatMarket(market), lender);
  }

  function getLenderAccountData(
    address lender,
    address[] memory markets
  ) external view returns (LenderAccountData[] memory arr) {
    arr = new LenderAccountData[](markets.length);
    for (uint256 i; i < markets.length; i++) {
      arr[i].fill(WildcatMarket(markets[i]), lender);
    }
  }

  function queryLenderAccount(
    LenderAccountQuery memory query
  ) external view returns (LenderAccountQueryResult memory result) {
    result.fill(query);
  }

  function queryLenderAccounts(
    LenderAccountQuery[] memory queries
  ) external view returns (LenderAccountQueryResult[] memory result) {
    result = new LenderAccountQueryResult[](queries.length);
    for (uint256 i; i < queries.length; i++) {
      result[i].fill(queries[i]);
    }
  }

  /* -------------------------------------------------------------------------- */
  /*                          Withdrawal batch queries                          */
  /* -------------------------------------------------------------------------- */

  function getWithdrawalBatchData(
    address market,
    uint32 expiry
  ) public view returns (WithdrawalBatchData memory data) {
    data.fill(WildcatMarket(market), expiry);
  }

  function getWithdrawalBatchesData(
    address market,
    uint32[] memory expiries
  ) public view returns (WithdrawalBatchData[] memory data) {
    data = new WithdrawalBatchData[](expiries.length);
    for (uint256 i; i < expiries.length; i++) {
      data[i].fill(WildcatMarket(market), expiries[i]);
    }
  }

  /* -------------------------------------------------------------------------- */
  /*                    Withdrawal batch queries with account                   */
  /* -------------------------------------------------------------------------- */

  function getWithdrawalBatchesDataWithLenderStatus(
    address market,
    uint32[] memory expiries,
    address lender
  ) external view returns (WithdrawalBatchDataWithLenderStatus[] memory statuses) {
    statuses = new WithdrawalBatchDataWithLenderStatus[](expiries.length);
    for (uint256 i; i < expiries.length; i++) {
      statuses[i].fill(WildcatMarket(market), expiries[i], lender);
    }
  }

  function getWithdrawalBatchDataWithLenderStatus(
    address market,
    uint32 expiry,
    address lender
  ) external view returns (WithdrawalBatchDataWithLenderStatus memory status) {
    status.fill(WildcatMarket(market), expiry, lender);
  }

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

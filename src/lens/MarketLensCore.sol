// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../IHooksFactory.sol";
import "../market/WildcatMarket.sol";
import "./MarketData.sol";
import "./TokenData.sol";
import "./interfaces/IMarketLensCore.sol";

contract MarketLensCore {
    WildcatArchController public immutable archController;
    IHooksFactory public immutable hooksFactory;

    constructor(address _archController, address _hooksFactory) {
        archController = WildcatArchController(_archController);
        hooksFactory = IHooksFactory(_hooksFactory);
    }

    function getTokenInfo(address token) external view returns (TokenMetadata memory info) {
        info.fill(token);
    }

    function getTokensInfo(address[] memory tokens) external view returns (TokenMetadata[] memory info) {
        info = new TokenMetadata[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            info[i].fill(tokens[i]);
        }
    }

    function getMarketData(address market) external view returns (MarketData memory data) {
        data.fill(WildcatMarket(market));
    }

    function getMarketsData(address[] memory markets) external view returns (MarketData[] memory data) {
        data = new MarketData[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
    }

    function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data) {
        data.fill(WildcatMarket(market));
    }

    function getMarketsDataV2(address[] memory markets) external view returns (MarketDataV2_5[] memory data) {
        data = new MarketDataV2_5[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
    }

    function getMarketDataWithLenderStatus(address lender, address market)
        external
        view
        returns (MarketDataWithLenderStatus memory data)
    {
        data.fill(WildcatMarket(market), lender);
    }

    function getMarketsDataWithLenderStatus(address lender, address[] memory markets)
        external
        view
        returns (MarketDataWithLenderStatus[] memory data)
    {
        data = new MarketDataWithLenderStatus[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]), lender);
        }
    }

    function getLenderAccountData(address lender, address market)
        external
        view
        returns (LenderAccountData memory data)
    {
        data.fill(WildcatMarket(market), lender);
    }

    function getLenderAccountData(address lender, address[] memory markets)
        external
        view
        returns (LenderAccountData[] memory arr)
    {
        arr = new LenderAccountData[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            arr[i].fill(WildcatMarket(markets[i]), lender);
        }
    }

    function getLenderAccountsData(address marketAddress, address[] memory lenders)
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

    function queryLenderAccount(LenderAccountQuery memory query)
        external
        view
        returns (LenderAccountQueryResult memory result)
    {
        result.fill(query);
    }

    function queryLenderAccounts(LenderAccountQuery[] memory queries)
        external
        view
        returns (LenderAccountQueryResult[] memory result)
    {
        result = new LenderAccountQueryResult[](queries.length);
        for (uint256 i; i < queries.length; i++) {
            result[i].fill(queries[i]);
        }
    }

    function getWithdrawalBatchData(address market, uint32 expiry)
        external
        view
        returns (WithdrawalBatchData memory data)
    {
        data.fill(WildcatMarket(market), expiry);
    }

    function getWithdrawalBatchesData(address market, uint32[] memory expiries)
        external
        view
        returns (WithdrawalBatchData[] memory data)
    {
        data = new WithdrawalBatchData[](expiries.length);
        for (uint256 i; i < expiries.length; i++) {
            data[i].fill(WildcatMarket(market), expiries[i]);
        }
    }

    function getWithdrawalBatchesDataWithLenderStatus(address market, uint32[] memory expiries, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus[] memory statuses)
    {
        statuses = new WithdrawalBatchDataWithLenderStatus[](expiries.length);
        for (uint256 i; i < expiries.length; i++) {
            statuses[i].fill(WildcatMarket(market), expiries[i], lender);
        }
    }

    function getWithdrawalBatchDataWithLenderStatus(address market, uint32 expiry, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus memory status)
    {
        status.fill(WildcatMarket(market), expiry, lender);
    }

    function getWithdrawalBatchDataWithLendersStatus(address market, uint32 expiry, address[] calldata lenders)
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

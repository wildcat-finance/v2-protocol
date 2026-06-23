// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../LenderAccountData.sol";
import "../MarketData.sol";
import "../TokenData.sol";
import "../WithdrawalBatchData.sol";

interface IMarketLensCore {
    function getTokenInfo(address token) external view returns (TokenMetadata memory info);

    function getTokensInfo(address[] memory tokens) external view returns (TokenMetadata[] memory infos);

    function getMarketData(address market) external view returns (MarketData memory data);

    function getMarketsData(address[] memory markets) external view returns (MarketData[] memory data);

    function getMarketDataV2(address market) external view returns (MarketDataV2_5 memory data);

    function getMarketsDataV2(address[] memory markets) external view returns (MarketDataV2_5[] memory data);

    function getMarketDataWithLenderStatus(address lender, address market)
        external
        view
        returns (MarketDataWithLenderStatus memory data);

    function getMarketsDataWithLenderStatus(address lender, address[] memory markets)
        external
        view
        returns (MarketDataWithLenderStatus[] memory data);

    function getLenderAccountData(address lender, address market) external view returns (LenderAccountData memory data);

    function getLenderAccountData(address lender, address[] memory markets)
        external
        view
        returns (LenderAccountData[] memory data);

    function getLenderAccountsData(address marketAddress, address[] memory lenders)
        external
        view
        returns (LenderAccountData[] memory data);

    function queryLenderAccount(LenderAccountQuery memory query)
        external
        view
        returns (LenderAccountQueryResult memory result);

    function queryLenderAccounts(LenderAccountQuery[] memory queries)
        external
        view
        returns (LenderAccountQueryResult[] memory results);

    function getWithdrawalBatchData(address market, uint32 expiry)
        external
        view
        returns (WithdrawalBatchData memory data);

    function getWithdrawalBatchesData(address market, uint32[] memory expiries)
        external
        view
        returns (WithdrawalBatchData[] memory data);

    function getWithdrawalBatchesDataWithLenderStatus(address market, uint32[] memory expiries, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus[] memory data);

    function getWithdrawalBatchDataWithLenderStatus(address market, uint32 expiry, address lender)
        external
        view
        returns (WithdrawalBatchDataWithLenderStatus memory data);

    function getWithdrawalBatchDataWithLendersStatus(address market, uint32 expiry, address[] calldata lenders)
        external
        view
        returns (WithdrawalBatchData memory batch, WithdrawalBatchLenderStatus[] memory statuses);
}

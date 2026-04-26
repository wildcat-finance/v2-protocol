// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../MarketLiveData.sol";

interface IMarketLensLive {
    function getMarketsLiveDataV2(address[] calldata markets) external view returns (MarketLiveDataV2_5[] memory data);

    function getMarketsLiveDataWithLenderStatusV2(address lender, address[] calldata markets)
        external
        view
        returns (MarketLiveDataWithLenderStatusV2_5[] memory data);
}

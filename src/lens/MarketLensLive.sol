// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "../IHooksFactory.sol";
import "../market/WildcatMarket.sol";
import "./MarketLiveData.sol";
import "./interfaces/IMarketLensLive.sol";

contract MarketLensLive is IMarketLensLive {
    WildcatArchController public immutable archController;
    IHooksFactory public immutable hooksFactory;

    constructor(address _archController, address _hooksFactory) {
        archController = WildcatArchController(_archController);
        hooksFactory = IHooksFactory(_hooksFactory);
    }

    function getMarketsLiveDataV2(address[] calldata markets) external view returns (MarketLiveDataV2_5[] memory data) {
        data = new MarketLiveDataV2_5[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]));
        }
    }

    function getMarketsLiveDataWithLenderStatusV2(address lender, address[] calldata markets)
        external
        view
        returns (MarketLiveDataWithLenderStatusV2_5[] memory data)
    {
        data = new MarketLiveDataWithLenderStatusV2_5[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            data[i].fill(WildcatMarket(markets[i]), lender);
        }
    }
}

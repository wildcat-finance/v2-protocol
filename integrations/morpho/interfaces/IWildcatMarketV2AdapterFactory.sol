// SPDX-License-Identifier: TODO
pragma solidity 0.8.25;

interface IWildcatMarketV2AdapterFactory {
    event CreateWildcatMarketV2Adapter(
        address indexed parentVault, address indexed market, address indexed wildcatMarketV2Adapter
    );

    error AdapterAlreadyExists();
    error NotRegisteredMarket();
    error UnsupportedMarketVersion();

    function V2_5_SCALED_TRANSFER_ROUNDING() external view returns (bytes32);

    function archController() external view returns (address);

    function wildcatMarketV2Adapter(address parentVault, address market) external view returns (address);

    function isWildcatMarketV2Adapter(address account) external view returns (bool);

    function createWildcatMarketV2Adapter(address parentVault, address market)
        external
        returns (address wildcatMarketV2Adapter);
}

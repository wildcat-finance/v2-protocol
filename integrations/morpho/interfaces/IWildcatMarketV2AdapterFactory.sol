// SPDX-License-Identifier: TODO
pragma solidity >=0.5.0;

interface IWildcatMarketV2AdapterFactory {

    event CreateWildcatMarketV2Adapter(
        address indexed parentVault, address indexed market, address indexed wildcatMarketV2Adapter
    );

    /// @notice Get the adapter address for a given (vault, market) pair
    function wildcatMarketV2Adapter(address parentVault, address market) external view returns (address);

    /// @notice Check if an address is a deployed adapter from this factory
    function isWildcatMarketV2Adapter(address account) external view returns (bool);

    /// @notice Deploy a new adapter for a parent vault and market
    function createWildcatMarketV2Adapter(address parentVault, address market)
        external
        returns (address wildcatMarketV2Adapter);
}

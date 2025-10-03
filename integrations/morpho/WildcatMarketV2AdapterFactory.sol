// SPDX-License-Identifier: TODO
pragma solidity 0.8.28;

import {WildcatMarketV2Adapter} from "./WildcatMarketV2Adapter.sol";
import {IWildcatMarketV2AdapterFactory} from "./interfaces/IWildcatMarketV2AdapterFactory.sol";

/**
 * @notice factory that deploys one adapter per (vault, market) pair.
 * TODO: maybe remove if we dont need factory
 */
contract WildcatMarketV2AdapterFactory is IWildcatMarketV2AdapterFactory {

	mapping(address parentVault => mapping(address market => address)) public wildcatMarketV2Adapter;
	mapping(address account => bool) public isWildcatMarketV2Adapter;

	function createWildcatMarketV2Adapter(address parentVault, address market)
		external
		returns (address adapter)
	{
		address _adapter = address(new WildcatMarketV2Adapter{salt: bytes32(0)}(parentVault, market));
		wildcatMarketV2Adapter[parentVault][market] = _adapter;
		isWildcatMarketV2Adapter[_adapter] = true;
		emit CreateWildcatMarketV2Adapter(parentVault, market, _adapter);
		return _adapter;
	}
}

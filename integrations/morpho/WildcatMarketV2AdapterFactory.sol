// SPDX-License-Identifier: TODO
pragma solidity 0.8.25;

import {IWildcatArchController} from "src/interfaces/IWildcatArchController.sol";

import {WildcatMarketV2Adapter} from "./WildcatMarketV2Adapter.sol";
import {IWildcatMarket} from "./interfaces/IWildcatMarket.sol";
import {IWildcatMarketV2AdapterFactory} from "./interfaces/IWildcatMarketV2AdapterFactory.sol";

/**
 * @notice Factory that deploys one adapter per (vault, market) pair.
 * @custom:author Jack McSweeney
 */
contract WildcatMarketV2AdapterFactory is IWildcatMarketV2AdapterFactory {
    bytes32 public constant V2_5_SCALED_TRANSFER_ROUNDING = keccak256("scaleAmountDown");

    address public immutable archController;

    mapping(address parentVault => mapping(address market => address)) public wildcatMarketV2Adapter;
    mapping(address account => bool) public isWildcatMarketV2Adapter;

    constructor(address _archController) {
        archController = _archController;
    }

    function createWildcatMarketV2Adapter(address parentVault, address market) external returns (address adapter) {
        if (wildcatMarketV2Adapter[parentVault][market] != address(0)) revert AdapterAlreadyExists();
        if (
            market.code.length == 0 || IWildcatMarket(market).archController() != archController
                || !IWildcatArchController(archController).isRegisteredMarket(market)
        ) revert NotRegisteredMarket();
        if (IWildcatMarket(market).scaledTransferRounding() != V2_5_SCALED_TRANSFER_ROUNDING) {
            revert UnsupportedMarketVersion();
        }

        adapter = address(new WildcatMarketV2Adapter{salt: bytes32(0)}(parentVault, market));
        wildcatMarketV2Adapter[parentVault][market] = adapter;
        isWildcatMarketV2Adapter[adapter] = true;
        emit CreateWildcatMarketV2Adapter(parentVault, market, adapter);
    }
}

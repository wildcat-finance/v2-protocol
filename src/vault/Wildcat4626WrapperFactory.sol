// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import { Wildcat4626Wrapper } from './Wildcat4626Wrapper.sol';

/**
 * @title Wildcat4626WrapperFactory
 * @notice factory for deploying wilcat erc-4626 wrappers.
 *  ensures at most one wrapper per market.
 */
contract Wildcat4626WrapperFactory {
  error WrapperAlreadyExists(address market);
  error ZeroAddress();

  event WrapperDeployed(address indexed market, address indexed wrapper);

  mapping(address => address) public wrapperForMarket;

  /// @notice callable by anyone, deploys a new wrapper for `market` if one does not already exist
  function createWrapper(address market) external returns (address wrapper) {
    if (market == address(0)) revert ZeroAddress();

    address existing = wrapperForMarket[market];
    if (existing != address(0)) revert WrapperAlreadyExists(market);

    wrapper = address(new Wildcat4626Wrapper(market));
    wrapperForMarket[market] = wrapper;

    emit WrapperDeployed(market, wrapper);
  }
}

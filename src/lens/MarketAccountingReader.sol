// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../market/WildcatMarket.sol';

/// @dev Older markets return one fewer word for state and batch tuples. Pad only the
///      exact legacy shape; normal ABI decoding still rejects truncated or dirty values.
library MarketAccountingReader {
  function _read(address market, bytes memory input, uint256 legacySize) private view returns (bytes memory data) {
    bool success;
    (success, data) = market.staticcall(input);
    if (!success) {
      assembly ('memory-safe') {
        revert(add(data, 0x20), mload(data))
      }
    }
    if (data.length == legacySize) data = bytes.concat(data, bytes32(0));
  }

  function currentState(WildcatMarket market) internal view returns (MarketState memory) {
    return
      abi.decode(_read(address(market), abi.encodeWithSelector(market.currentState.selector), 0x1c0), (MarketState));
  }

  function previousState(WildcatMarket market) internal view returns (MarketState memory) {
    return
      abi.decode(_read(address(market), abi.encodeWithSelector(market.previousState.selector), 0x1c0), (MarketState));
  }

  function withdrawalBatch(WildcatMarket market, uint32 expiry) internal view returns (WithdrawalBatch memory) {
    return abi.decode(
      _read(address(market), abi.encodeWithSelector(market.getWithdrawalBatch.selector, expiry), 0x60),
      (WithdrawalBatch)
    );
  }
}

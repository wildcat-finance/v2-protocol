// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import '../interfaces/WildcatStructsAndEnums.sol';
import '../libraries/MarketState.sol';
import '../libraries/Withdrawal.sol';

library TypeCasts {
  /**
   * @dev Function type cast to avoid duplicate declaration of MarketState return parameter.
   *
   *      With `viaIR` enabled, calling this function is a noop.
   */
  function asReturnsMarketState(
    function() internal view returns (uint256) fnIn
  ) internal pure returns (function() internal view returns (MarketState memory) fnOut) {
    assembly {
      fnOut := fnIn
    }
  }

  /**
   * @dev Function type cast to avoid duplicate declaration of MarketState and WithdrawalBatch
   *      return parameters.
   *
   *      With `viaIR` enabled, calling this function is a noop.
   */
  function asReturnsStateWithExpiryAndBatch(
    function() internal view returns (MarketState memory, uint32, WithdrawalBatch memory) fnIn
  ) internal pure returns (function() internal view returns (uint256, uint32, uint256) fnOut) {
    assembly {
      fnOut := fnIn
    }
  }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MarketState } from "../libraries/MarketState.sol";
import { WithdrawalBatch } from "../libraries/Withdrawal.sol";

/**
 * @dev Library with type-casts from functions returning raw pointers
 *      to functions returning instances of specific types.
 *      
 *      Used to get around solc's over-allocation of memory when
 *      dynamic return parameters are re-assigned.
 */
library FunctionTypeCasts {
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
  function asReturnsPointers(
    function() internal view returns (MarketState memory, uint32, WithdrawalBatch memory) fnIn
  ) internal pure returns (function() internal view returns (uint256, uint32, uint256) fnOut) {
    assembly {
      fnOut := fnIn
    }
  }
}
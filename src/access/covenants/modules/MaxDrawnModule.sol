// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../lib/ICovenantModule.sol';

/**
 * @title MaxDrawnModule
 * @dev Reference covenant module and the simplest possible predicate: a hard
 *      ceiling on the market's drawn amount. `config` is one word, the
 *      ceiling. Stateless, view-only, parameterised entirely by the
 *      dispatcher, exactly as the module interface intends.
 */
contract MaxDrawnModule is ICovenantModule {
  error DrawnCeilingExceeded(uint256 drawnAfter, uint256 ceiling);
  error InvalidCeiling();

  function checkOnBorrow(
    address /* market */,
    uint256 drawnBefore,
    uint256 drawnAfter,
    bytes calldata config
  ) external pure {
    if (drawnAfter <= drawnBefore) return; // reclaim, never gated
    uint256 ceiling = abi.decode(config, (uint256));
    if (drawnAfter > ceiling) revert DrawnCeilingExceeded(drawnAfter, ceiling);
  }

  function validateConfig(bytes calldata config) external pure {
    if (config.length != 32 || abi.decode(config, (uint256)) == 0) {
      revert InvalidCeiling();
    }
  }
}

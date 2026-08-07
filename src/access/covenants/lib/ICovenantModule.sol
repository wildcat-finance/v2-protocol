// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

/**
 * @title ICovenantModule
 * @dev A covenant module is a stateless predicate: it observes a proposed
 *      draw and reverts to block it. Modules hold no per-market state; their
 *      parameters live in the dispatching hooks instance and arrive as
 *      `config` on every call. Modules are reached by STATICCALL only, so a
 *      module can observe anything and change nothing.
 */
interface ICovenantModule {
  /// @dev Revert to block the draw. `drawnBefore`/`drawnAfter` are the
  ///      market's drawn amount either side of the proposed borrow.
  function checkOnBorrow(
    address market,
    uint256 drawnBefore,
    uint256 drawnAfter,
    bytes calldata config
  ) external view;

  /// @dev Called once at append time; revert to reject malformed config.
  function validateConfig(bytes calldata config) external view;
}

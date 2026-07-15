// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Generic market transfer-policy capability used by optional integrations.
 *      A `false` response is a compatibility promise that the hook will not
 *      later transition the market to a universally transfer-disabled state.
 */
interface IMarketTransferPolicy {
  function isMarketTransferDisabled(address market) external view returns (bool);
}

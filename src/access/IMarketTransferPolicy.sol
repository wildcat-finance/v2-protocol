// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Generic market transfer-policy capability used by optional integrations.
 *      A `false` response is a compatibility promise that the hook will not
 *      later transition the market to a universally transfer-disabled state.
 */
interface IMarketTransferPolicy {
  function isMarketTransferDisabled(address market) external view returns (bool);

  /**
   * @dev says whether `recipient` can receive `market` tokens right now without extra hook data.
   *      this doesn't pretend to check balance, allowance, or amount-specific failures. return
   *      false for an ordinary policy denial; integrations can treat a revert as unavailable.
   */
  function isMarketTransferRecipientAllowed(
    address market,
    address recipient
  ) external view returns (bool);
}

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
   * @dev Whether `recipient` currently passes the recipient-side transfer policy for `market`
   *      without additional hook data. This intentionally ignores sender balance, allowance,
   *      and amount-dependent failures. Policy denial should return false rather than revert;
   *      integrations may treat an unexpected query failure as unavailable.
   */
  function isMarketTransferRecipientAllowed(
    address market,
    address recipient
  ) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice read-only transfer policy exposed to wrappers and other optional integrations.
/// @dev a false result from `isMarketTransferDisabled` promises that this hook won't later move
///      the market into a universally transfer-disabled state.
interface IMarketTransferPolicy {
  /// @notice says whether every market-token transfer is disabled for `market`.
  function isMarketTransferDisabled(address market) external view returns (bool);

  /// @notice says whether `recipient` can receive `market` tokens right now without hook data.
  /// @dev this doesn't check balance, allowance, or amount-specific failures. false is an ordinary
  ///      policy denial; integrations can treat a revert as an unavailable policy answer.
  function isMarketTransferRecipientAllowed(
    address market,
    address recipient
  ) external view returns (bool);
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

/// @notice read surface specific to revolving credit markets.
interface IWildcatMarketRevolving {
  /// @notice emitted when a borrow, repayment, or closure reconciles drawn principal.
  /// @param previousDrawnAmount drawn principal before reconciliation.
  /// @param newDrawnAmount drawn principal after reconciliation.
  event DrawnAmountUpdated(uint256 previousDrawnAmount, uint256 newDrawnAmount);

  /// @notice fixed annual rate paid on the full market supply, in bips.
  /// @return commitment fee rate in bips.
  function commitmentFeeBips() external view returns (uint256);

  /// @notice principal currently treated as drawn for revolving APR calculations.
  /// @return drawn principal in underlying-asset units.
  function drawnAmount() external view returns (uint256);
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IWildcatMarketRevolving {
  event DrawnAmountUpdated(uint256 previousDrawnAmount, uint256 newDrawnAmount);

  function commitmentFeeBips() external view returns (uint256);

  function drawnAmount() external view returns (uint256);
}

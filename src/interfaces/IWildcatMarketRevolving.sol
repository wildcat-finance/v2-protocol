// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IWildcatMarketRevolving {
  function commitmentFeeBips() external view returns (uint256);

  function drawnAmount() external view returns (uint256);
}

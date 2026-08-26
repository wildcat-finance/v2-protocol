// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

/// @notice Minimal market view used by singleton hooks to identify the canonical wrapper.
interface IWrapperAwareSingletonMarket {
  function registeredWrapper() external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IERC4626} from "openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWildcat4626Wrapper is IERC4626 {
    /// @notice Returns the address of the wrapped Wildcat market token.
    function market() external view returns (address);

    /// @notice Returns the address that receives administrative privileges.
    function owner() external view returns (address);

    /// @notice Returns the maximum deposit cap enforced by the wrapper.
    function wrapperCap() external view returns (uint256);
}

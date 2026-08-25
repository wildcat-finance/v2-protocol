// SPDX-License-Identifier: TODO
pragma solidity 0.8.25;

import {AccountWithdrawalStatus, WithdrawalBatch} from "src/libraries/Withdrawal.sol";

/**
 * @notice Minimal V2.5 Wildcat market surface used by the Morpho adapter.
 */
interface IWildcatMarket {
    function archController() external view returns (address);

    function asset() external view returns (address);

    function scaledTransferRounding() external pure returns (bytes32);

    function balanceOf(address account) external view returns (uint256);

    function scaledBalanceOf(address account) external view returns (uint256);

    function scaleFactor() external view returns (uint256);

    function deposit(uint256 amount) external;

    function queueWithdrawal(uint256 amount) external returns (uint32 expiry);

    function queueWithdrawalScaled(uint256 scaledAmount) external returns (uint32 expiry);

    function executeWithdrawal(address account, uint32 expiry) external returns (uint256);

    function getWithdrawalBatch(uint32 expiry) external view returns (WithdrawalBatch memory);

    function getAccountWithdrawalStatus(address account, uint32 expiry)
        external
        view
        returns (AccountWithdrawalStatus memory);

    function getAvailableWithdrawalAmount(address account, uint32 expiry) external view returns (uint256);
}

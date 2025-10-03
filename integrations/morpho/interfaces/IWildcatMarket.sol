// SPDX-License-Identifier: TODO
pragma solidity >=0.8.20;

/**
 * @notice minimal Wildcat market interface used by the Morpho adapter.
 */
interface IWildcatMarket {

    /// @notice Underlying asset of the market
    function asset() external view returns (address);

    /// @notice Deposit exactly `amount` underlying asset
    function deposit(uint256 amount) external;

    /// @notice Normalized balance of `account`
    function balanceOf(address account) external view returns (uint256);

    /// @notice Queue a withdrawal of `amount` normalized assets
    function queueWithdrawal(uint256 amount) external returns (uint32 expiry);

    /// @notice Execute a matured withdrawal for `account` and `expiry`
    function executeWithdrawal(address account, uint32 expiry) external returns (uint256);

    /// @notice Expiries of every unpaid withdrawal batch
    function getUnpaidBatchExpiries() external view returns (uint32[] memory);

    /// @notice Amount currently available to withdraw immediately for `account` and `expiry`
    function getAvailableWithdrawalAmount(address account, uint32 expiry) external view returns (uint256);
}

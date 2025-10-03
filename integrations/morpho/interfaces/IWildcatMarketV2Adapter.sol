// SPDX-License-Identifier: TODO
pragma solidity >=0.5.0;

import {IAdapter} from "lib/vault-v2/src/interfaces/IAdapter.sol";

/**
 * @notice Wildcat market adapter interface used by Morpho VaultV2
 * @dev mirrors Morpho V1 adapter with some helpers for integratoors
 */
interface IWildcatMarketV2Adapter is IAdapter {

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    error AssetMismatch();
    error CannotSkimWildcatMarketTokens();
    error InvalidData();
    error NotAuthorized();
    error InsufficientImmediateLiquidity();

    /// @notice Factory that created this adapter.
    function factory() external view returns (address);

    /// @notice Parent vault v2 address.
    function parentVault() external view returns (address);

    /// @notice Wildcat market v2 address.
    function market() external view returns (address);

    /// @notice Unique adapter id used by the vault.
    function adapterId() external view returns (bytes32);

    /// @notice Recipient of skimmed tokens.
    function skimRecipient() external view returns (address);

    /// @notice Current vault-recorded allocation.
    function allocation() external view returns (uint256);

    /// @notice Ids array (single element).
    function ids() external view returns (bytes32[] memory);

    /// @notice Set the skim recipient (vault owner only).
    function setSkimRecipient(address newSkimRecipient) external;

    /// @notice Skim arbitrary ERC20 (not the market token).
    function skim(address token) external;

    // helpers

    /// @notice Queue a withdrawal for `amount` normalized assets held by this adapter.
    function queueAdapterWithdrawal(uint256 amount) external;

    /// @notice Realize up to `maxBatches` matured unpaid withdrawals owed to this adapter.
    function realizeClaimable(uint256 maxBatches) external;

    /// @notice Get available liquidity withdrawable now (adapter balance plus matured claimable).
    function getAvailableLiquidity() external view returns (uint256);

    /// @notice Check if `amount` can be withdrawn synchronously now.
    function canWithdrawSync(uint256 amount) external view returns (bool);
}

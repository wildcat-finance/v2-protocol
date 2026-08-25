// SPDX-License-Identifier: TODO
pragma solidity 0.8.25;

import {IAdapter} from "lib/vault-v2/src/interfaces/IAdapter.sol";

interface IWildcatMarketV2Adapter is IAdapter {
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    error ApproveFailed();
    error AssetMismatch();
    error CannotSkimWildcatMarketTokens();
    error InsufficientImmediateLiquidity();
    error InvalidData();
    error NotAuthorized();
    error TooManyTrackedWithdrawalExpiries();
    error WithdrawalExecutionMismatch();

    function MAX_TRACKED_WITHDRAWAL_EXPIRIES() external view returns (uint256);

    function factory() external view returns (address);

    function parentVault() external view returns (address);

    function market() external view returns (address);

    function asset() external view returns (address);

    function adapterId() external view returns (bytes32);

    function skimRecipient() external view returns (address);

    function idleAssets() external view returns (uint256);

    function accountedWithdrawalAssets(uint32 expiry) external view returns (uint256);

    function allocation() external view returns (uint256);

    function ids() external view returns (bytes32[] memory);

    function trackedWithdrawalExpiriesLength() external view returns (uint256);

    function trackedWithdrawalExpiryAt(uint256 index) external view returns (uint32);

    function pendingWithdrawals(uint32 expiry) external view returns (uint256);

    function totalPendingWithdrawals() external view returns (uint256);

    function setSkimRecipient(address newSkimRecipient) external;

    function skim(address token) external;

    function queueAdapterWithdrawal(uint256 amount) external;

    function queueAdapterFullWithdrawal() external;

    function realizeClaimable(uint256 maxBatches) external;

    function getAvailableLiquidity() external view returns (uint256);

    function canWithdrawSync(uint256 amount) external view returns (bool);
}

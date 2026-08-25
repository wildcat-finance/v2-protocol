// SPDX-License-Identifier: TODO
pragma solidity 0.8.25;

import {IERC20} from "lib/vault-v2/src/interfaces/IERC20.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";
import {LibERC20} from "src/libraries/LibERC20.sol";
import {MathUtils} from "src/libraries/MathUtils.sol";
import {AccountWithdrawalStatus, WithdrawalBatch} from "src/libraries/Withdrawal.sol";

import {IWildcatMarket} from "./interfaces/IWildcatMarket.sol";
import {IWildcatMarketV2Adapter} from "./interfaces/IWildcatMarketV2Adapter.sol";

/**
 * @notice Adapter for allocating Morpho Vault V2 funds into one Wildcat market.
 * @dev Wildcat withdrawals are asynchronous. Curators must queue a withdrawal before
 *      asking the vault to deallocate funds that are not already idle in the adapter.
 *
 *      - On allocate: deposits the assets received from the parent vault into the market.
 *      - On deallocate: realizes matured withdrawal batches until enough cash is idle,
 *        then reports the position value expected after the vault pulls `assets`.
 *
 * @custom:author Jack McSweeney
 */
contract WildcatMarketV2Adapter is IWildcatMarketV2Adapter {
    using LibERC20 for address;
    using MathUtils for uint256;

    // ===================================================================== //
    //                               Constants                               //
    // ===================================================================== //

    uint256 public constant MAX_TRACKED_WITHDRAWAL_EXPIRIES = 8;

    // ===================================================================== //
    //                               Immutables                              //
    // ===================================================================== //

    address public immutable factory;
    address public immutable parentVault;
    address public immutable market;
    address public immutable asset;
    bytes32 public immutable adapterId;

    // ===================================================================== //
    //                                 Storage                               //
    // ===================================================================== //

    address public skimRecipient;

    // Wildcat sends the full currently-available claim when a withdrawal is executed.
    // This can exceed a vault deallocation request, so excess proceeds stay managed here.
    uint256 internal _idleAssets;

    uint32[] internal trackedWithdrawalExpiries;
    mapping(uint32 expiry => uint256 indexPlusOne) internal trackedExpiryIndexPlusOne;
    mapping(uint32 expiry => uint256 assets) public accountedWithdrawalAssets;

    // ===================================================================== //
    //                               Constructor                             //
    // ===================================================================== //

    constructor(address _parentVault, address _market) {
        factory = msg.sender;
        parentVault = _parentVault;
        market = _market;

        address _asset = IVaultV2(_parentVault).asset();
        if (_asset != IWildcatMarket(_market).asset()) revert AssetMismatch();
        asset = _asset;

        adapterId = keccak256(abi.encode("this", address(this)));

        // The vault pulls assets after deallocate; the market pulls them during deposit.
        _safeApprove(asset, parentVault, type(uint256).max);
        _safeApprove(asset, market, type(uint256).max);
    }

    /**
     * @notice Set the recipient for skimmed tokens.
     * @dev Only callable by the vault owner.
     */
    function setSkimRecipient(address newSkimRecipient) external {
        if (msg.sender != IVaultV2(parentVault).owner()) revert NotAuthorized();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /**
     * @notice Skim an unrelated ERC20 held by the adapter to `skimRecipient`.
     * @dev Market tokens are always managed. For the underlying asset, only the balance
     *      above `idleAssets` is surplus and therefore skimmable.
     */
    function skim(address token) external {
        if (msg.sender != skimRecipient) revert NotAuthorized();
        if (token == market) revert CannotSkimWildcatMarketTokens();

        _syncTrackedWithdrawals();

        uint256 balance = token.balanceOf(address(this));
        if (token == asset) {
            uint256 managedBalance = _idleAssets;
            balance = balance > managedBalance ? balance - managedBalance : 0;
        }

        token.safeTransfer(skimRecipient, balance);
        emit Skim(token, balance);
    }

    /**
     * @notice Allocate assets into the market.
     * @dev Only callable by the parent vault. `data` must be empty.
     */
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        if (data.length != 0) revert InvalidData();
        if (msg.sender != parentVault) revert NotAuthorized();

        uint256 oldAllocation = allocation();
        if (assets > 0) IWildcatMarket(market).deposit(assets);
        // Deposit first so freshly transferred allocation assets cannot be mistaken for
        // withdrawal proceeds that somebody realized directly through the market.
        _syncTrackedWithdrawals();
        uint256 newAllocation = _positionAssets();

        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /**
     * @notice Deallocate assets from the adapter back to the parent vault.
     * @dev The vault pulls exactly `assets` from the adapter immediately after this call.
     *      The returned allocation change therefore prices the position after that pull.
     */
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        if (data.length != 0) revert InvalidData();
        if (msg.sender != parentVault) revert NotAuthorized();

        uint256 oldAllocation = allocation();
        _realizeClaimable(MAX_TRACKED_WITHDRAWAL_EXPIRIES, assets);
        if (_idleAssets < assets) revert InsufficientImmediateLiquidity();

        // The vault's transferFrom occurs after this callback. Account for it now; a failed
        // pull reverts the whole vault transaction and restores this value.
        _idleAssets -= assets;
        uint256 newAllocation = _positionAssets();

        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /**
     * @notice Current assets controlled by this adapter.
     * @dev Returns zero once the vault has no allocation for this adapter id, matching the
     *      Morpho adapter convention and preventing unsolicited donations from reviving it.
     */
    function realAssets() external view returns (uint256) {
        if (allocation() == 0) return 0;
        return _positionAssets();
    }

    // ===================================================================== //
    //                                  Views                                //
    // ===================================================================== //

    function ids() public view returns (bytes32[] memory ids_) {
        ids_ = new bytes32[](1);
        ids_[0] = adapterId;
    }

    function allocation() public view returns (uint256) {
        return IVaultV2(parentVault).allocation(adapterId);
    }

    function idleAssets() public view returns (uint256) {
        uint256 managedAssets = _idleAssets;
        uint256 assetBalance = asset.balanceOf(address(this));
        if (managedAssets >= assetBalance) return assetBalance;

        uint256 length = trackedWithdrawalExpiries.length;
        IWildcatMarket marketContract = IWildcatMarket(market);
        for (uint256 i; i < length; ++i) {
            uint32 expiry = trackedWithdrawalExpiries[i];
            AccountWithdrawalStatus memory status = marketContract.getAccountWithdrawalStatus(address(this), expiry);
            uint256 accountedAssets = accountedWithdrawalAssets[expiry];
            if (status.normalizedAmountWithdrawn > accountedAssets) {
                managedAssets += status.normalizedAmountWithdrawn - accountedAssets;
            }
        }
        return managedAssets < assetBalance ? managedAssets : assetBalance;
    }

    function trackedWithdrawalExpiriesLength() external view returns (uint256) {
        return trackedWithdrawalExpiries.length;
    }

    function trackedWithdrawalExpiryAt(uint256 index) external view returns (uint32) {
        return trackedWithdrawalExpiries[index];
    }

    /**
     * @notice Remaining value owed to the adapter from one tracked batch.
     * @dev Includes paid-but-unclaimed assets and the current value of unpaid scaled tokens.
     */
    function pendingWithdrawals(uint32 expiry) public view returns (uint256) {
        if (trackedExpiryIndexPlusOne[expiry] == 0) return 0;
        return _pendingWithdrawalAssets(expiry, IWildcatMarket(market).scaleFactor());
    }

    function totalPendingWithdrawals() public view returns (uint256 total) {
        uint256 length = trackedWithdrawalExpiries.length;
        if (length == 0) return 0;

        uint256 scaleFactor = IWildcatMarket(market).scaleFactor();
        for (uint256 i; i < length; ++i) {
            total += _pendingWithdrawalAssets(trackedWithdrawalExpiries[i], scaleFactor);
        }
    }

    /**
     * @notice Get liquidity that can be synchronously returned to the vault now.
     */
    function getAvailableLiquidity() public view returns (uint256 available) {
        available = idleAssets();

        uint256 length = trackedWithdrawalExpiries.length;
        IWildcatMarket marketContract = IWildcatMarket(market);
        for (uint256 i; i < length; ++i) {
            uint32 expiry = trackedWithdrawalExpiries[i];
            if (expiry < block.timestamp) {
                available += marketContract.getAvailableWithdrawalAmount(address(this), expiry);
            }
        }
    }

    function canWithdrawSync(uint256 amount) external view returns (bool) {
        return getAvailableLiquidity() >= amount;
    }

    // ===================================================================== //
    //                                  Helpers                              //
    // ===================================================================== //

    /**
     * @notice Queue `amount` normalized assets for withdrawal from Wildcat.
     * @dev Only the vault owner or an allocator may alter the vault's liquidity schedule.
     */
    function queueAdapterWithdrawal(uint256 amount) external {
        _requireOwnerOrAllocator();
        _syncTrackedWithdrawals();
        uint32 expiry = IWildcatMarket(market).queueWithdrawal(amount);
        _trackExpiry(expiry);
    }

    /**
     * @notice Queue the adapter's exact remaining scaled market balance.
     * @dev Uses the V2.5 scaled queue path to avoid leaving normalized-rounding dust.
     */
    function queueAdapterFullWithdrawal() external {
        _requireOwnerOrAllocator();
        _syncTrackedWithdrawals();
        IWildcatMarket marketContract = IWildcatMarket(market);
        uint256 scaledAmount = marketContract.scaledBalanceOf(address(this));
        uint32 expiry = marketContract.queueWithdrawalScaled(scaledAmount);
        _trackExpiry(expiry);
    }

    /**
     * @notice Realize up to `maxBatches` expired withdrawals owed to this adapter.
     * @dev Permissionless bc realizing a claim can only move managed assets from the market
     *      into this adapter; only the parent vault can consume them.
     */
    function realizeClaimable(uint256 maxBatches) external {
        _realizeClaimable(maxBatches, type(uint256).max);
    }

    // ===================================================================== //
    //                               Internals                               //
    // ===================================================================== //

    /*
    TL;DR: Wildcat withdrawals are batches of scaled tokens. Their normalized value keeps
    moving with interest until the corresponding scaled tokens are paid and burned. We keep
    a bounded, indexable set of expiries, but derive value from Wildcat's batch/account state
    instead of maintaining a second nominal ledger here. Eight expiries is the hard gas bound
    for Morpho's realAssets() loop; a curator must realize an old batch before opening a ninth.
    */

    function _positionAssets() internal view returns (uint256 total) {
        IWildcatMarket marketContract = IWildcatMarket(market);
        total = marketContract.balanceOf(address(this));

        uint256 length = trackedWithdrawalExpiries.length;
        uint256 scaleFactor = length == 0 ? 0 : marketContract.scaleFactor();
        uint256 unaccountedAssets;
        for (uint256 i; i < length; ++i) {
            uint32 expiry = trackedWithdrawalExpiries[i];
            WithdrawalBatch memory batch = marketContract.getWithdrawalBatch(expiry);
            AccountWithdrawalStatus memory status = marketContract.getAccountWithdrawalStatus(address(this), expiry);
            total += _pendingWithdrawalAssets(batch, status, scaleFactor);

            uint256 accountedAssets = accountedWithdrawalAssets[expiry];
            if (status.normalizedAmountWithdrawn > accountedAssets) {
                unaccountedAssets += status.normalizedAmountWithdrawn - accountedAssets;
            }
        }

        uint256 assetBalance = asset.balanceOf(address(this));
        uint256 managedIdleAssets = _idleAssets + unaccountedAssets;
        total += managedIdleAssets < assetBalance ? managedIdleAssets : assetBalance;
    }

    function _pendingWithdrawalAssets(uint32 expiry, uint256 scaleFactor) internal view returns (uint256) {
        IWildcatMarket marketContract = IWildcatMarket(market);
        WithdrawalBatch memory batch = marketContract.getWithdrawalBatch(expiry);
        AccountWithdrawalStatus memory status = marketContract.getAccountWithdrawalStatus(address(this), expiry);
        return _pendingWithdrawalAssets(batch, status, scaleFactor);
    }

    function _pendingWithdrawalAssets(
        WithdrawalBatch memory batch,
        AccountWithdrawalStatus memory status,
        uint256 scaleFactor
    ) internal pure returns (uint256) {
        if (batch.scaledTotalAmount == 0) return 0;
        if (status.scaledAmount == 0) return 0;

        uint256 normalizedTotalAmount = uint256(batch.normalizedAmountPaid)
            + uint256(batch.scaledTotalAmount - batch.scaledAmountBurned).rayMul(scaleFactor);
        uint256 accountTotalAmount = normalizedTotalAmount.mulDiv(status.scaledAmount, batch.scaledTotalAmount);
        return accountTotalAmount - status.normalizedAmountWithdrawn;
    }

    function _realizeClaimable(uint256 maxBatches, uint256 targetIdleAssets) internal {
        _syncTrackedWithdrawals();
        if (maxBatches == 0 || _idleAssets >= targetIdleAssets) return;

        IWildcatMarket marketContract = IWildcatMarket(market);
        uint256 processed;
        for (uint256 i = trackedWithdrawalExpiries.length; i > 0 && processed < maxBatches;) {
            unchecked {
                --i;
            }

            uint32 expiry = trackedWithdrawalExpiries[i];
            if (expiry >= block.timestamp) continue;
            ++processed;

            uint256 available = marketContract.getAvailableWithdrawalAmount(address(this), expiry);
            if (available > 0) {
                uint256 balanceBefore = asset.balanceOf(address(this));
                uint256 withdrawn = marketContract.executeWithdrawal(address(this), expiry);
                uint256 received = asset.balanceOf(address(this)) - balanceBefore;
                if (received != withdrawn) revert WithdrawalExecutionMismatch();
            }

            bool allWithdrawalsAccounted = _syncExpiry(expiry);
            if (allWithdrawalsAccounted && _pendingWithdrawalAssets(expiry, marketContract.scaleFactor()) == 0) {
                _untrackExpiryAt(i, expiry);
            }
            if (_idleAssets >= targetIdleAssets) break;
        }
    }

    function _syncTrackedWithdrawals() internal {
        uint256 assetBalance = asset.balanceOf(address(this));
        if (_idleAssets > assetBalance) _idleAssets = assetBalance;

        IWildcatMarket marketContract = IWildcatMarket(market);
        uint256 scaleFactor = trackedWithdrawalExpiries.length == 0 ? 0 : marketContract.scaleFactor();
        for (uint256 i = trackedWithdrawalExpiries.length; i > 0;) {
            unchecked {
                --i;
            }
            uint32 expiry = trackedWithdrawalExpiries[i];
            bool allWithdrawalsAccounted = _syncExpiry(expiry);
            if (allWithdrawalsAccounted && _pendingWithdrawalAssets(expiry, scaleFactor) == 0) {
                _untrackExpiryAt(i, expiry);
            }
        }
    }

    function _syncExpiry(uint32 expiry) internal returns (bool allWithdrawalsAccounted) {
        AccountWithdrawalStatus memory status = IWildcatMarket(market).getAccountWithdrawalStatus(address(this), expiry);
        uint256 accountedAssets = accountedWithdrawalAssets[expiry];
        uint256 withdrawnAssets = status.normalizedAmountWithdrawn;
        if (withdrawnAssets > accountedAssets) {
            uint256 assetBalance = asset.balanceOf(address(this));
            uint256 availableAssets = assetBalance > _idleAssets ? assetBalance - _idleAssets : 0;
            uint256 newlyAccountedAssets = MathUtils.min(withdrawnAssets - accountedAssets, availableAssets);
            if (newlyAccountedAssets > 0) {
                accountedAssets += newlyAccountedAssets;
                accountedWithdrawalAssets[expiry] = accountedAssets;
                _idleAssets += newlyAccountedAssets;
            }
        }
        return accountedAssets == withdrawnAssets;
    }

    function _trackExpiry(uint32 expiry) internal {
        if (trackedExpiryIndexPlusOne[expiry] != 0) return;
        if (trackedWithdrawalExpiries.length == MAX_TRACKED_WITHDRAWAL_EXPIRIES) {
            revert TooManyTrackedWithdrawalExpiries();
        }

        trackedWithdrawalExpiries.push(expiry);
        trackedExpiryIndexPlusOne[expiry] = trackedWithdrawalExpiries.length;
    }

    function _untrackExpiryAt(uint256 index, uint32 expiry) internal {
        uint256 lastIndex = trackedWithdrawalExpiries.length - 1;
        if (index != lastIndex) {
            uint32 lastExpiry = trackedWithdrawalExpiries[lastIndex];
            trackedWithdrawalExpiries[index] = lastExpiry;
            trackedExpiryIndexPlusOne[lastExpiry] = index + 1;
        }
        trackedWithdrawalExpiries.pop();
        delete trackedExpiryIndexPlusOne[expiry];
        delete accountedWithdrawalAssets[expiry];
    }

    function _requireOwnerOrAllocator() internal view {
        IVaultV2 vault = IVaultV2(parentVault);
        if (msg.sender != vault.owner() && !vault.isAllocator(msg.sender)) revert NotAuthorized();
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        _callApprove(token, spender, 0);
        _callApprove(token, spender, amount);
    }

    function _callApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory returnData) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (!success || (returnData.length != 0 && (returnData.length < 32 || !abi.decode(returnData, (bool))))) {
            revert ApproveFailed();
        }
    }
}

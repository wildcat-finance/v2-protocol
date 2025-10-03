// SPDX-License-Identifier: TODO
pragma solidity 0.8.28;

import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IAdapter} from "lib/vault-v2/src/interfaces/IAdapter.sol";
import {IERC20} from "lib/vault-v2/src/interfaces/IERC20.sol";
import {LibERC20} from "src/libraries/LibERC20.sol";

import {IWildcatMarket} from "./interfaces/IWildcatMarket.sol";
import {IWildcatMarketV2Adapter} from "./interfaces/IWildcatMarketV2Adapter.sol";

/**
 * @notice Adapter for allocating morpho-VaultV2 funds into a wildcat market.
 * @dev Withdrawals in wildcat are async
 * @dev curators must call queueAdapterWithdrawal before deallocating
 *        - On allocate: it deposits the adapter's asset balance into the market.
 *        - On deallocate: attempts to execute withdrawal of matured batches
 * 			owed to this adapter, succeeding if there is sufficient liquidity
 */
contract WildcatMarketV2Adapter is IWildcatMarketV2Adapter {
	using LibERC20 for address;
	// ===================================================================== //
	//                               Immutables                              //
	// ===================================================================== //

	address public immutable factory; // if we actually care for a factory
	address public immutable parentVault;
	address public immutable market;
	address public immutable asset;
	bytes32 public immutable adapterId;

	// ===================================================================== //
	//                                 Storage                               //
	// ===================================================================== //

	address public skimRecipient;
	mapping(uint32 => uint256) public pendingWithdrawals; // expiry => amount queued by this adapter
	uint256 public totalPendingWithdrawals; // total amount queued
	uint32[] internal trackedWithdrawalExpiries; // unique expiries the adapter has queued against
	mapping(uint32 => uint256) internal trackedExpiryIndexPlusOne; // index 1based

	// ===================================================================== //
	//                               Constructor                             //
	// ===================================================================== //

	constructor(address _parentVault, address _market) {
		factory = msg.sender;
		parentVault = _parentVault;
		market = _market;

		address _asset = IVaultV2(_parentVault).asset();
		require(_asset == IWildcatMarket(_market).asset(), AssetMismatch());
		asset = _asset;

		adapterId = keccak256(abi.encode("this", address(this)));

		// approvals: vault pulls on deallocate, market pulls on deposit
		// TODO: do we want to set max's?
		_safeApprove(asset, parentVault, type(uint256).max);
		_safeApprove(asset, market, type(uint256).max);
	}

	/**
	 * @notice Set the recipient for skimmed tokens.
	 * @dev Only callable by the vault owner.
	 * @param newSkimRecipient Address that will receive skimmed tokens.
	 */
	function setSkimRecipient(address newSkimRecipient) external {
		if (msg.sender != IVaultV2(parentVault).owner()) revert NotAuthorized();
		skimRecipient = newSkimRecipient;
		emit SetSkimRecipient(newSkimRecipient);
	}

	/**
	 * @notice Skim arbitrary ERC20 held by the adapter (e.g., rewards) to `skimRecipient`.
	 * @dev Reverts if `token` is the Wildcat market token itself. Only the `skimRecipient` may call.
	 * @param token The ERC20 address to skim.
	 */
	function skim(address token) external {
		if (msg.sender != skimRecipient) revert NotAuthorized();
		if (token == market) revert CannotSkimWildcatMarketTokens(); // MOOSE: do we also want to prevent underlying?
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(skimRecipient, balance);
		emit Skim(token, balance);
	}

	/**
	 * @notice Allocate assets into the market.
	 * @dev Only callable by the parent vault. `data` must be empty. If `assets > 0`,
	 *      deposits up to `assets` from the adapter's asset balance to the market.
	 * @param data Unused; must be empty (0x).
	 * @param assets Amount to allocate.
	 * @return ids The single adapter id used by this position.
	 * @return change The signed change in allocation.
	 */
	function allocate(bytes memory data, uint256 assets, bytes4, address)
		external
		returns (bytes32[] memory, int256)
	{
		if (data.length != 0) revert InvalidData();
		if (msg.sender != parentVault) revert NotAuthorized();

		if (assets > 0) {
			IWildcatMarket(market).deposit(assets);
		}

		uint256 oldAllocation = allocation();
		uint256 newAllocation = IWildcatMarket(market).balanceOf(address(this));
		int256 change = int256(newAllocation) - int256(oldAllocation);
		return (ids(), change);
	}

	/**
	 * @notice Deallocate assets from the adapter back to the parent vault.
	 * @dev
	 * - Only callable by the parent vault.
	 * - `data` must be empty (0x); no custom logic supported.
	 * - Attempts to realize up to 8 matured withdrawal batches owed to this adapter before deallocation.
	 * - Ensures the adapter has enough asset liquidity for the vault to pull the requested amount.
	 * - Reverts if insufficient immediate liquidity is available.
	 * @dev - the VaultV2 will pull the EXACT amount of `assets` from the adapter right after this call.
	 * 
	 * @param data Unused parameter; must be empty.
	 * @param assets Amount of assets to deallocate (transfer back to the vault).
	 * @return ids The single adapter id used by this position.
	 * @return change The signed change in allocation (new allocation minus old allocation).
	 */
	function deallocate(bytes memory data, uint256 assets, bytes4, address)
		external
		returns (bytes32[] memory, int256)
	{
		if (data.length != 0) revert InvalidData();
		if (msg.sender != parentVault) revert NotAuthorized();

		if (assets > 0) {
			// Attempt to realize up to 8 matured withdrawal batches owed to this adapter.
			// This is a arbitrary number of batches to call to increase available liquidity before deallocation.
			_realizeClaimable(8);

			// Check if the adapter has enough asset balance to fulfill the deallocation.
			uint256 available = asset.balanceOf(address(this));
			if (available < assets) revert InsufficientImmediateLiquidity();
		}

		uint256 oldAllocation = allocation();
		uint256 newAllocation = IWildcatMarket(market).balanceOf(address(this));
		int256 change = int256(newAllocation) - int256(oldAllocation);

		return (ids(), change);
	}

	/**
	 * @notice Current assets as seen by the adapter (0 if vault allocation is zero).
	 */
	function realAssets() external view returns (uint256) {
		if (allocation() == 0) return 0;
		return IWildcatMarket(market).balanceOf(address(this)) + asset.balanceOf(address(this));
	}

	// ===================================================================== //
	//                                Views                                   //
	// ===================================================================== //

	/**
	 * @notice Adapter id this position uses (assumed we only want one? )
	 */
	function ids() public view returns (bytes32[] memory) {
		bytes32[] memory ids_ = new bytes32[](1);
		ids_[0] = adapterId;
		return ids_;
	}

	/**
	 * @notice Current allocation recorded by the vault for this adapter id.
	 */
	function allocation() public view returns (uint256) {
		return IVaultV2(parentVault).allocation(adapterId);
	}

	// ===================================================================== //
	//                               Internals                               //
	// ===================================================================== //

	/**
	/*
	TL;DR: Withdrawals are batched by "expiry" timestamps, and only become realizable once
	they mature. To avoid scanning arbitrary timestamps and to bound gas, we keep an
	indexable set of expiries that currently have nonzero pending amounts. This lets us:
	- process at most `maxBatches` matured buckets per call,
	- remain best-effort and non-reverting via try/catch when querying availability,
	- reconcile both per-expiry and global pending debt as amounts are realized, and
	- remove empty buckets in O(1) using swap-and-pop with a 1-based index map.
	We iterate the tracked array in reverse so removals don’t invalidate yet-to-be-visited
	indices.
	*/

	/**
	 * @notice Realize up to `maxBatches` matured withdrawal batches owed to this adapter.
	 * @dev Processes up to `maxBatches` matured batches. errors querying batch
	 *      availability are ignored to keep this non-reverting.
	 *      For each matured batch, attempts to execute withdrawal and update tracking.
	 * @param maxBatches Maximum number of batches to try process
	 */
	function _realizeClaimable(uint256 maxBatches) internal {
		if (maxBatches == 0) return;
		uint32[] storage expiries = trackedWithdrawalExpiries;
		uint256 len = expiries.length;
		if (len == 0) return;
		uint256 processed;
		address self = address(this);
		IWildcatMarket marketContract = IWildcatMarket(market);
		for (uint256 i = len; i > 0 && processed < maxBatches; ) {
			unchecked { i--; }
			uint32 expiry = expiries[i];
			if (expiry >= block.timestamp) continue;
			processed++;
			uint256 available;
			try marketContract.getAvailableWithdrawalAmount(self, expiry) returns (uint256 amt) {
				available = amt;
			} catch {
				continue;
			}
			if (available > 0) {
				uint256 withdrawn = marketContract.executeWithdrawal(self, expiry);
				_updatePendingAfterWithdrawal(expiry, withdrawn);
			}
			if (pendingWithdrawals[expiry] == 0) {
				_untrackExpiryAt(i, expiry);
			}
		}
	}

	function _updatePendingAfterWithdrawal(uint32 expiry, uint256 withdrawn) internal {
		if (withdrawn == 0) return;
		uint256 pending = pendingWithdrawals[expiry];
		if (pending >= withdrawn) {
			pendingWithdrawals[expiry] = pending - withdrawn;
			totalPendingWithdrawals = totalPendingWithdrawals > withdrawn ?
				totalPendingWithdrawals - withdrawn : 0;
			if (pending == withdrawn) {
				delete pendingWithdrawals[expiry];
			}
		} else {
			// More was realized than originally tracked (interest/rounding). Zero out tracking.
			totalPendingWithdrawals = totalPendingWithdrawals > pending ?
				totalPendingWithdrawals - pending : 0;
			delete pendingWithdrawals[expiry];
		}
	}

	function _trackExpiry(uint32 expiry) internal {
		if (expiry == 0) return;
		if (trackedExpiryIndexPlusOne[expiry] != 0) return;
		trackedWithdrawalExpiries.push(expiry);
		trackedExpiryIndexPlusOne[expiry] = trackedWithdrawalExpiries.length;
	}

	function _untrackExpiryAt(uint256 index, uint32 expiry) internal {
		uint256 arrayLength = trackedWithdrawalExpiries.length;
		if (index >= arrayLength) return;
		uint32 lastExpiry = trackedWithdrawalExpiries[arrayLength - 1];
		if (index != arrayLength - 1) {
			trackedWithdrawalExpiries[index] = lastExpiry;
			trackedExpiryIndexPlusOne[lastExpiry] = index + 1;
		}
		trackedWithdrawalExpiries.pop();
		delete trackedExpiryIndexPlusOne[expiry];
	}

	function _recordPending(uint32 expiry, uint256 amount) internal {
		if (expiry == 0 || amount == 0) return;
		pendingWithdrawals[expiry] += amount;
		totalPendingWithdrawals += amount;
		_trackExpiry(expiry);
	}

	function _safeApprove(address token, address spender, uint256 amount) internal {
		// reset to zero first for usdt-like tokens
		(bool s1, ) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
		require(s1, "APPROVE_RESET_FAILED");
		(bool s2, ) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
		require(s2, "APPROVE_FAILED");
	}



    // ===================================================================== //
    //                             helpers                                   //
    // ===================================================================== //

	/**
	 * @notice Queue a withdrawal for `amount` normalized assets held by this adapter.
	 * @dev Only callable by the vault owner or an authorized allocator. `amount` is in
	 *      underlying (normalized) units as expected by the market.
	 */
	function queueAdapterWithdrawal(uint256 amount) external {
		address _parent = parentVault;
		if (msg.sender != IVaultV2(_parent).owner() && !IVaultV2(_parent).isAllocator(msg.sender)) revert NotAuthorized();
		uint32 expiry = IWildcatMarket(market).queueWithdrawal(amount);
		_recordPending(expiry, amount);
	}

	/**
	 * @notice Realize up to `maxBatches` matured unpaid withdrawals owed to this adapter.
	 */
	function realizeClaimable(uint256 maxBatches) external {
		_realizeClaimable(maxBatches);
	}

	/**
	 * @notice Get available liquidity withdrawable now (balanceOf + matured claimable).
	 * @dev helper for allocators to check synchronous liquidity
	 */
	function getAvailableLiquidity() external view returns (uint256 available) {
		available = asset.balanceOf(address(this));

		uint32[] storage expiries = trackedWithdrawalExpiries;
		IWildcatMarket marketContract = IWildcatMarket(market);
		address self = address(this);
		for (uint256 i = 0; i < expiries.length; i++) {
			uint32 expiry = expiries[i];
			if (expiry >= block.timestamp) continue;
			try marketContract.getAvailableWithdrawalAmount(self, expiry) returns (uint256 amt) {
				available += amt;
			} catch {}
		}
		return available;
	}

	/**
	 * @notice Check if `amount` can be withdrawn now.
	 * @dev helper for the vault to check whether a synchronous withdrawal will succeed.
	 */
	function canWithdrawSync(uint256 amount) external view returns (bool) {
		return this.getAvailableLiquidity() >= amount;
	}
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WildcatMarketWithdrawals
//  \ ^ /   Withdrawal queueing, batch funding, and claim collection.
//    V
//
//  QUEUEING
//  queueWithdrawal(...)
//  queueWithdrawalScaled(...)
//  queueFullWithdrawal()
//  _queueWithdrawal(...)
//
//  BATCH FUNDING
//  repayAndProcessUnpaidWithdrawalBatches(...)
//  _processUnpaidWithdrawalBatch(...)
//
//  CLAIM COLLECTION
//  executeWithdrawal(...)
//  executeWithdrawals(...)
//  _executeWithdrawal(...)
//  getAvailableWithdrawalAmount(...)
//
//  QUERIES
//  getUnpaidBatchExpiries()
//  getWithdrawalBatch(...)
//  getAccountWithdrawalStatus(...)
// ═════

import './WildcatMarketBase.sol';
import '../libraries/LibERC20.sol';
import '../libraries/BoolUtils.sol';

// ┌─ WildcatMarketWithdrawals ─────────────────────────────────────────────────
/// @notice queue lender exits, fund expired batches oldest first, and collect paid claims.
contract WildcatMarketWithdrawals is WildcatMarketBase {
  using LibERC20 for address;
  using MathUtils for uint256;
  using MathUtils for bool;
  using SafeCastLib for uint256;
  using BoolUtils for bool;

  // ░░▒▒▓▓██ [ QUEUEING ] ─────────────────────────────────────────────────────

  // ┌─ queueWithdrawal ─────
  /// @notice queue `amount` normalized market tokens, rounded down to scaled shares.
  ///
  /// @param amount normalized market-token amount to queue.
  ///
  /// @return expiry key of the batch joined or created.
  function queueWithdrawal(uint256 amount) external nonReentrant sphereXGuardExternal returns (uint32 expiry) {
    MarketState memory state = _getUpdatedState();

    uint104 scaledAmount = state.scaleAmountDown(amount).toUint104();
    if (scaledAmount == 0) revert_NullBurnAmount();

    Account memory account = _getAccount(msg.sender);

    return _queueWithdrawal(state, account, msg.sender, scaledAmount, amount, _runtimeConstant(0x24));
  }

  // ┌─ queueWithdrawalScaled ─────
  /// @notice queue exactly `scaledAmount` scaled shares.
  ///
  /// @dev for integrations, including the canonical ERC-4626 wrapper, that already track scaled shares.
  ///      don't round-trip those shares through a normalized amount.
  ///
  /// @param scaledAmount exact scaled shares to move into the batch.
  ///
  /// @return expiry key of the batch joined or created.
  function queueWithdrawalScaled(uint256 scaledAmount)
    external
    nonReentrant
    sphereXGuardExternal
    returns (uint32 expiry)
  {
    MarketState memory state = _getUpdatedState();

    uint104 amount = scaledAmount.toUint104();
    if (amount == 0) revert_NullBurnAmount();

    Account memory account = _getAccount(msg.sender);

    uint256 normalizedAmount = state.normalizeAmount(amount);

    return _queueWithdrawal(state, account, msg.sender, amount, normalizedAmount, _runtimeConstant(0x24));
  }

  // ┌─ queueFullWithdrawal ─────
  /// @notice queue the caller's entire direct scaled market-token balance.
  ///
  /// @return expiry key of the batch joined or created.
  function queueFullWithdrawal() external nonReentrant sphereXGuardExternal returns (uint32 expiry) {
    MarketState memory state = _getUpdatedState();

    Account memory account = _getAccount(msg.sender);

    uint104 scaledAmount = account.scaledBalance;
    if (scaledAmount == 0) revert_NullBurnAmount();

    uint256 normalizedAmount = state.normalizeAmount(scaledAmount);

    return _queueWithdrawal(state, account, msg.sender, scaledAmount, normalizedAmount, _runtimeConstant(0x04));
  }

  // ┌─ _queueWithdrawal ─────
  /// @dev move scaled shares into the current batch, or create one. reserve available liquidity
  ///      for the batch before committing state.
  function _queueWithdrawal(
    MarketState memory state,
    Account memory account,
    address accountAddress,
    uint104 scaledAmount,
    uint256 normalizedAmount,
    uint256 baseCalldataSize
  )
    internal
    returns (uint32 expiry)
  {
    expiry = state.pendingWithdrawalExpiry;

    if (expiry == 0) {
      // closed markets don't need another withdrawal delay.
      uint256 duration = state.isClosed.ternary(0, withdrawalBatchDuration);
      expiry = (block.timestamp + duration).toUint32();

      // don't reopen a processed batch. mixing pre- and post-close claims shifts value
      // between withdrawers.
      if (state.isClosed && _withdrawalData.batches[expiry].scaledTotalAmount != 0) {
        expiry += 1;
        if (_withdrawalData.batches[expiry].scaledTotalAmount != 0) {
          revert_WithdrawalBatchKeyAlreadyExists();
        }
      }

      emit_WithdrawalBatchCreated(expiry);
      state.pendingWithdrawalExpiry = expiry;
    }

    // the repayment phase bypasses hook admission, not batch accounting or market-level sanctions checks.
    if (!_isInRepayment()) {
      hooks.onQueueWithdrawal(accountAddress, expiry, scaledAmount, state, baseCalldataSize);
    }

    // move shares into the batch, not out of supply. funding burns them.
    account.scaledBalance -= scaledAmount;
    _accounts[accountAddress] = account;
    emit_Transfer(accountAddress, address(this), normalizedAmount);

    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];

    // keep account ownership, batch ownership, and market pending shares in sync.
    _withdrawalData.accountStatuses[expiry][accountAddress].scaledAmount += scaledAmount;
    // the ABI is uint128. keep the uint104 admission cap and its overflow panic.
    assembly ('memory-safe') {
      let total :=
        add(and(mload(batch), 0xffffffffffffffffffffffffffffffff), and(scaledAmount, 0xffffffffffffffffffffffffff))
      if gt(total, 0xffffffffffffffffffffffffff) {
        mstore(0, 0x4e487b71)
        mstore(0x20, 0x11)
        revert(0x1c, 0x24)
      }
      mstore(batch, total)
    }
    state.scaledPendingWithdrawals += scaledAmount;

    emit_WithdrawalQueued(expiry, accountAddress, scaledAmount, normalizedAmount);

    // protect unclaimed assets, older unpaid batches, and protocol fees before funding this batch.
    uint256 currentTotalAssets = totalAssets();
    uint256 availableLiquidity = batch.availableLiquidityForPendingBatch(state, currentTotalAssets);
    if (availableLiquidity > 0) {
      _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity);
    }

    _withdrawalData.batches[expiry] = batch;
    _writeState(state, currentTotalAssets);
  }

  // ░░▒▒▓▓██ [ BATCH FUNDING ] ────────────────────────────────────────────────

  // ┌─ repayAndProcessUnpaidWithdrawalBatches ─────
  /// @notice repay if needed, then fund expired unpaid batches oldest first.
  ///
  /// @dev stop at `maxBatches` or when liquidity runs out. zero repayment is valid even after closure,
  ///      so existing liquidity can still fund batches in bounded calls.
  ///
  /// @param repayAmount underlying assets to transfer from the caller, or zero.
  /// @param maxBatches  upper bound on expired unpaid batches to process.
  function repayAndProcessUnpaidWithdrawalBatches(
    uint256 repayAmount,
    uint256 maxBatches
  )
    public
    virtual
    nonReentrant
    sphereXGuardExternal
  {
    // transfer first so the state update can use this repayment for pending and unpaid batches.
    if (repayAmount > 0) {
      asset.safeTransferFrom(msg.sender, address(this), repayAmount);
      emit_DebtRepaid(msg.sender, repayAmount);
    }

    MarketState memory state = _getUpdatedState(repayAmount == 0);
    if (state.isClosed && repayAmount != 0) revert_RepayToClosedMarket();

    uint256 currentTotalAssets;
    if (repayAmount > 0) {
      // keep solc from specializing this call on a constant calldata size.
      hooks.onRepay(repayAmount, state, _runtimeConstant(0x44));
      currentTotalAssets = _onRepayAndGetTotalAssets(state, repayAmount);
    } else {
      currentTotalAssets = totalAssets();
    }

    // reserved claims and protocol fees aren't available to pay another batch.
    uint256 availableLiquidity =
      currentTotalAssets.satSub(state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees);

    uint256 numBatches = MathUtils.min(maxBatches, _withdrawalData.unpaidBatches.length());

    // newer batches wait until the head is fully funded.
    uint256 i;
    while (i < numBatches && availableLiquidity > 0) {
      uint256 normalizedAmountPaid = _processUnpaidWithdrawalBatch(state, availableLiquidity);

      availableLiquidity = availableLiquidity.satSub(normalizedAmountPaid);
      unchecked {
        ++i;
      }
    }

    _writeState(state, currentTotalAssets);
  }

  // ┌─ _processUnpaidWithdrawalBatch ─────
  /// @dev fund the oldest unpaid batch and remove it once fully funded. an empty queue reverts.
  function _processUnpaidWithdrawalBatch(
    MarketState memory state,
    uint256 availableLiquidity
  )
    internal
    returns (uint256 normalizedAmountPaid)
  {
    uint32 expiry = _withdrawalData.unpaidBatches.first();

    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];

    (, normalizedAmountPaid) = _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity);

    // no new requests can join this batch. once fully funded, its sub-RAY remainder isn't owed.
    batch.releaseRemainder(state);

    _withdrawalData.batches[expiry] = batch;

    if (batch.scaledTotalAmount == batch.scaledAmountBurned) {
      _withdrawalData.unpaidBatches.shift();
      emit_WithdrawalBatchClosed(expiry);
    }
  }

  // ░░▒▒▓▓██ [ CLAIM COLLECTION ] ─────────────────────────────────────────────

  // ┌─ executeWithdrawal ─────
  /// @notice claim newly available underlying assets for `accountAddress`.
  ///
  /// @dev anyone can call. the batch must have expired or been released by closure. assets go to
  ///      the account, or its sanctions escrow if currently sanctioned. reverts if nothing new is claimable.
  ///
  /// @param accountAddress lender that owns the claim and receives unsanctioned assets.
  /// @param expiry         batch key and scheduled expiry timestamp.
  ///
  /// @return underlying assets transferred to the account or its sanctions escrow.
  function executeWithdrawal(
    address accountAddress,
    uint32 expiry
  )
    public
    nonReentrant
    sphereXGuardExternal
    returns (uint256)
  {
    MarketState memory state = _getUpdatedState();
    uint256 normalizedAmountWithdrawn = _executeWithdrawal(state, accountAddress, expiry);

    _writeState(state);
    return normalizedAmountWithdrawn;
  }

  // ┌─ executeWithdrawals ─────
  /// @notice claim several account/batch pairs in one transaction.
  ///
  /// @dev the arrays are paired by index. one invalid or empty claim reverts the whole call.
  ///
  /// @param accountAddresses lenders that own each claim.
  /// @param expiries         batch key paired with each lender.
  ///
  /// @return amounts underlying assets transferred to each account or its sanctions escrow.
  function executeWithdrawals(
    address[] calldata accountAddresses,
    uint32[] calldata expiries
  )
    external
    nonReentrant
    sphereXGuardExternal
    returns (uint256[] memory amounts)
  {
    if (accountAddresses.length != expiries.length) revert_InvalidArrayLength();

    amounts = new uint256[](accountAddresses.length);

    MarketState memory state = _getUpdatedState();

    for (uint256 i = 0; i < accountAddresses.length; i++) {
      amounts[i] = _executeWithdrawal(state, accountAddresses[i], expiries[i]);
    }

    _writeState(state);
    return amounts;
  }

  // ┌─ _executeWithdrawal ─────
  /// @dev settle only the newly paid part of a pro-rata claim. route sanctioned accounts through escrow.
  function _executeWithdrawal(
    MarketState memory state,
    address accountAddress,
    uint32 expiry
  )
    internal
    returns (uint256)
  {
    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];
    if (expiry == state.pendingWithdrawalExpiry) revert_WithdrawalBatchNotExpired();

    AccountWithdrawalStatus storage status = _withdrawalData.accountStatuses[expiry][accountAddress];

    // claim against cumulative funding, not the latest payment. subtract what's already been collected.
    uint128 newTotalWithdrawn =
      uint128(MathUtils.mulDiv(batch.normalizedAmountPaid, status.scaledAmount, batch.scaledTotalAmount));

    uint128 normalizedAmountWithdrawn = newTotalWithdrawn - status.normalizedAmountWithdrawn;

    if (normalizedAmountWithdrawn == 0) revert_NullWithdrawalAmount();

    status.normalizedAmountWithdrawn = newTotalWithdrawn;
    state.normalizedUnclaimedWithdrawals -= normalizedAmountWithdrawn;

    if (_isSanctioned(accountAddress)) {
      // escrow holds the assets until Chainalysis clears the account or the borrower overrides the sanction.
      address escrow = _createEscrowForUnderlyingAsset(accountAddress);
      asset.safeTransfer(escrow, normalizedAmountWithdrawn);

      emit_SanctionedAccountWithdrawalSentToEscrow(accountAddress, escrow, expiry, normalizedAmountWithdrawn);
    } else {
      asset.safeTransfer(accountAddress, normalizedAmountWithdrawn);
    }

    emit_WithdrawalExecuted(expiry, accountAddress, normalizedAmountWithdrawn);

    return normalizedAmountWithdrawn;
  }

  // ┌─ getAvailableWithdrawalAmount ─────
  /// @notice preview the account's newly claimable underlying assets.
  ///
  /// @dev uses reserved assets from the current-state preview. a pending batch still reverts,
  ///      unless closure releases it. a valid claim with nothing new to collect returns zero.
  ///
  /// @param accountAddress lender whose claim is queried.
  /// @param expiry         batch key and scheduled expiry timestamp.
  ///
  /// @return currently claimable underlying assets.
  function getAvailableWithdrawalAmount(
    address accountAddress,
    uint32 expiry
  )
    external
    view
    nonReentrantView
    returns (uint256)
  {
    (MarketState memory state, uint32 pendingBatchExpiry, WithdrawalBatch memory pendingBatch) =
      _calculateCurrentState();

    // funded closure can release the batch before expiry. preview and execution must agree.
    if (expiry == state.pendingWithdrawalExpiry || (expiry >= block.timestamp && !state.isClosed)) {
      revert_WithdrawalBatchNotExpired();
    }

    // use the previewed batch when available. storage may not include this block's funding yet.
    WithdrawalBatch memory batch;
    if (expiry == pendingBatchExpiry) {
      batch = pendingBatch;
    } else {
      batch = _withdrawalData.batches[expiry];
    }
    AccountWithdrawalStatus memory status = _withdrawalData.accountStatuses[expiry][accountAddress];

    // floor each account's cumulative share, just like execution. dust stays in the batch;
    // cheaper claims are the tradeoff.
    uint256 previousTotalWithdrawn = status.normalizedAmountWithdrawn;
    uint256 newTotalWithdrawn = uint256(batch.normalizedAmountPaid).mulDiv(status.scaledAmount, batch.scaledTotalAmount);
    return newTotalWithdrawn - previousTotalWithdrawn;
  }

  // ░░▒▒▓▓██ [ QUERIES ] ──────────────────────────────────────────────────────

  // ┌─ getUnpaidBatchExpiries ─────
  /// @notice list expired, underfunded batches in payment order.
  ///
  /// @return expiries oldest unpaid batch first.
  function getUnpaidBatchExpiries() external view nonReentrantView returns (uint32[] memory) {
    return _withdrawalData.unpaidBatches.values();
  }

  // ┌─ getWithdrawalBatch ─────
  /// @notice read aggregate accounting for the batch at `expiry`.
  ///
  /// @dev for the current batch, include interest and payments through this block. nothing is written.
  ///
  /// @param expiry batch key and scheduled expiry timestamp.
  ///
  /// @return batch current aggregate accounting for that key.
  function getWithdrawalBatch(uint32 expiry) external view nonReentrantView returns (WithdrawalBatch memory batch) {
    (, uint32 pendingBatchExpiry, WithdrawalBatch memory pendingBatch) = _calculateCurrentState();
    if ((expiry == pendingBatchExpiry).and(expiry > 0)) {
      return pendingBatch;
    }

    return _withdrawalData.batches[expiry];
  }

  // ┌─ getAccountWithdrawalStatus ─────
  /// @notice read the account's scaled batch share and amount already claimed.
  ///
  /// @param accountAddress lender whose batch position is queried.
  /// @param expiry         batch key and scheduled expiry timestamp.
  ///
  /// @return status lender's stored position in the batch.
  function getAccountWithdrawalStatus(
    address accountAddress,
    uint32 expiry
  )
    external
    view
    nonReentrantView
    returns (AccountWithdrawalStatus memory status)
  {
    AccountWithdrawalStatus storage _status = _withdrawalData.accountStatuses[expiry][accountAddress];
    status.scaledAmount = _status.scaledAmount;
    status.normalizedAmountWithdrawn = _status.normalizedAmountWithdrawn;
  }
}

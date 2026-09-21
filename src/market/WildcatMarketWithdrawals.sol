// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './WildcatMarketBase.sol';
import '../libraries/LibERC20.sol';
import '../libraries/BoolUtils.sol';

/// @notice batched lender exit flow with FIFO payment priority across expired batches.
contract WildcatMarketWithdrawals is WildcatMarketBase {
  using LibERC20 for address;
  using MathUtils for uint256;
  using MathUtils for bool;
  using SafeCastLib for uint256;
  using BoolUtils for bool;

  // ========================================================================== //
  //                             Withdrawal Queries                             //
  // ========================================================================== //

  /// @notice returns expired, underfunded batch expiries in payment order.
  /// @return expiries oldest unpaid batch first.
  function getUnpaidBatchExpiries() external view nonReentrantView returns (uint32[] memory) {
    return _withdrawalData.unpaidBatches.values();
  }

  /// @notice returns aggregate accounting for the batch at `expiry`.
  /// @dev if it is the current batch, the result includes interest and payments calculable through
  ///      this block without writing state.
  /// @param expiry batch key and scheduled expiry timestamp.
  /// @return batch current aggregate accounting for that key.
  function getWithdrawalBatch(
    uint32 expiry
  ) external view nonReentrantView returns (WithdrawalBatch memory batch) {
    (, uint32 pendingBatchExpiry, WithdrawalBatch memory pendingBatch) = _calculateCurrentState();
    if ((expiry == pendingBatchExpiry).and(expiry > 0)) {
      return pendingBatch;
    }

    WithdrawalBatch storage _batch = _withdrawalData.batches[expiry];
    batch.scaledTotalAmount = _batch.scaledTotalAmount;
    batch.scaledAmountBurned = _batch.scaledAmountBurned;
    batch.normalizedAmountPaid = _batch.normalizedAmountPaid;
  }

  /// @notice returns `accountAddress`'s fixed share and amount already claimed from a batch.
  /// @param accountAddress lender whose batch position is queried.
  /// @param expiry batch key and scheduled expiry timestamp.
  /// @return status lender's stored position in the batch.
  function getAccountWithdrawalStatus(
    address accountAddress,
    uint32 expiry
  ) external view nonReentrantView returns (AccountWithdrawalStatus memory status) {
    AccountWithdrawalStatus storage _status = _withdrawalData.accountStatuses[expiry][
      accountAddress
    ];
    status.scaledAmount = _status.scaledAmount;
    status.normalizedAmountWithdrawn = _status.normalizedAmountWithdrawn;
  }

  /// @notice returns the additional amount `accountAddress` can claim from an expired batch.
  /// @dev uses the batch's currently reserved assets and reverts while the batch is still current.
  /// @param accountAddress lender whose claim is queried.
  /// @param expiry batch key and scheduled expiry timestamp.
  /// @return currently claimable underlying assets.
  function getAvailableWithdrawalAmount(
    address accountAddress,
    uint32 expiry
  ) external view nonReentrantView returns (uint256) {
    if (expiry >= block.timestamp) {
      revert_WithdrawalBatchNotExpired();
    }
    (, uint32 pendingBatchExpiry, WithdrawalBatch memory pendingBatch) = _calculateCurrentState();
    WithdrawalBatch memory batch;
    if (expiry == pendingBatchExpiry) {
      batch = pendingBatch;
    } else {
      batch = _withdrawalData.batches[expiry];
    }
    AccountWithdrawalStatus memory status = _withdrawalData.accountStatuses[expiry][accountAddress];
    // Rounding errors will lead to some dust accumulating in the batch, but the cost of
    // executing a withdrawal will be lower for users.
    uint256 previousTotalWithdrawn = status.normalizedAmountWithdrawn;
    uint256 newTotalWithdrawn = uint256(batch.normalizedAmountPaid).mulDiv(
      status.scaledAmount,
      batch.scaledTotalAmount
    );
    return newTotalWithdrawn - previousTotalWithdrawn;
  }

  // ========================================================================== //
  //                             Withdrawal Actions                             //
  // ========================================================================== //

  /// @dev moves scaled shares from an account into the current batch, creating one when needed.
  ///      any currently available liquidity is reserved for the batch before state is stored.
  function _queueWithdrawal(
    MarketState memory state,
    Account memory account,
    address accountAddress,
    uint104 scaledAmount,
    uint normalizedAmount,
    uint baseCalldataSize
  ) internal returns (uint32 expiry) {
    // Cache batch expiry on the stack for gas savings
    expiry = state.pendingWithdrawalExpiry;

    // If there is no pending withdrawal batch, create a new one.
    if (expiry == 0) {
      // If the market is closed, use zero for withdrawal batch duration.
      uint duration = state.isClosed.ternary(0, withdrawalBatchDuration);
      expiry = (block.timestamp + duration).toUint32();

      // Reopening a processed batch mixes pre- and post-close accounting,
      // shifting value between withdrawers.
      if (state.isClosed && _withdrawalData.batches[expiry].scaledTotalAmount != 0) {
        expiry += 1;
        if (_withdrawalData.batches[expiry].scaledTotalAmount != 0) {
          revert_WithdrawalBatchKeyAlreadyExists();
        }
      }

      emit_WithdrawalBatchCreated(expiry);
      state.pendingWithdrawalExpiry = expiry;
    }

    // Execute queueWithdrawal hook if enabled
    hooks.onQueueWithdrawal(accountAddress, expiry, scaledAmount, state, baseCalldataSize);

    // Reduce account's balance and emit transfer event
    account.scaledBalance -= scaledAmount;
    _accounts[accountAddress] = account;

    emit_Transfer(accountAddress, address(this), normalizedAmount);

    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];

    // Add scaled withdrawal amount to account withdrawal status, withdrawal batch and market state.
    _withdrawalData.accountStatuses[expiry][accountAddress].scaledAmount += scaledAmount;
    batch.scaledTotalAmount += scaledAmount;
    state.scaledPendingWithdrawals += scaledAmount;

    emit_WithdrawalQueued(expiry, accountAddress, scaledAmount, normalizedAmount);

    // Burn as much of the withdrawal batch as possible with available liquidity.
    uint256 currentTotalAssets = totalAssets();
    uint256 availableLiquidity = batch.availableLiquidityForPendingBatch(
      state,
      currentTotalAssets
    );
    if (availableLiquidity > 0) {
      _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity);
    }

    // Update stored batch data
    _withdrawalData.batches[expiry] = batch;

    // Update stored state
    _writeState(state, currentTotalAssets);
  }

  /// @notice queues the floor-scaled portion of `amount` normalized market tokens.
  /// @param amount normalized amount used to derive the scaled request.
  /// @return expiry batch joined or created by this request.
  function queueWithdrawal(
    uint256 amount
  ) external nonReentrant sphereXGuardExternal returns (uint32 expiry) {
    MarketState memory state = _getUpdatedState();

    uint104 scaledAmount = state.scaleAmountDown(amount).toUint104();
    if (scaledAmount == 0) revert_NullBurnAmount();

    // Cache account data
    Account memory account = _getAccount(msg.sender);

    return
      _queueWithdrawal(state, account, msg.sender, scaledAmount, amount, _runtimeConstant(0x24));
  }

  /// @notice queues exactly `scaledAmount` scaled market tokens.
  /// @dev meant for integrations such as the canonical ERC-4626 wrapper that already account in
  ///      scaled shares and must not round through a normalized amount first.
  /// @param scaledAmount exact scaled shares to move into the batch.
  /// @return expiry batch joined or created by this request.
  function queueWithdrawalScaled(
    uint256 scaledAmount
  ) external nonReentrant sphereXGuardExternal returns (uint32 expiry) {
    MarketState memory state = _getUpdatedState();

    uint104 amount = scaledAmount.toUint104();
    if (amount == 0) revert_NullBurnAmount();

    // Cache account data
    Account memory account = _getAccount(msg.sender);

    uint256 normalizedAmount = state.normalizeAmount(amount);

    return
      _queueWithdrawal(
        state,
        account,
        msg.sender,
        amount,
        normalizedAmount,
        _runtimeConstant(0x24)
      );
  }

  /// @notice queues the caller's entire direct scaled market-token balance.
  /// @return expiry batch joined or created by this request.
  function queueFullWithdrawal()
    external
    nonReentrant
    sphereXGuardExternal
    returns (uint32 expiry)
  {
    MarketState memory state = _getUpdatedState();

    // Cache account data
    Account memory account = _getAccount(msg.sender);

    uint104 scaledAmount = account.scaledBalance;
    if (scaledAmount == 0) revert_NullBurnAmount();

    uint256 normalizedAmount = state.normalizeAmount(scaledAmount);

    return
      _queueWithdrawal(
        state,
        account,
        msg.sender,
        scaledAmount,
        normalizedAmount,
        _runtimeConstant(0x04)
      );
  }

  /// @notice claims `accountAddress`'s newly paid share of an expired batch.
  /// @dev permissionless. assets go to the account, or its sanctions escrow when currently
  ///      sanctioned. reverts when no additional amount is claimable.
  /// @param accountAddress lender that owns the claim and receives unsanctioned assets.
  /// @param expiry batch key and scheduled expiry timestamp.
  /// @return underlying assets transferred for this claim.
  function executeWithdrawal(
    address accountAddress,
    uint32 expiry
  ) public nonReentrant sphereXGuardExternal returns (uint256) {
    MarketState memory state = _getUpdatedState();
    // Use an obfuscated constant for the base calldata size to prevent solc
    // function specialization.
    uint256 normalizedAmountWithdrawn = _executeWithdrawal(
      state,
      accountAddress,
      expiry,
      _runtimeConstant(0x44)
    );
    // Update stored state
    _writeState(state);
    return normalizedAmountWithdrawn;
  }

  /// @notice claims several account/batch pairs in one transaction.
  /// @dev the arrays are paired by index. one invalid or empty claim reverts the whole call.
  /// @param accountAddresses lenders that own each claim.
  /// @param expiries batch key paired with each lender.
  /// @return amounts underlying assets transferred for each pair.
  function executeWithdrawals(
    address[] calldata accountAddresses,
    uint32[] calldata expiries
  ) external nonReentrant sphereXGuardExternal returns (uint256[] memory amounts) {
    if (accountAddresses.length != expiries.length) revert_InvalidArrayLength();

    amounts = new uint256[](accountAddresses.length);

    MarketState memory state = _getUpdatedState();

    for (uint256 i = 0; i < accountAddresses.length; i++) {
      // Use calldatasize() for baseCalldataSize to indicate no data should be passed as `extraData`
      amounts[i] = _executeWithdrawal(state, accountAddresses[i], expiries[i], msg.data.length);
    }
    // Update stored state
    _writeState(state);
    return amounts;
  }

  /// @dev settles one paid pro-rata claim and routes sanctioned accounts through escrow.
  function _executeWithdrawal(
    MarketState memory state,
    address accountAddress,
    uint32 expiry,
    uint baseCalldataSize
  ) internal returns (uint256) {
    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];
    if (expiry == state.pendingWithdrawalExpiry) revert_WithdrawalBatchNotExpired();

    AccountWithdrawalStatus storage status = _withdrawalData.accountStatuses[expiry][
      accountAddress
    ];

    uint128 newTotalWithdrawn = uint128(
      MathUtils.mulDiv(batch.normalizedAmountPaid, status.scaledAmount, batch.scaledTotalAmount)
    );

    uint128 normalizedAmountWithdrawn = newTotalWithdrawn - status.normalizedAmountWithdrawn;

    if (normalizedAmountWithdrawn == 0) revert_NullWithdrawalAmount();

    hooks.onExecuteWithdrawal(
      accountAddress,
      expiry,
      normalizedAmountWithdrawn,
      state,
      baseCalldataSize
    );

    status.normalizedAmountWithdrawn = newTotalWithdrawn;
    state.normalizedUnclaimedWithdrawals -= normalizedAmountWithdrawn;

    if (_isSanctioned(accountAddress)) {
      // Get or create an escrow contract for the lender and transfer the owed amount to it.
      // They will be unable to withdraw from the escrow until their sanctioned
      // status is lifted on Chainalysis, or until the borrower overrides it.
      address escrow = _createEscrowForUnderlyingAsset(accountAddress);
      asset.safeTransfer(escrow, normalizedAmountWithdrawn);

      // Emit `SanctionedAccountWithdrawalSentToEscrow` event using a custom emitter.
      emit_SanctionedAccountWithdrawalSentToEscrow(
        accountAddress,
        escrow,
        expiry,
        normalizedAmountWithdrawn
      );
    } else {
      asset.safeTransfer(accountAddress, normalizedAmountWithdrawn);
    }

    emit_WithdrawalExecuted(expiry, accountAddress, normalizedAmountWithdrawn);

    return normalizedAmountWithdrawn;
  }

  /// @notice optionally repays debt, then applies available liquidity to old batches in FIFO order.
  /// @dev processes at most `maxBatches` and stops early when liquidity runs out. a zero repayment
  ///      is allowed, which makes this the bounded queue-maintenance path before market closure.
  /// @param repayAmount underlying assets to transfer from the caller, or zero.
  /// @param maxBatches upper bound on expired unpaid batches to process.
  function repayAndProcessUnpaidWithdrawalBatches(
    uint256 repayAmount,
    uint256 maxBatches
  ) public virtual nonReentrant sphereXGuardExternal {
    // Repay before updating state to ensure the paid amount is counted towards
    // any pending or unpaid withdrawals.
    if (repayAmount > 0) {
      asset.safeTransferFrom(msg.sender, address(this), repayAmount);
      emit_DebtRepaid(msg.sender, repayAmount);
    }

    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_RepayToClosedMarket();

    // Use an obfuscated constant for the base calldata size to prevent solc
    // function specialization.
    uint256 currentTotalAssets;
    if (repayAmount > 0) {
      hooks.onRepay(repayAmount, state, _runtimeConstant(0x44));
      currentTotalAssets = _onRepayAndGetTotalAssets(state, repayAmount);
    } else {
      currentTotalAssets = totalAssets();
    }

    // Calculate assets available to process the first batch - will be updated after each batch
    uint256 availableLiquidity = currentTotalAssets.satSub(
      state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees
    );

    // Get the maximum number of batches to process
    uint256 numBatches = MathUtils.min(maxBatches, _withdrawalData.unpaidBatches.length());

    uint256 i;
    // Process up to `maxBatches` unpaid batches while there is available liquidity
    while (i < numBatches && availableLiquidity > 0) {
      // Process the next unpaid batch using available liquidity
      uint256 normalizedAmountPaid = _processUnpaidWithdrawalBatch(state, availableLiquidity);
      // Reduce liquidity available to next batch
      availableLiquidity = availableLiquidity.satSub(normalizedAmountPaid);
      unchecked {
        ++i;
      }
    }
    _writeState(state, currentTotalAssets);
  }

  /// @dev pays the oldest unpaid batch and removes it from the queue once fully funded.
  function _processUnpaidWithdrawalBatch(
    MarketState memory state,
    uint256 availableLiquidity
  ) internal returns (uint256 normalizedAmountPaid) {
    // Get the next unpaid batch timestamp from storage (reverts if none)
    uint32 expiry = _withdrawalData.unpaidBatches.first();

    // Cache batch data in memory
    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];

    // Pay up to the available liquidity to the batch
    (, normalizedAmountPaid) = _applyWithdrawalBatchPayment(
      batch,
      state,
      expiry,
      availableLiquidity
    );

    // Update stored batch
    _withdrawalData.batches[expiry] = batch;

    // Remove batch from unpaid set if fully paid
    if (batch.scaledTotalAmount == batch.scaledAmountBurned) {
      _withdrawalData.unpaidBatches.shift();
      emit_WithdrawalBatchClosed(expiry);
    }
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './WildcatMarketBase.sol';
import './WildcatMarketConfig.sol';
import './WildcatMarketToken.sol';
import './WildcatMarketWithdrawals.sol';

/// @notice standard Wildcat credit market with interest on the full normalized supply.
contract WildcatMarket is
  WildcatMarketBase,
  WildcatMarketConfig,
  WildcatMarketToken,
  WildcatMarketWithdrawals
{
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  using LibERC20 for address;
  using BoolUtils for bool;

  /// @notice applies accrued interest and fees, processes an expired current batch, and stores
  ///         the market's current delinquency status.
  /// @dev permissionless. nothing accrues twice when called again at the same timestamp.
  function updateState() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    _writeState(state);
  }

  /// @notice sends the market's entire balance of an unrelated token to the borrower.
  /// @dev the underlying asset and the market token can't be rescued.
  /// @param token token accidentally sent to the market.
  function rescueTokens(address token) external nonReentrant onlyBorrower {
    if ((token == asset).or(token == address(this))) {
      revert_BadRescueAsset();
    }
    token.safeTransferAll(msg.sender);
  }

  /// @dev deposits up to `amount`, capped by current capacity, and mints floor-scaled shares.
  ///      reverts if the market is closed, the result is below one scaled token, access fails,
  ///      or the hook rejects the deposit.
  /// @return underlying assets deposited.
  function _depositUpTo(
    uint256 amount
  ) internal virtual nonReentrant returns (uint256 /* actualAmount */) {
    // Get current state
    MarketState memory state = _getUpdatedState();

    if (state.isClosed) revert_DepositToClosedMarket();

    // Reduce amount if it would exceed the maximum deposit (maxTotalSupply - totalSupply)
    amount = MathUtils.min(amount, state.maximumDeposit());

    // Scale the mint amount
    uint104 scaledAmount = state.scaleAmountDown(amount).toUint104();
    if (scaledAmount == 0) revert_NullMintAmount();

    // Cache account data and revert if not authorized to deposit.
    Account memory account = _getAccount(msg.sender);

    hooks.onDeposit(msg.sender, scaledAmount, state);

    // Transfer deposit from caller
    asset.safeTransferFrom(msg.sender, address(this), amount);

    account.scaledBalance += scaledAmount;
    _accounts[msg.sender] = account;

    emit_Transfer(_runtimeConstant(address(0)), msg.sender, amount);
    emit_Deposit(msg.sender, amount, scaledAmount);

    // Increase supply
    state.scaledTotalSupply += scaledAmount;

    // Update stored state
    _writeState(state);

    return amount;
  }

  /// @notice deposits as much of `amount` as current capacity allows.
  /// @dev mints floor-scaled shares. reverts instead of succeeding with less than one share.
  /// @param amount maximum underlying assets to transfer from the caller.
  /// @return assets deposited, which may be lower than `amount`.
  function depositUpTo(
    uint256 amount
  ) external virtual sphereXGuardExternal returns (uint256 /* actualAmount */) {
    return _depositUpTo(amount);
  }

  /// @notice deposits exactly `amount` underlying assets for the caller.
  /// @dev reverts if capacity is lower than `amount` or the floor-scaled mint is zero.
  /// @param amount underlying assets to transfer from the caller.
  function deposit(uint256 amount) external virtual sphereXGuardExternal {
    uint256 actualAmount = _depositUpTo(amount);
    if (amount != actualAmount) revert_MaxSupplyExceeded();
  }

  /// @notice sends all currently withdrawable protocol fees to `feeRecipient`.
  /// @dev permissionless. paid-but-unclaimed withdrawals have priority over protocol fees.
  function collectFees() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    if (state.accruedProtocolFees == 0) revert_NullFeeAmount();

    uint128 withdrawableFees = state.withdrawableProtocolFees(totalAssets());
    if (withdrawableFees == 0) revert_InsufficientReservesForFeeWithdrawal();

    state.accruedProtocolFees -= withdrawableFees;
    asset.safeTransfer(feeRecipient, withdrawableFees);
    _writeState(state);
    emit_FeesCollected(msg.sender, feeRecipient, withdrawableFees);
  }

  /// @notice draws `amount` underlying assets to the operational borrower.
  /// @dev can't exceed assets left after every collateral obligation. raw Chainalysis flags on
  ///      either the borrower or principal block the draw even when a sentinel override exists.
  /// @param amount underlying assets to draw.
  function borrow(uint256 amount) external virtual onlyBorrower nonReentrant sphereXGuardExternal {
    // Check the raw Chainalysis status of both borrower identities. Sentinel overrides
    // must not let either identity draw while flagged.
    address currentBorrower = msg.sender;
    address currentPrincipal = borrowerPrincipal();
    if (_flaggedBorrowerIdentity(currentBorrower, currentPrincipal) != address(0)) {
      revert_BorrowWhileSanctioned();
    }

    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_BorrowFromClosedMarket();

    uint256 borrowable = state.borrowableAssets(totalAssets());
    if (amount > borrowable) revert_BorrowAmountTooHigh();

    // Execute borrow hook if enabled
    hooks.onBorrow(amount, state);

    _onBorrow(state, amount);
    asset.safeTransfer(msg.sender, amount);
    _writeState(state);
    emit_Borrow(currentBorrower, amount);
  }

  /// @dev pulls a nonzero repayment, runs the hook, and lets derived markets reconcile it.
  function _repay(
    MarketState memory state,
    uint256 amount,
    uint256 baseCalldataSize
  ) internal virtual {
    if (amount == 0) revert_NullRepayAmount();
    if (state.isClosed) revert_RepayToClosedMarket();

    asset.safeTransferFrom(msg.sender, address(this), amount);
    emit_DebtRepaid(msg.sender, amount);

    // Execute repay hook if enabled
    hooks.onRepay(amount, state, baseCalldataSize);
    _onRepay(state, amount);
  }

  /// @notice transfers `amount` underlying assets into the market as debt repayment.
  /// @dev anyone can repay, but the market credits no tokens or repayment claim to the caller.
  ///      on revolving markets it also reduces drawn principal.
  /// @param amount nonzero underlying assets to transfer from the caller.
  function repay(uint256 amount) external virtual nonReentrant sphereXGuardExternal {
    if (amount == 0) revert_NullRepayAmount();

    asset.safeTransferFrom(msg.sender, address(this), amount);
    emit_DebtRepaid(msg.sender, amount);

    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_RepayToClosedMarket();

    // Execute repay hook if enabled
    hooks.onRepay(amount, state, _runtimeConstant(0x24));
    uint256 currentTotalAssets = _onRepayAndGetTotalAssets(state, amount);

    _writeState(state, currentTotalAssets);
  }

  /// @notice fully collateralizes and permanently closes the market.
  /// @dev pulls any shortfall from the borrower or returns excess assets, sets APR to zero and
  ///      reserves to 100%, then pays every withdrawal batch. unpaid batches make gas scale with
  ///      queue length, so they can be processed incrementally before closure.
  function closeMarket() external virtual onlyBorrower nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();

    if (state.isClosed) revert_MarketAlreadyClosed();
    uint256 previousAnnualInterestBips = state.annualInterestBips;
    uint256 previousReserveRatioBips = state.reserveRatioBips;

    uint256 currentlyHeld = totalAssets();
    uint256 totalDebts = state.totalDebts();
    if (currentlyHeld < totalDebts) {
      // Transfer remaining debts from borrower
      uint256 remainingDebt = totalDebts - currentlyHeld;
      _repay(state, remainingDebt, 0x04);
      currentlyHeld += remainingDebt;
    } else if (currentlyHeld > totalDebts) {
      uint256 excessDebt = currentlyHeld - totalDebts;
      // Transfer excess assets to borrower
      asset.safeTransfer(msg.sender, excessDebt);
      currentlyHeld -= excessDebt;
    }
    hooks.onCloseMarket(state);
    state.annualInterestBips = 0;
    state.isClosed = true;
    state.reserveRatioBips = 10000;
    // Ensures that delinquency fee doesn't increase scale factor further
    // as doing so would mean last lender in market couldn't fully redeem
    state.timeDelinquent = 0;

    // Still track available liquidity in case of a rounding error
    uint256 availableLiquidity = currentlyHeld.satSub(
      state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees
    );

    // If there is a pending withdrawal batch which is not fully paid off, set aside
    // up to the available liquidity for that batch.
    if (state.pendingWithdrawalExpiry != 0) {
      uint32 expiry = state.pendingWithdrawalExpiry;
      WithdrawalBatch memory batch = _withdrawalData.batches[expiry];
      if (batch.scaledAmountBurned < batch.scaledTotalAmount) {
        (, uint128 normalizedAmountPaid) = _applyWithdrawalBatchPayment(
          batch,
          state,
          expiry,
          availableLiquidity
        );
        availableLiquidity -= normalizedAmountPaid;
        _withdrawalData.batches[expiry] = batch;
      }

      // Remove the pending batch to ensure new withdrawals are not
      // added to it after the market is closed.
      state.pendingWithdrawalExpiry = 0;
      emit_WithdrawalBatchExpired(
        expiry,
        batch.scaledTotalAmount,
        batch.scaledAmountBurned,
        batch.normalizedAmountPaid
      );
      emit_WithdrawalBatchClosed(expiry);

      // If the batch expiry is at the time of the market's closure, create
      // a new empty batch that expires in one second to ensure new batches
      // aren't created after the market is closed with the same expiry.
      if (expiry == block.timestamp) {
        uint32 newExpiry = expiry + 1;
        emit_WithdrawalBatchCreated(newExpiry);
        state.pendingWithdrawalExpiry = newExpiry;
      }
    }

    uint256 numBatches = _withdrawalData.unpaidBatches.length();
    for (uint256 i; i < numBatches; i++) {
      // Process the next unpaid batch using available liquidity
      uint256 normalizedAmountPaid = _processUnpaidWithdrawalBatch(state, availableLiquidity);
      // Reduce liquidity available to next batch
      availableLiquidity -= normalizedAmountPaid;
    }

    if (state.scaledPendingWithdrawals != 0) {
      revert_CloseMarketWithUnpaidWithdrawals();
    }

    _onCloseMarket();
    _writeState(state);
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      msg.sender,
      previousAnnualInterestBips,
      state.annualInterestBips,
      previousReserveRatioBips,
      state.reserveRatioBips
    );
    emit_MarketClosed(msg.sender, block.timestamp);
  }

  /**
   * @dev Queues a full withdrawal of a sanctioned account's assets.
   */
  function _blockAccount(MarketState memory state, address accountAddress) internal override {
    Account memory account = _accounts[accountAddress];
    if (account.scaledBalance > 0) {
      uint104 scaledAmount = account.scaledBalance;

      uint256 normalizedAmount = state.normalizeAmount(scaledAmount);

      // caf-03 attempted to bypass `onQueueWithdrawal` here so sanctions withdrawals
      // could not be vetoed. That bypass also skips term withdrawal restrictions
      // (fixed-term end times, periodic withdrawal windows), so `nukeFromOrbit`
      // intentionally uses the ordinary withdrawal path: quarantine can be
      // deferred until withdrawals open. Accepted behavior; see Known Issues.
      uint32 expiry = _queueWithdrawal(
        state,
        account,
        accountAddress,
        scaledAmount,
        normalizedAmount,
        msg.data.length
      );

      emit_SanctionedAccountAssetsQueuedForWithdrawal(
        accountAddress,
        expiry,
        scaledAmount,
        normalizedAmount
      );
    }
  }
}

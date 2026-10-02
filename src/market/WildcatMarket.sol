// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WildcatMarket
// ║  ██▀▀     ▀▀██   Deposits, borrowing, repayment, and market settlement.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  DEPOSITS
// ║  deposit(...)
// ║  depositUpTo(...)
// ║  _depositUpTo(...)
// ║
// ║  BORROWING
// ║  borrow(...)
// ║
// ║  REPAYMENT
// ║  repay(...)
// ║  _repay(...)
// ║
// ║  PROTOCOL FEES
// ║  collectFees()
// ║
// ║  CLOSURE AND RECOVERY
// ║  closeMarket()
// ║  rescueTokens(...)
// ║
// ║  STATE CHECKPOINTING
// ║  updateState()
// ║
// ║  SANCTIONS
// ║  _blockAccount(...)
// ╚═════

import './WildcatMarketBase.sol';
import './WildcatMarketConfig.sol';
import './WildcatMarketToken.sol';
import './WildcatMarketWithdrawals.sol';

// ┌─ WildcatMarket ────────────────────────────────────────────────────────────
/// @notice standard Wildcat credit market with interest on the full normalized supply.
contract WildcatMarket is WildcatMarketBase, WildcatMarketConfig, WildcatMarketToken, WildcatMarketWithdrawals {
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  using LibERC20 for address;
  using BoolUtils for bool;

  // ░░▒▒▓▓██ [ DEPOSITS ] ─────────────────────────────────────────────────────

  // ┌─ deposit ─────
  /// @notice deposits exactly `amount` underlying assets for the caller.
  ///
  /// @dev reverts if capacity is lower than `amount` or the floor-scaled mint is zero.
  ///
  /// @param amount underlying assets to transfer from the caller.
  function deposit(uint256 amount) external virtual sphereXGuardExternal {
    uint256 actualAmount = _depositUpTo(amount);
    if (amount != actualAmount) revert_MaxSupplyExceeded();
  }

  // ┌─ depositUpTo ─────
  /// @notice deposits as much of `amount` as current capacity allows.
  ///
  /// @dev mints floor-scaled shares. reverts instead of succeeding with less than one share.
  ///
  /// @param amount maximum underlying assets to transfer from the caller.
  ///
  /// @return assets deposited, which may be lower than `amount`.
  function depositUpTo(uint256 amount)
    external
    virtual
    sphereXGuardExternal
    returns (
      uint256 /* actualAmount */
    )
  {
    return _depositUpTo(amount);
  }

  // ┌─ _depositUpTo ─────
  /// @dev deposits up to `amount`, capped by current capacity, and mints floor-scaled shares.
  ///      reverts if the market is closed, the result is below one scaled token, access fails,
  ///      or the hook rejects the deposit.
  ///
  /// @return underlying assets deposited.
  function _depositUpTo(uint256 amount)
    internal
    virtual
    nonReentrant
    returns (
      uint256 /* actualAmount */
    )
  {
    MarketState memory state = _getUpdatedState();

    if (state.isClosed) revert_DepositToClosedMarket();
    if (_isInRepayment()) revert_MarketInRepayment();

    // capacity limits new deposits, not interest already owed to lenders.
    amount = MathUtils.min(amount, state.maximumDeposit());

    uint104 scaledAmount = state.scaleAmountDown(amount).toUint104();
    if (scaledAmount == 0) revert_NullMintAmount();

    // sanctions checks still apply before hook admission.
    Account memory account = _getAccount(msg.sender);

    hooks.onDeposit(msg.sender, scaledAmount, state);

    asset.safeTransferFrom(msg.sender, address(this), amount);

    account.scaledBalance += scaledAmount;
    _accounts[msg.sender] = account;

    emit_Transfer(_runtimeConstant(address(0)), msg.sender, amount);
    emit_Deposit(msg.sender, amount, scaledAmount);

    state.scaledTotalSupply += scaledAmount;

    _writeState(state);

    return amount;
  }

  // ░░▒▒▓▓██ [ BORROWING ] ────────────────────────────────────────────────────

  // ┌─ borrow ─────
  /// @notice draw `amount` underlying assets to the operational borrower.
  ///
  /// @dev can't exceed assets left after every collateral obligation. raw Chainalysis flags on
  ///      either the borrower or principal block the draw even when a sentinel override exists.
  ///
  /// @param amount underlying assets to draw.
  function borrow(uint256 amount) external virtual onlyBorrower nonReentrant sphereXGuardExternal {
    // raw Chainalysis flags block either borrower identity. sentinel overrides don't permit a draw.
    address currentBorrower = msg.sender;
    address currentPrincipal = borrowerPrincipal();
    if (_flaggedBorrowerIdentity(currentBorrower, currentPrincipal) != address(0)) {
      revert_BorrowWhileSanctioned();
    }

    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_BorrowFromClosedMarket();
    if (_isInRepayment()) revert_MarketInRepayment();

    uint256 borrowable = state.borrowableAssets(totalAssets());
    if (amount > borrowable) revert_BorrowAmountTooHigh();

    hooks.onBorrow(amount, state);

    _onBorrow(state, amount);
    asset.safeTransfer(msg.sender, amount);
    _writeState(state);
    emit_Borrow(currentBorrower, amount);
  }

  // ░░▒▒▓▓██ [ REPAYMENT ] ────────────────────────────────────────────────────

  // ┌─ repay ─────
  /// @notice transfer `amount` underlying assets into the market as debt repayment.
  ///
  /// @dev anyone can repay, but the market credits no tokens or repayment claim to the caller.
  ///      on revolving markets it also reduces drawn principal.
  ///
  /// @param amount nonzero underlying assets to transfer from the caller.
  function repay(uint256 amount) external virtual nonReentrant sphereXGuardExternal {
    if (amount == 0) revert_NullRepayAmount();

    asset.safeTransferFrom(msg.sender, address(this), amount);
    emit_DebtRepaid(msg.sender, amount);

    MarketState memory state = _getUpdatedState(_runtimeConstant(0) != 0);
    if (state.isClosed) revert_RepayToClosedMarket();

    hooks.onRepay(amount, state, _runtimeConstant(0x24));
    uint256 currentTotalAssets = _onRepayAndGetTotalAssets(state, amount);

    _writeState(state, currentTotalAssets);
  }

  // ┌─ _repay ─────
  /// @dev pulls a nonzero repayment, runs the hook, and lets derived markets reconcile it.
  function _repay(MarketState memory state, uint256 amount, uint256 baseCalldataSize) internal virtual {
    if (amount == 0) revert_NullRepayAmount();
    if (state.isClosed) revert_RepayToClosedMarket();

    asset.safeTransferFrom(msg.sender, address(this), amount);
    emit_DebtRepaid(msg.sender, amount);

    hooks.onRepay(amount, state, baseCalldataSize);
    _onRepay(state, amount);
  }

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  // ┌─ collectFees ─────
  /// @notice send all currently withdrawable protocol fees to `feeRecipient`.
  ///
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

  // ░░▒▒▓▓██ [ CLOSURE AND RECOVERY ] ─────────────────────────────────────────

  // ┌─ closeMarket ─────
  /// @notice fully collateralize and permanently close the market.
  ///
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
      uint256 remainingDebt = totalDebts - currentlyHeld;
      _repay(state, remainingDebt, 0x04);
      currentlyHeld += remainingDebt;
    } else if (currentlyHeld > totalDebts) {
      uint256 excessDebt = currentlyHeld - totalDebts;
      asset.safeTransfer(msg.sender, excessDebt);
      currentlyHeld -= excessDebt;
    }
    hooks.onCloseMarket(state);
    state.annualInterestBips = 0;
    state.isClosed = true;
    state.reserveRatioBips = 10000;
    // stop delinquency accrual too. further interest would leave the last lender short.
    state.timeDelinquent = 0;

    // track the actual liquidity left; don't assume rounding makes every batch fit.
    uint256 availableLiquidity = currentlyHeld.satSub(state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees);

    // fund the current batch before releasing it for claims.
    if (state.pendingWithdrawalExpiry != 0) {
      uint32 expiry = state.pendingWithdrawalExpiry;
      WithdrawalBatch memory batch = _withdrawalData.batches[expiry];
      if (batch.scaledAmountBurned < batch.scaledTotalAmount) {
        (, uint128 normalizedAmountPaid) = _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity);
        availableLiquidity -= normalizedAmountPaid;
      }
      batch.releaseRemainder(state);
      _withdrawalData.batches[expiry] = batch;

      // retire this batch so post-close withdrawals can't join its existing claims.
      state.pendingWithdrawalExpiry = 0;
      emit_WithdrawalBatchExpired(expiry, batch.scaledTotalAmount, batch.scaledAmountBurned, batch.normalizedAmountPaid);
      emit_WithdrawalBatchClosed(expiry);

      // closure at this exact expiry would reuse the key. reserve the next second
      // for a fresh, empty batch instead.
      if (expiry == block.timestamp) {
        uint32 newExpiry = expiry + 1;
        emit_WithdrawalBatchCreated(newExpiry);
        state.pendingWithdrawalExpiry = newExpiry;
      }
    }

    uint256 numBatches = _withdrawalData.unpaidBatches.length();
    for (uint256 i; i < numBatches; i++) {
      uint256 normalizedAmountPaid = _processUnpaidWithdrawalBatch(state, availableLiquidity);
      availableLiquidity -= normalizedAmountPaid;
    }

    if (state.scaledPendingWithdrawals != 0) {
      revert_CloseMarketWithUnpaidWithdrawals();
    }

    _onCloseMarket();
    _writeState(state);
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      msg.sender, previousAnnualInterestBips, state.annualInterestBips, previousReserveRatioBips, state.reserveRatioBips
    );
    emit_MarketClosed(msg.sender, block.timestamp);
  }

  // ┌─ rescueTokens ─────
  /// @notice send unrelated tokens or surplus underlying assets after closure to the borrower.
  ///
  /// @dev totalDebts protects live shares, unpaid batches, paid claims, and protocol fees.
  ///      the market token can't be rescued. a failed surplus transfer affects only this call.
  ///
  /// @param token token to recover; underlying assets require a fully funded, closed market.
  function rescueTokens(address token) external nonReentrant onlyBorrower {
    if (token == address(this)) revert_BadRescueAsset();
    if (token == asset) {
      MarketState memory state = _getUpdatedState();
      if (!state.isClosed) revert_BadRescueAsset();
      uint256 totalDebts = state.totalDebts();
      token.safeTransfer(msg.sender, totalAssets() - totalDebts);
      _writeState(state, totalDebts);
    } else {
      token.safeTransferAll(msg.sender);
    }
  }

  // ░░▒▒▓▓██ [ STATE CHECKPOINTING ] ──────────────────────────────────────────

  // ┌─ updateState ─────
  /// @notice apply accrued interest and fees, process an expired current batch, and store
  ///         the market's current delinquency status.
  ///
  /// @dev permissionless. nothing accrues twice when called again at the same timestamp.
  function updateState() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    _writeState(state);
  }

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  // ┌─ _blockAccount ─────
  /// @dev queue the sanctioned account's full balance for withdrawal.
  function _blockAccount(MarketState memory state, address accountAddress) internal override {
    Account memory account = _accounts[accountAddress];
    if (account.scaledBalance > 0) {
      uint104 scaledAmount = account.scaledBalance;

      uint256 normalizedAmount = state.normalizeAmount(scaledAmount);

      // caf-03 tried bypassing `onQueueWithdrawal` to remove the sanctions-withdrawal veto.
      // that also bypasses fixed-term end times and periodic withdrawal windows.
      // keep `nukeFromOrbit` on the ordinary queue path: term restrictions can defer
      // quarantine until withdrawals open. accepted behavior; see Known Issues.
      uint32 expiry = _queueWithdrawal(state, account, accountAddress, scaledAmount, normalizedAmount, msg.data.length);

      emit_SanctionedAccountAssetsQueuedForWithdrawal(accountAddress, expiry, scaledAmount, normalizedAmount);
    }
  }
}

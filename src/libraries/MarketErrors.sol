// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketErrors
// ║  ██▀▀     ▀▀██   Compact market errors grouped by the operations they guard.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP AND CONFIGURATION
// ║  revert_InvalidRepaymentTerms()
// ║  revert_UnsupportedExecuteWithdrawalHook()
// ║  revert_NotFactory()
// ║  revert_CapacityChangeOnClosedMarket()
// ║  revert_AprChangeOnClosedMarket()
// ║  revert_AnnualInterestBipsTooHigh()
// ║  revert_ReserveRatioBipsTooHigh()
// ║  revert_RepaymentReserveRequired()
// ║  revert_InsufficientReservesForOldLiquidityRatio()
// ║  revert_InsufficientReservesForNewLiquidityRatio()
// ║  revert_ExecutePendingAprReductionNotEnabled()
// ║  revert_AprReductionNotReduction()
// ║
// ║  BORROWER AUTHORITY
// ║  revert_NotApprovedBorrower()
// ║  revert_NoPendingBorrowerTransfer()
// ║  revert_NotPendingBorrower()
// ║  revert_BorrowerTransferWhileSanctioned(...)
// ║
// ║  DEPOSITS AND TRANSFERS
// ║  revert_NotApprovedLender()
// ║  revert_DepositToClosedMarket()
// ║  revert_MaxSupplyExceeded()
// ║  revert_NullMintAmount()
// ║  revert_NullTransferAmount()
// ║
// ║  BORROWING AND REPAYMENT
// ║  revert_MarketInRepayment()
// ║  revert_BorrowWhileSanctioned()
// ║  revert_BorrowFromClosedMarket()
// ║  revert_BorrowAmountTooHigh()
// ║  revert_NullRepayAmount()
// ║  revert_RepayToClosedMarket()
// ║
// ║  PROTOCOL FEES
// ║  revert_NullFeeAmount()
// ║  revert_InsufficientReservesForFeeWithdrawal()
// ║  revert_ProtocolFeeTooHigh()
// ║  revert_ProtocolFeeRecipientRequired()
// ║  revert_ProtocolFeeChangeOnClosedMarket()
// ║
// ║  WITHDRAWALS
// ║  revert_NullBurnAmount()
// ║  revert_NullWithdrawalAmount()
// ║  revert_WithdrawalBatchKeyAlreadyExists()
// ║  revert_WithdrawalBatchNotExpired()
// ║  revert_InvalidArrayLength()
// ║
// ║  CLOSURE AND RECOVERY
// ║  revert_MarketAlreadyClosed()
// ║  revert_CloseMarketWithUnpaidWithdrawals()
// ║  revert_BadRescueAsset()
// ║
// ║  WRAPPERS AND SANCTIONS
// ║  revert_NotWrapperFactory()
// ║  revert_WrapperAlreadyRegistered()
// ║  revert_CannotNukeWrapper()
// ║  revert_BadLaunchCode()
// ║  revert_AccountBlocked()
// ╚═════
// ░░▒▒▓▓██ [ ERROR SELECTORS ] ────────────────────────────────────────────────

uint256 constant MaxSupplyExceeded_ErrorSelector = 0x8a164f63;

uint256 constant NotWrapperFactory_ErrorSelector = 0x3780ab27;

uint256 constant WrapperAlreadyRegistered_ErrorSelector = 0xbcfd1f3a;

uint256 constant CannotNukeWrapper_ErrorSelector = 0x812ab045;

uint256 constant CapacityChangeOnClosedMarket_ErrorSelector = 0x81b21078;

uint256 constant AprChangeOnClosedMarket_ErrorSelector = 0xb9de88a2;

uint256 constant AprReductionNotReduction_ErrorSelector = 0x116a7bf1;

uint256 constant ExecutePendingAprReductionNotEnabled_ErrorSelector = 0x52025ce9;

uint256 constant MarketAlreadyClosed_ErrorSelector = 0x449e5f50;

uint256 constant NotApprovedBorrower_ErrorSelector = 0x02171e6a;

uint256 constant NotApprovedLender_ErrorSelector = 0xe50a45ce;

uint256 constant BadLaunchCode_ErrorSelector = 0xa97ab167;

uint256 constant ReserveRatioBipsTooHigh_ErrorSelector = 0x8ec83073;

/*
code size: 25634
initcode size: 28024

errors: -48 runtime, -48 initcode
*/
uint256 constant AnnualInterestBipsTooHigh_ErrorSelector = 0xcf1f916f;

uint256 constant AccountBlocked_ErrorSelector = 0x6bc671fd;

uint256 constant BorrowAmountTooHigh_ErrorSelector = 0x119fe6e3;

uint256 constant BadRescueAsset_ErrorSelector = 0x11530cde;

uint256 constant InsufficientReservesForFeeWithdrawal_ErrorSelector = 0xf784cfa4;

uint256 constant WithdrawalBatchNotExpired_ErrorSelector = 0x2561b880;

uint256 constant WithdrawalBatchKeyAlreadyExists_ErrorSelector = 0x7867bc7e;

uint256 constant NullMintAmount_ErrorSelector = 0xe4aa5055;

uint256 constant NullBurnAmount_ErrorSelector = 0xd61c50f8;

uint256 constant NullFeeAmount_ErrorSelector = 0x45c835cb;

uint256 constant NullTransferAmount_ErrorSelector = 0xddee9b30;

uint256 constant NullWithdrawalAmount_ErrorSelector = 0x186334fe;

uint256 constant NullRepayAmount_ErrorSelector = 0x7e082088;

uint256 constant DepositToClosedMarket_ErrorSelector = 0x22d7c043;

uint256 constant RepayToClosedMarket_ErrorSelector = 0x61d1bc8f;

uint256 constant BorrowWhileSanctioned_ErrorSelector = 0x4a1c13a9;

uint256 constant BorrowFromClosedMarket_ErrorSelector = 0xd0242b28;

uint256 constant CloseMarketWithUnpaidWithdrawals_ErrorSelector = 0x4d790997;

uint256 constant InsufficientReservesForNewLiquidityRatio_ErrorSelector = 0x253ecbb9;

uint256 constant InsufficientReservesForOldLiquidityRatio_ErrorSelector = 0x0a68e5bf;

uint256 constant InvalidArrayLength_ErrorSelector = 0x9d89020a;

uint256 constant ProtocolFeeTooHigh_ErrorSelector = 0x499fddb1;

uint256 constant ProtocolFeeRecipientRequired_ErrorSelector = 0x84247ce2;

uint256 constant ProtocolFeeChangeOnClosedMarket_ErrorSelector = 0x37f1a75f;

uint256 constant NotFactory_ErrorSelector = 0x32cc7236;

// ░░▒▒▓▓██ [ SETUP AND CONFIGURATION ] ────────────────────────────────────────

// ┌─ revert_InvalidRepaymentTerms ─────
/// @dev same four-byte payload as `revert InvalidRepaymentTerms()`.
function revert_InvalidRepaymentTerms() pure {
  assembly {
    mstore(0, 0x2c0a3eec)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_UnsupportedExecuteWithdrawalHook ─────
/// @dev same four-byte payload as `revert UnsupportedExecuteWithdrawalHook()`.
function revert_UnsupportedExecuteWithdrawalHook() pure {
  assembly {
    mstore(0, 0xb9285f99)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NotFactory ─────
function revert_NotFactory() pure {
  assembly {
    mstore(0, 0x32cc7236)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_CapacityChangeOnClosedMarket ─────
/// @dev Equivalent to `revert CapacityChangeOnClosedMarket()`
function revert_CapacityChangeOnClosedMarket() pure {
  assembly {
    mstore(0, 0x81b21078)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_AprChangeOnClosedMarket ─────
/// @dev Equivalent to `revert AprChangeOnClosedMarket()`
function revert_AprChangeOnClosedMarket() pure {
  assembly {
    mstore(0, 0xb9de88a2)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_AnnualInterestBipsTooHigh ─────
/// @dev Equivalent to `revert AnnualInterestBipsTooHigh()`
function revert_AnnualInterestBipsTooHigh() pure {
  assembly {
    mstore(0, 0xcf1f916f)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_ReserveRatioBipsTooHigh ─────
/// @dev Equivalent to `revert ReserveRatioBipsTooHigh()`
function revert_ReserveRatioBipsTooHigh() pure {
  assembly {
    mstore(0, 0x8ec83073)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_RepaymentReserveRequired ─────
/// @dev same four-byte payload as `revert RepaymentReserveRequired()`.
function revert_RepaymentReserveRequired() pure {
  assembly {
    mstore(0, 0xfd97550f)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_InsufficientReservesForOldLiquidityRatio ─────
/// @dev Equivalent to `revert InsufficientReservesForOldLiquidityRatio()`
function revert_InsufficientReservesForOldLiquidityRatio() pure {
  assembly {
    mstore(0, 0x0a68e5bf)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_InsufficientReservesForNewLiquidityRatio ─────
/// @dev Equivalent to `revert InsufficientReservesForNewLiquidityRatio()`
function revert_InsufficientReservesForNewLiquidityRatio() pure {
  assembly {
    mstore(0, 0x253ecbb9)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_ExecutePendingAprReductionNotEnabled ─────
/// @dev Equivalent to `revert ExecutePendingAprReductionNotEnabled()`
function revert_ExecutePendingAprReductionNotEnabled() pure {
  assembly {
    mstore(0, 0x52025ce9)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_AprReductionNotReduction ─────
/// @dev Equivalent to `revert AprReductionNotReduction()`
function revert_AprReductionNotReduction() pure {
  assembly {
    mstore(0, 0x116a7bf1)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ BORROWER AUTHORITY ] ─────────────────────────────────────────────

// ┌─ revert_NotApprovedBorrower ─────
/// @dev Equivalent to `revert NotApprovedBorrower()`
function revert_NotApprovedBorrower() pure {
  assembly {
    mstore(0, 0x02171e6a)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NoPendingBorrowerTransfer ─────
/// @dev Equivalent to `revert NoPendingBorrowerTransfer()`
function revert_NoPendingBorrowerTransfer() pure {
  assembly {
    // `mstore` always writes a full 32-byte word. This four-byte selector literal
    // has 28 leading zero bytes, so starting at 0x1c skips that padding and
    // returns exactly the selector Solidity expects.
    mstore(0, 0x6b1ac6e2)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NotPendingBorrower ─────
/// @dev Equivalent to `revert NotPendingBorrower()`
function revert_NotPendingBorrower() pure {
  assembly {
    // This is the ABI encoding for a custom error with no arguments. Write the
    // selector as one word, skip its 28 bytes of left padding, and revert with
    // the remaining four bytes.
    mstore(0, 0x3505fe80)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_BorrowerTransferWhileSanctioned ─────
/// @dev Equivalent to `revert BorrowerTransferWhileSanctioned(account)`
function revert_BorrowerTransferWhileSanctioned(address account) pure {
  assembly {
    // A custom error uses the same basic ABI layout as a function call: four
    // selector bytes followed by one 32-byte word for each argument. The
    // selector occupies the last four bytes of the first word, and the address
    // occupies the next ABI word.
    mstore(0, 0xfe1f6916)
    mstore(0x20, account)
    // Start at byte 28 of the selector word and return 4 + 32 bytes.
    revert(0x1c, 0x24)
  }
}

// ░░▒▒▓▓██ [ DEPOSITS AND TRANSFERS ] ─────────────────────────────────────────

// ┌─ revert_NotApprovedLender ─────
/// @dev Equivalent to `revert NotApprovedLender()`
function revert_NotApprovedLender() pure {
  assembly {
    mstore(0, 0xe50a45ce)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_DepositToClosedMarket ─────
/// @dev Equivalent to `revert DepositToClosedMarket()`
function revert_DepositToClosedMarket() pure {
  assembly {
    mstore(0, 0x22d7c043)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_MaxSupplyExceeded ─────
/// @dev Equivalent to `revert MaxSupplyExceeded()`
function revert_MaxSupplyExceeded() pure {
  assembly {
    mstore(0, 0x8a164f63)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NullMintAmount ─────
/// @dev Equivalent to `revert NullMintAmount()`
function revert_NullMintAmount() pure {
  assembly {
    mstore(0, 0xe4aa5055)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NullTransferAmount ─────
/// @dev Equivalent to `revert NullTransferAmount()`
function revert_NullTransferAmount() pure {
  assembly {
    mstore(0, 0xddee9b30)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ BORROWING AND REPAYMENT ] ────────────────────────────────────────

// ┌─ revert_MarketInRepayment ─────
/// @dev same four-byte payload as `revert MarketInRepayment()`.
function revert_MarketInRepayment() pure {
  assembly {
    mstore(0, 0xd01b8cf8)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_BorrowWhileSanctioned ─────
/// @dev Equivalent to `revert BorrowWhileSanctioned()`
function revert_BorrowWhileSanctioned() pure {
  assembly {
    mstore(0, 0x4a1c13a9)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_BorrowFromClosedMarket ─────
/// @dev Equivalent to `revert BorrowFromClosedMarket()`
function revert_BorrowFromClosedMarket() pure {
  assembly {
    mstore(0, 0xd0242b28)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_BorrowAmountTooHigh ─────
/// @dev Equivalent to `revert BorrowAmountTooHigh()`
function revert_BorrowAmountTooHigh() pure {
  assembly {
    mstore(0, 0x119fe6e3)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NullRepayAmount ─────
/// @dev Equivalent to `revert NullRepayAmount()`
function revert_NullRepayAmount() pure {
  assembly {
    mstore(0, 0x7e082088)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_RepayToClosedMarket ─────
/// @dev Equivalent to `revert RepayToClosedMarket()`
function revert_RepayToClosedMarket() pure {
  assembly {
    mstore(0, 0x61d1bc8f)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ PROTOCOL FEES ] ──────────────────────────────────────────────────

// ┌─ revert_NullFeeAmount ─────
/// @dev Equivalent to `revert NullFeeAmount()`
function revert_NullFeeAmount() pure {
  assembly {
    mstore(0, 0x45c835cb)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_InsufficientReservesForFeeWithdrawal ─────
/// @dev Equivalent to `revert InsufficientReservesForFeeWithdrawal()`
function revert_InsufficientReservesForFeeWithdrawal() pure {
  assembly {
    mstore(0, 0xf784cfa4)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_ProtocolFeeTooHigh ─────
/// @dev Equivalent to `revert ProtocolFeeTooHigh()`
function revert_ProtocolFeeTooHigh() pure {
  assembly {
    mstore(0, 0x499fddb1)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_ProtocolFeeRecipientRequired ─────
/// @dev Equivalent to `revert ProtocolFeeRecipientRequired()`
function revert_ProtocolFeeRecipientRequired() pure {
  assembly {
    mstore(0, 0x84247ce2)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_ProtocolFeeChangeOnClosedMarket ─────
/// @dev Equivalent to `revert ProtocolFeeChangeOnClosedMarket()`
function revert_ProtocolFeeChangeOnClosedMarket() pure {
  assembly {
    mstore(0, 0x37f1a75f)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ WITHDRAWALS ] ────────────────────────────────────────────────────

// ┌─ revert_NullBurnAmount ─────
/// @dev Equivalent to `revert NullBurnAmount()`
function revert_NullBurnAmount() pure {
  assembly {
    mstore(0, 0xd61c50f8)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_NullWithdrawalAmount ─────
/// @dev Equivalent to `revert NullWithdrawalAmount()`
function revert_NullWithdrawalAmount() pure {
  assembly {
    mstore(0, 0x186334fe)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_WithdrawalBatchKeyAlreadyExists ─────
/// @dev Equivalent to `revert WithdrawalBatchKeyAlreadyExists()`
function revert_WithdrawalBatchKeyAlreadyExists() pure {
  assembly {
    mstore(0, 0x7867bc7e)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_WithdrawalBatchNotExpired ─────
/// @dev Equivalent to `revert WithdrawalBatchNotExpired()`
function revert_WithdrawalBatchNotExpired() pure {
  assembly {
    mstore(0, 0x2561b880)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_InvalidArrayLength ─────
/// @dev Equivalent to `revert InvalidArrayLength()`
function revert_InvalidArrayLength() pure {
  assembly {
    mstore(0, 0x9d89020a)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ CLOSURE AND RECOVERY ] ───────────────────────────────────────────

// ┌─ revert_MarketAlreadyClosed ─────
/// @dev Equivalent to `revert MarketAlreadyClosed()`
function revert_MarketAlreadyClosed() pure {
  assembly {
    mstore(0, 0x449e5f50)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_CloseMarketWithUnpaidWithdrawals ─────
/// @dev Equivalent to `revert CloseMarketWithUnpaidWithdrawals()`
function revert_CloseMarketWithUnpaidWithdrawals() pure {
  assembly {
    mstore(0, 0x4d790997)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_BadRescueAsset ─────
/// @dev Equivalent to `revert BadRescueAsset()`
function revert_BadRescueAsset() pure {
  assembly {
    mstore(0, 0x11530cde)
    revert(0x1c, 0x04)
  }
}

// ░░▒▒▓▓██ [ WRAPPERS AND SANCTIONS ] ─────────────────────────────────────────

// ┌─ revert_NotWrapperFactory ─────
/// @dev Equivalent to `revert NotWrapperFactory()`
function revert_NotWrapperFactory() pure {
  assembly {
    mstore(0, 0x3780ab27)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_WrapperAlreadyRegistered ─────
/// @dev Equivalent to `revert WrapperAlreadyRegistered()`
function revert_WrapperAlreadyRegistered() pure {
  assembly {
    mstore(0, 0xbcfd1f3a)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_CannotNukeWrapper ─────
/// @dev Equivalent to `revert CannotNukeWrapper()`
function revert_CannotNukeWrapper() pure {
  assembly {
    mstore(0, 0x812ab045)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_BadLaunchCode ─────
/// @dev Equivalent to `revert BadLaunchCode()`
function revert_BadLaunchCode() pure {
  assembly {
    mstore(0, 0xa97ab167)
    revert(0x1c, 0x04)
  }
}

// ┌─ revert_AccountBlocked ─────
/// @dev Equivalent to `revert AccountBlocked()`
function revert_AccountBlocked() pure {
  assembly {
    mstore(0, 0x6bc671fd)
    revert(0x1c, 0x04)
  }
}

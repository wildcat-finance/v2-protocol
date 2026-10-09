// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MarketErrors
//  \ ^ /   Market custom-error selectors, raised through `revertWithSelector`.
//    V
//
//  every value is `bytes4(keccak256("Name()"))` for the matching error declared in
//  IMarketEventsAndErrors or WildcatMarketBase. raise with
//  `revertWithSelector(Name_ErrorSelector)` or, for the one error with an argument,
//  `revertWithSelectorAndArgument(Name_ErrorSelector, arg)` from Errors.sol.
// ═════

import './Errors.sol';

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
uint256 constant InvalidRepaymentTerms_ErrorSelector = 0x2c0a3eec;
uint256 constant UnsupportedExecuteWithdrawalHook_ErrorSelector = 0xb9285f99;
uint256 constant RepaymentReserveRequired_ErrorSelector = 0xfd97550f;
uint256 constant NoPendingBorrowerTransfer_ErrorSelector = 0x6b1ac6e2;
uint256 constant NotPendingBorrower_ErrorSelector = 0x3505fe80;
uint256 constant BorrowerTransferWhileSanctioned_ErrorSelector = 0xfe1f6916;
uint256 constant MarketInRepayment_ErrorSelector = 0xd01b8cf8;

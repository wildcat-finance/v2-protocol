// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { MarketState } from '../libraries/MarketState.sol';

/// @notice shared market events and custom errors.
interface IMarketEventsAndErrors {
  /// @notice an exact deposit request exceeds the market's current normalized capacity.
  error MaxSupplyExceeded();

  /// @notice the caller is not the market's current operational borrower.
  error NotApprovedBorrower();

  /// @notice the lender isn't approved by the market's access policy.
  error NotApprovedLender();

  /// @notice the caller is not the factory that deployed the market.
  error NotFactory();

  /// @notice the caller is not the canonical wrapper factory.
  error NotWrapperFactory();

  /// @notice this market already has a canonical wrapper.
  error WrapperAlreadyRegistered();

  /// @notice the canonical wrapper can't be quarantined as a lender account.
  error CannotNukeWrapper();

  /// @notice the target isn't currently sanctioned.
  error BadLaunchCode();

  /// @notice the account is sanctioned in the market's current borrower-principal namespace.
  error AccountBlocked();

  /// @notice the borrower tried to rescue the underlying asset or market token.
  error BadRescueAsset();

  /// @notice the requested borrow exceeds currently borrowable assets.
  error BorrowAmountTooHigh();

  /// @notice accrued protocol fees exist, but higher-priority reserves leave none withdrawable.
  error InsufficientReservesForFeeWithdrawal();

  /// @notice the requested withdrawal batch hasn't expired yet.
  error WithdrawalBatchNotExpired();

  /// @notice a batch already exists for the requested expiry.
  error WithdrawalBatchKeyAlreadyExists();

  /// @notice the capacity-capped deposit amount scales down to zero.
  error NullMintAmount();

  /// @notice a withdrawal request resolves to zero scaled tokens.
  error NullBurnAmount();

  /// @notice no protocol fees are currently accrued.
  error NullFeeAmount();

  /// @notice a transfer is zero or too small to move one scaled token.
  error NullTransferAmount();

  /// @notice an expired withdrawal claim has no additional assets available.
  error NullWithdrawalAmount();

  /// @notice the repayment amount is zero.
  error NullRepayAmount();

  /// @notice the market is already closed.
  error MarketAlreadyClosed();

  /// @notice deposits are disabled after market closure.
  error DepositToClosedMarket();

  /// @notice repayments through the market entry point are disabled after closure.
  error RepayToClosedMarket();

  /// @notice the borrower or its principal is raw-flagged and can't draw funds.
  error BorrowWhileSanctioned();

  /// @notice borrowing is disabled after market closure.
  error BorrowFromClosedMarket();

  /// @notice APR or reserve-ratio changes are disabled after market closure.
  error AprChangeOnClosedMarket();

  /// @notice supply-cap changes are disabled after market closure.
  error CapacityChangeOnClosedMarket();

  /// @notice protocol-fee changes are disabled after market closure.
  error ProtocolFeeChangeOnClosedMarket();

  /// @notice a proposed APR reduction did not actually reduce APR.
  error AprReductionNotReduction();

  /// @notice this market doesn't enable periodic-term APR reduction execution.
  error ExecutePendingAprReductionNotEnabled();

  /// @notice the market can't close while any withdrawal obligation remains unpaid.
  error CloseMarketWithUnpaidWithdrawals();

  /// @notice annual lender APR exceeds 10,000 bips.
  error AnnualInterestBipsTooHigh();

  /// @notice the reserve ratio exceeds 10,000 bips.
  error ReserveRatioBipsTooHigh();

  /// @notice the protocol fee exceeds 1,000 bips.
  error ProtocolFeeTooHigh();

  /// @notice a positive protocol fee requires a nonzero fee recipient.
  error ProtocolFeeRecipientRequired();

  /// @notice the borrower address is zero.
  error InvalidBorrower();

  /// @notice the configured identity registry belongs to a different ArchController or has bad ABI.
  error InvalidBorrowerIdentityRegistry();

  /// @notice the proposed borrower transfer is zero or leaves both borrower fields unchanged.
  error InvalidBorrowerTransferTarget();

  /// @notice no borrower transfer is pending.
  error NoPendingBorrowerTransfer();

  /// @notice the caller isn't the pending operational borrower.
  error NotPendingBorrower();

  /// @notice the pending account changed principals after the transfer was requested.
  /// @param expectedPrincipal principal pinned when the request was made.
  /// @param actualPrincipal principal currently resolved by the identity registry.
  error PendingBorrowerPrincipalChanged(address expectedPrincipal, address actualPrincipal);

  /// @notice the identity registry couldn't resolve the proposed borrower.
  error BorrowerIdentityNotFound();

  /// @notice the resolved principal is not registered with the ArchController.
  error BorrowerPrincipalNotRegistered();

  /// @notice an address is both a direct principal and a registered borrower account.
  error AmbiguousBorrowerIdentity();

  /// @notice a borrower transfer involves an address flagged by Chainalysis.
  /// @param account operational borrower or principal that is currently flagged.
  error BorrowerTransferWhileSanctioned(address account);

  /// @notice raising the reserve ratio would make the market delinquent.
  error InsufficientReservesForNewLiquidityRatio();

  /// @notice the market is already delinquent under its current reserve ratio.
  error InsufficientReservesForOldLiquidityRatio();

  /// @notice parallel batch arrays have different lengths.
  error InvalidArrayLength();

  /// @notice emitted when normalized market tokens move, mint, or burn.
  /// @param from token source; zero for mints.
  /// @param to token recipient; zero for burns.
  /// @param value normalized amount reported by the operation.
  event Transfer(address indexed from, address indexed to, uint256 value);

  /// @notice emitted when an owner sets a normalized market-token allowance.
  /// @param owner account granting the allowance.
  /// @param spender account allowed to spend the owner's tokens.
  /// @param value new normalized allowance.
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /// @notice emitted when the borrower changes the deposit cap.
  /// @param caller account that executed the change.
  /// @param previousMaxTotalSupply old normalized cap.
  /// @param newMaxTotalSupply new normalized cap.
  event MaxTotalSupplyUpdated(
    address indexed caller,
    uint256 previousMaxTotalSupply,
    uint256 newMaxTotalSupply
  );

  /// @notice emitted when the factory updates the market's protocol fee.
  /// @param caller factory that executed the change.
  /// @param previousProtocolFeeBips old protocol share of base interest, in bips.
  /// @param newProtocolFeeBips new protocol share of base interest, in bips.
  event ProtocolFeeBipsUpdated(
    address indexed caller,
    uint256 previousProtocolFeeBips,
    uint256 newProtocolFeeBips
  );

  /// @notice emitted when lender APR or the reserve ratio changes.
  /// @param caller account that executed the change.
  /// @param previousAnnualInterestBips old base annual lender rate, in bips.
  /// @param newAnnualInterestBips new base annual lender rate, in bips.
  /// @param previousReserveRatioBips old reserve requirement, in bips.
  /// @param newReserveRatioBips new reserve requirement, in bips.
  event AnnualInterestAndReserveRatioBipsUpdated(
    address indexed caller,
    uint256 previousAnnualInterestBips,
    uint256 newAnnualInterestBips,
    uint256 previousReserveRatioBips,
    uint256 newReserveRatioBips
  );

  /// @notice emitted when a sanctioned lender's full scaled balance enters a withdrawal batch.
  /// @param account sanctioned lender whose balance was queued.
  /// @param expiry batch receiving the balance.
  /// @param scaledAmount exact scaled balance queued.
  /// @param normalizedAmount value of the queued shares at queue time.
  event SanctionedAccountAssetsQueuedForWithdrawal(
    address indexed account,
    uint256 expiry,
    uint256 scaledAmount,
    uint256 normalizedAmount
  );

  /// @notice emitted after underlying assets are deposited and scaled tokens are minted.
  /// @param account lender that deposited and received the tokens.
  /// @param assetAmount underlying assets deposited.
  /// @param scaledAmount scaled shares minted.
  event Deposit(address indexed account, uint256 assetAmount, uint256 scaledAmount);

  /// @notice emitted when the borrower draws underlying assets.
  /// @param borrower operational borrower receiving the assets.
  /// @param assetAmount underlying assets drawn.
  event Borrow(address indexed borrower, uint256 assetAmount);

  /// @notice emitted when underlying assets are explicitly repaid through a market entry point.
  /// @param from account that supplied the repayment.
  /// @param assetAmount underlying assets repaid.
  event DebtRepaid(address indexed from, uint256 assetAmount);

  /// @notice emitted after final market settlement and closure.
  /// @param borrower operational borrower that closed the market.
  /// @param timestamp closure timestamp.
  event MarketClosed(address indexed borrower, uint256 timestamp);

  /// @notice emitted when withdrawable protocol fees are sent to `feeRecipient`.
  /// @param collector account that triggered collection.
  /// @param feeRecipient immutable recipient that received the assets.
  /// @param assets underlying assets transferred.
  event FeesCollected(
    address indexed collector,
    address indexed feeRecipient,
    uint256 assets
  );

  /// @notice emitted on each stored state write after delinquency is recalculated.
  /// @param scaleFactor stored ray-scaled ratio from scaled shares to normalized tokens.
  /// @param isDelinquent whether assets are below the resulting collateral obligation.
  event StateUpdated(uint256 scaleFactor, bool isDelinquent);

  /// @notice emitted for each accrual interval applied to market state.
  /// @param fromTimestamp start of the interval.
  /// @param toTimestamp end of the interval.
  /// @param scaleFactor scale factor after applying the interval.
  /// @param baseInterestRay base lender interest accrued over the interval, in ray.
  /// @param delinquencyFeeRay penalty interest accrued over the interval, in ray.
  /// @param protocolFees normalized protocol fees accrued over the interval.
  event InterestAndFeesAccrued(
    uint256 fromTimestamp,
    uint256 toTimestamp,
    uint256 scaleFactor,
    uint256 baseInterestRay,
    uint256 delinquencyFeeRay,
    uint256 protocolFees
  );

  /// @notice emitted when the canonical ERC-4626 wrapper is registered.
  /// @param wrapper canonical wrapper address.
  event WrapperRegistered(address indexed wrapper);

  /// @notice emitted when the borrower creates or replaces a pending transfer.
  /// @param borrower current operational borrower.
  /// @param previousPendingBorrower displaced pending borrower, or zero.
  /// @param pendingBorrower new operational borrower that can accept.
  /// @param borrowerPrincipal current registered principal.
  /// @param previousPendingBorrowerPrincipal principal displaced with the old request, or zero.
  /// @param pendingBorrowerPrincipal principal pinned for the new request.
  event BorrowerTransferRequested(
    address indexed borrower,
    address indexed previousPendingBorrower,
    address indexed pendingBorrower,
    address borrowerPrincipal,
    address previousPendingBorrowerPrincipal,
    address pendingBorrowerPrincipal
  );

  /// @notice emitted when the borrower clears a pending transfer.
  /// @param borrower current operational borrower.
  /// @param cancelledPendingBorrower operational address removed from the request.
  /// @param borrowerPrincipal current registered principal.
  /// @param cancelledPendingBorrowerPrincipal principal removed from the request.
  event BorrowerTransferCancelled(
    address indexed borrower,
    address indexed cancelledPendingBorrower,
    address borrowerPrincipal,
    address cancelledPendingBorrowerPrincipal
  );

  /// @notice emitted when the pending borrower accepts control of the market.
  /// @param previousBorrower former operational borrower.
  /// @param newBorrower accepted operational borrower.
  /// @param previousBorrowerPrincipal former registered principal.
  /// @param newBorrowerPrincipal accepted registered principal.
  event BorrowerTransferred(
    address indexed previousBorrower,
    address indexed newBorrower,
    address previousBorrowerPrincipal,
    address indexed newBorrowerPrincipal
  );

  // =====================================================================//
  //                          Withdrawal Events                           //
  // =====================================================================//

  /// @notice emitted when the current batch stops accepting requests and is classified.
  /// @param expiry batch key and scheduled expiry timestamp.
  /// @param scaledTotalAmount cumulative scaled requests in the batch.
  /// @param scaledAmountBurned scaled requests already paid and burned.
  /// @param normalizedAmountPaid underlying assets reserved for the paid portion.
  event WithdrawalBatchExpired(
    uint256 indexed expiry,
    uint256 scaledTotalAmount,
    uint256 scaledAmountBurned,
    uint256 normalizedAmountPaid
  );

  /// @notice emitted whenever the market creates a new current withdrawal batch.
  /// @dev closure can create an empty one-second collision guard without a lender request.
  /// @param expiry batch key and scheduled expiry timestamp.
  event WithdrawalBatchCreated(uint256 indexed expiry);

  /// @notice emitted when the batch has enough assets reserved to pay every request.
  /// @param expiry batch key and scheduled expiry timestamp.
  event WithdrawalBatchClosed(uint256 indexed expiry);

  /// @notice emitted when assets are reserved and the matching scaled supply is burned.
  /// @param expiry batch receiving the payment.
  /// @param scaledAmountBurned scaled supply paid and burned by this payment.
  /// @param normalizedAmountPaid underlying assets reserved by this payment.
  event WithdrawalBatchPayment(
    uint256 indexed expiry,
    uint256 scaledAmountBurned,
    uint256 normalizedAmountPaid
  );

  /// @notice emitted when scaled tokens move from an account into a withdrawal batch.
  /// @param expiry batch receiving the request.
  /// @param account lender that queued the request.
  /// @param scaledAmount exact scaled shares queued.
  /// @param normalizedAmount normalized amount reported at queue time.
  event WithdrawalQueued(
    uint256 indexed expiry,
    address indexed account,
    uint256 scaledAmount,
    uint256 normalizedAmount
  );

  /// @notice emitted when an account's paid share of a batch is transferred out.
  /// @param expiry batch whose claim was executed.
  /// @param account lender owning the claim.
  /// @param normalizedAmount underlying assets transferred for this execution.
  event WithdrawalExecuted(
    uint256 indexed expiry,
    address indexed account,
    uint256 normalizedAmount
  );

  /// @notice emitted when a sanctioned lender's withdrawal is sent to its escrow.
  /// @param account sanctioned lender owning the claim.
  /// @param escrow sanctions escrow that received the assets.
  /// @param expiry batch whose claim was executed.
  /// @param amount underlying assets sent to escrow.
  event SanctionedAccountWithdrawalSentToEscrow(
    address indexed account,
    address escrow,
    uint32 expiry,
    uint256 amount
  );
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MarketState } from '../libraries/MarketState.sol';

interface IMarketEventsAndErrors {
  /// @notice Error thrown when deposit exceeds maxTotalSupply
  error MaxSupplyExceeded();

  /// @notice Error thrown when non-borrower tries accessing borrower-only actions
  error NotApprovedBorrower();

  /// @notice Error thrown when non-approved lender tries lending to the market
  error NotApprovedLender();

  /// @notice Error thrown when caller other than factory tries changing protocol fee
  error NotFactory();

  /// @notice Error thrown when caller other than the canonical wrapper factory
  ///         tries to register a wrapper.
  error NotWrapperFactory();

  /// @notice Error thrown when the canonical wrapper has already been registered.
  error WrapperAlreadyRegistered();

  /// @notice Error thrown when attempting to nuke the market's canonical wrapper.
  error CannotNukeWrapper();

  /// @notice Error thrown when non-sentinel tries to use nukeFromOrbit
  error BadLaunchCode();

  /// @notice Error thrown when transfer target is blacklisted
  error AccountBlocked();

  error BadRescueAsset();

  error BorrowAmountTooHigh();

  error InsufficientReservesForFeeWithdrawal();

  error WithdrawalBatchNotExpired();

  error WithdrawalBatchKeyAlreadyExists();

  error NullMintAmount();

  error NullBurnAmount();

  error NullFeeAmount();

  error NullTransferAmount();

  error NullWithdrawalAmount();

  error NullRepayAmount();

  error MarketAlreadyClosed();

  error DepositToClosedMarket();

  error RepayToClosedMarket();

  error BorrowWhileSanctioned();

  error BorrowFromClosedMarket();

  error AprChangeOnClosedMarket();

  error CapacityChangeOnClosedMarket();

  error ProtocolFeeChangeOnClosedMarket();

  error AprReductionNotReduction();

  error ExecutePendingAprReductionNotEnabled();

  error CloseMarketWithUnpaidWithdrawals();

  error AnnualInterestBipsTooHigh();

  error ReserveRatioBipsTooHigh();

  error ProtocolFeeTooHigh();

  error InvalidBorrower();

  error InvalidBorrowerIdentityRegistry();

  error InvalidBorrowerTransferTarget();

  error NoPendingBorrowerTransfer();

  error NotPendingBorrower();

  error BorrowerIdentityNotFound();

  error BorrowerPrincipalNotRegistered();

  error AmbiguousBorrowerIdentity();

  error BorrowerTransferWhileSanctioned(address account);

  /// @dev Error thrown when reserve ratio is set to a value
  ///      that would make the market delinquent.
  error InsufficientReservesForNewLiquidityRatio();

  error InsufficientReservesForOldLiquidityRatio();

  error InvalidArrayLength();

  event Transfer(address indexed from, address indexed to, uint256 value);

  event Approval(address indexed owner, address indexed spender, uint256 value);

  event MaxTotalSupplyUpdated(uint256 assets);

  event ProtocolFeeBipsUpdated(uint256 protocolFeeBips);

  event AnnualInterestBipsUpdated(uint256 annualInterestBipsUpdated);

  event ReserveRatioBipsUpdated(uint256 reserveRatioBipsUpdated);

  event SanctionedAccountAssetsQueuedForWithdrawal(
    address indexed account,
    uint256 expiry,
    uint256 scaledAmount,
    uint256 normalizedAmount
  );

  event Deposit(address indexed account, uint256 assetAmount, uint256 scaledAmount);

  event Borrow(uint256 assetAmount);

  event DebtRepaid(address indexed from, uint256 assetAmount);

  event MarketClosed(uint256 timestamp);

  event FeesCollected(uint256 assets);

  event StateUpdated(uint256 scaleFactor, bool isDelinquent);

  event InterestAndFeesAccrued(
    uint256 fromTimestamp,
    uint256 toTimestamp,
    uint256 scaleFactor,
    uint256 baseInterestRay,
    uint256 delinquencyFeeRay,
    uint256 protocolFees
  );

  event AccountSanctioned(address indexed account);

  event WrapperRegistered(address indexed wrapper);

  event BorrowerTransferRequested(
    address indexed borrower,
    address indexed previousPendingBorrower,
    address indexed pendingBorrower,
    address borrowerPrincipal,
    address pendingBorrowerPrincipal
  );

  event BorrowerTransferCancelled(
    address indexed borrower,
    address indexed cancelledPendingBorrower,
    address borrowerPrincipal
  );

  event BorrowerTransferred(
    address indexed previousBorrower,
    address indexed newBorrower,
    address previousBorrowerPrincipal,
    address indexed newBorrowerPrincipal
  );

  // =====================================================================//
  //                          Withdrawl Events                            //
  // =====================================================================//

  event WithdrawalBatchExpired(
    uint256 indexed expiry,
    uint256 scaledTotalAmount,
    uint256 scaledAmountBurned,
    uint256 normalizedAmountPaid
  );

  /// @dev Emitted when a new withdrawal batch is created.
  event WithdrawalBatchCreated(uint256 indexed expiry);

  /// @dev Emitted when a withdrawal batch is paid off.
  event WithdrawalBatchClosed(uint256 indexed expiry);

  event WithdrawalBatchPayment(
    uint256 indexed expiry,
    uint256 scaledAmountBurned,
    uint256 normalizedAmountPaid
  );

  event WithdrawalQueued(
    uint256 indexed expiry,
    address indexed account,
    uint256 scaledAmount,
    uint256 normalizedAmount
  );

  event WithdrawalExecuted(
    uint256 indexed expiry,
    address indexed account,
    uint256 normalizedAmount
  );

  event SanctionedAccountWithdrawalSentToEscrow(
    address indexed account,
    address escrow,
    uint32 expiry,
    uint256 amount
  );
}

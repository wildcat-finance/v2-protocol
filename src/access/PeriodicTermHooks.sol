// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './MarketConstraintHooks.sol';
import './IMarketTransferPolicy.sol';
import '../libraries/SafeCastLib.sol';
import './BaseAccessControls.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/**
 * @dev sized to fit one storage slot (31 bytes)
 *      hooks (deposit, transfer, queueWithdrawal) load the whole struct
 *      open/fixed templates' equivalents are single-slot.
 *      `minimumDeposit` is uint96 (max ~7.9e28) to stay under 32 bytes
 *      external `setMinimumDeposit(address,uint128)` signature unchanged
 *      `MinimumDepositUpdated(address,uint128)` event unchanged
 *      checked downcast at the boundary
 */
struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  bool depositHookEnabled;
  uint96 minimumDeposit;
  uint32 firstWithdrawalWindowStart;
  uint32 periodDuration;
  uint32 withdrawalWindowDuration;
  bool transfersDisabled;
  bool isClosed;
}

struct PendingAprChange {
  uint16 annualInterestBips;
  uint32 proposalTimestamp;
}

/**
 * @dev Storage layout for pending APR reduction proposals. Fits one slot.
 *      Response window bounds are fixed at proposal time.
 *      Kept separate from `PendingAprChange` so the external ABI of
 *      `pendingAprChanges` and `getPendingAprChange` is unchanged from the
 *      first template version.
 */
struct PendingAprChangeStorage {
  uint16 annualInterestBips;
  uint32 proposalTimestamp;
  uint32 responseWindowStart;
  uint32 responseWindowEnd;
}

interface IMarketApr {
  function annualInterestBips() external view returns (uint256);
}

/**
 * @title PeriodicTermHooks
 * @dev Hooks contract for markets where withdrawals may only be queued during
 *      a recurring scheduled window. Withdrawal batches still expire using
 *      the market's immutable `withdrawalBatchDuration`.
 *
 *      APR reductions must be proposed in advance: lenders have the next
 *      withdrawal window to exit in response, and the reduction is only
 *      applied after that window ends, before the proposal expires and with
 *      no unpaid withdrawal batches outstanding.
 */
contract PeriodicTermHooks is BaseAccessControls, MarketConstraintHooks, IMarketTransferPolicy {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  event MinimumDepositUpdated(address market, uint128 newMinimumDeposit);
  event PeriodicTermUpdated(
    address market,
    uint32 firstWithdrawalWindowStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration
  );
  event PeriodicTermClosed(address market);
  event AnnualInterestBipsReductionProposed(
    address indexed market,
    uint16 annualInterestBips,
    uint32 proposalTimestamp,
    uint32 responseWindowStart,
    uint32 responseWindowEnd
  );
  event AnnualInterestBipsReductionProposalCancelled(address indexed market);
  event AnnualInterestBipsReductionExecuted(address indexed market, uint16 annualInterestBips);

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  error NotHookedMarket();
  error DepositBelowMinimum();
  error TransfersDisabled();
  error InvalidAccessConfiguration();
  error PeriodicWindowNotProvided();
  error InitialWithdrawalWindowTooFarInFuture();
  error PeriodDurationOutOfBounds();
  error WithdrawalWindowDurationOutOfBounds();
  error DepositHookNotEnabled();
  error WithdrawOutsideWindow();
  error AprReductionProposalDuringWithdrawalWindow();
  error AprReductionProposalNotReduction();
  error NoPendingAprChange();
  error AprChangeDoesNotMatchProposal();
  error AprChangeNotReady();
  error AprReductionProposalExpired();
  error AprReductionProposalOnClosedMarket();
  error UnpaidWithdrawalsExist();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  HooksDeploymentConfig public immutable override config;

  // TODO FOR MAINNET: Finalize the minimum period duration with the team.
  uint32 public constant MinimumPeriodDuration = 6 minutes;
  // TODO FOR MAINNET: Finalize the maximum period duration with the team.
  uint32 public constant MaximumPeriodDuration = 365 days;
  // TODO FOR MAINNET: Finalize the minimum withdrawal window duration with the team.
  uint32 public constant MinimumWithdrawalWindowDuration = 1 minutes;
  // TODO FOR MAINNET: Finalize the maximum initial withdrawal window delay with the team.
  uint32 public constant MaximumInitialWithdrawalWindowDelay = MaximumPeriodDuration;

  /**
   * @dev Number of periods after the response window starts during which a
   *      proposed APR reduction remains executable. A value of one means the
   *      proposal can be executed after the response window ends until the next
   *      withdrawal window starts.
   */
  uint32 public constant AprReductionProposalValidityPeriods = 1;

  mapping(address => HookedMarket) internal _hookedMarkets;
  mapping(address => PendingAprChangeStorage) internal _pendingAprChanges;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /**
   * @param _deployer Address of the account that called the factory.
   * @param args Optional abi-encoded `NameAndProviderInputs` struct to initialize
   *             the providers and name for the hooks instance.
   */
  constructor(address _deployer, bytes memory args) BaseAccessControls(_deployer) IHooks() {
    HooksConfig optionalFlags = encodeHooksConfig({
      hooksAddress: address(0),
      useOnDeposit: true,
      useOnQueueWithdrawal: false,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false,
      useOnSetProtocolFeeBips: false
    });
    HooksConfig requiredFlags = EmptyHooksConfig
      .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
      .setFlag(Bit_Enabled_QueueWithdrawal)
      .setFlag(Bit_Enabled_CloseMarket)
      .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction);
    config = encodeHooksDeploymentConfig(optionalFlags, requiredFlags);

    if (args.length > 0) {
      NameAndProviderInputs memory inputs = abi.decode(args, (NameAndProviderInputs));
      _initialize(inputs);
    }
  }

  function version() external pure override returns (string memory) {
    return 'PeriodicTermHooks';
  }

  /**
   * @dev Template revision. `version()` stays 'PeriodicTermHooks' because
   *      the subgraph matches templates by that exact string.
   */
  function templateVersion() external pure returns (uint256) {
    return 2;
  }

  /// @dev Same selector and return shape as the public-mapping getter
  ///      from the first template version.
  function pendingAprChanges(
    address market
  ) external view returns (uint16 annualInterestBips, uint32 proposalTimestamp) {
    PendingAprChangeStorage storage pendingAprChange = _pendingAprChanges[market];
    return (pendingAprChange.annualInterestBips, pendingAprChange.proposalTimestamp);
  }

  function _readBoolCd(bytes calldata data, uint offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint32Cd(bytes calldata data, uint offset) internal pure returns (uint32 value) {
    uint _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint32();
  }

  function _readUint96Cd(bytes calldata data, uint offset) internal pure returns (uint96 value) {
    uint _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint96();
  }

  /**
   * @dev Called when market is deployed using this contract as its `hooks`.
   *
   *     @param deployer      Address of the account that called the factory - must
   *                          match the borrower address.
   *     @param marketAddress Address of the market being deployed.
   *     @param parameters    Parameters used to deploy the market.
   *     @param hooksData     Extra data passed to the market deployment function containing
   *                          the parameters for the hooks.
   *
   *     `hooksData` is a tuple of (
   *        uint32 firstWithdrawalWindowStart,
   *        uint32 periodDuration,
   *        uint32 withdrawalWindowDuration,
   *        uint128? minimumDeposit,
   *        bool? transfersDisabled
   *     )
   *     Where only the first three parameters are mandatory.
   *
   *      Withdrawal windows begin at `firstWithdrawalWindowStart` and recur
   *      every `periodDuration` seconds.
   *
   *      Note: Called inside the root `onCreateMarket` in the base contract,
   *      so no need to verify the caller is the factory.
   */
  function _onCreateMarket(
    address deployer,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    super._onCreateMarket(deployer, marketAddress, parameters, hooksData);
    if (deployer != borrower) revert CallerNotBorrower();
    if (hooksData.length < 0x60) revert PeriodicWindowNotProvided();

    marketHooksConfig = parameters.hooks;

    uint32 firstWithdrawalWindowStart = _readUint32Cd(hooksData, 0);
    uint32 periodDuration = _readUint32Cd(hooksData, 0x20);
    uint32 withdrawalWindowDuration = _readUint32Cd(hooksData, 0x40);

    _validatePeriodicTerm(
      firstWithdrawalWindowStart,
      periodDuration,
      withdrawalWindowDuration,
      block.timestamp
    );
    emit PeriodicTermUpdated(
      marketAddress,
      firstWithdrawalWindowStart,
      periodDuration,
      withdrawalWindowDuration
    );

    // Use the deposit and transfer flags to determine whether those require
    // access control. These are tracked separately because if the market
    // enables `onQueueWithdrawal`, deposit and transfer hooks will also be
    // enabled, but may not require access control.
    // If the calldata does not contain sufficient bytes for an optional
    // parameter, it will be read as zero.
    HookedMarket memory hookedMarket = HookedMarket({
      isHooked: true,
      transferRequiresAccess: marketHooksConfig.useOnTransfer(),
      depositRequiresAccess: marketHooksConfig.useOnDeposit(),
      withdrawalRequiresAccess: marketHooksConfig.useOnQueueWithdrawal(),
      depositHookEnabled: false,
      firstWithdrawalWindowStart: firstWithdrawalWindowStart,
      periodDuration: periodDuration,
      withdrawalWindowDuration: withdrawalWindowDuration,
      minimumDeposit: _readUint96Cd(hooksData, 0x60),
      transfersDisabled: _readBoolCd(hooksData, 0x80),
      isClosed: false
    });
    if (hookedMarket.withdrawalRequiresAccess) {
      if (!hookedMarket.depositRequiresAccess) revert InvalidAccessConfiguration();
      if (!hookedMarket.transfersDisabled && !hookedMarket.transferRequiresAccess) {
        revert InvalidAccessConfiguration();
      }
    }

    if (hookedMarket.minimumDeposit > 0) {
      marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_Deposit);
      emit MinimumDepositUpdated(marketAddress, hookedMarket.minimumDeposit);
    }
    if (hookedMarket.transfersDisabled) {
      marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_Transfer);
    }

    if (marketHooksConfig.useOnQueueWithdrawal()) {
      marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_Transfer).setFlag(
        Bit_Enabled_Deposit
      );
    }
    hookedMarket.depositHookEnabled = marketHooksConfig.useOnDeposit();
    marketHooksConfig = marketHooksConfig.mergeFlags(config);
    _hookedMarkets[address(marketAddress)] = hookedMarket;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  /**
   * @notice Sets the minimum deposit for a market created by this hooks instance.
   * @dev Market hook dispatch flags are immutable after deployment. A positive
   *      minimum is enforceable only if `onDeposit` was enabled when the market
   *      was created. A positive initial minimum enables it automatically. A
   *      market created with a zero minimum and `onDeposit` disabled cannot
   *      later adopt a positive minimum.
   *      Reverts if `market` was not created with this hooks instance.
   */
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyBorrower {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (newMinimumDeposit > 0 && !hookedMarket.depositHookEnabled) revert DepositHookNotEnabled();
    // External signature kept as uint128 for ABI stability; storage is uint96.
    hookedMarket.minimumDeposit = uint256(newMinimumDeposit).toUint96();
    emit MinimumDepositUpdated(market, newMinimumDeposit);
  }

  function proposeAnnualInterestBips(
    address market,
    uint16 annualInterestBips
  ) external onlyBorrower {
    HookedMarket memory hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (hookedMarket.isClosed) revert AprReductionProposalOnClosedMarket();
    if (_isWithdrawalWindowOpen(hookedMarket, block.timestamp)) {
      revert AprReductionProposalDuringWithdrawalWindow();
    }
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );

    if (annualInterestBips >= IMarketApr(market).annualInterestBips()) {
      revert AprReductionProposalNotReduction();
    }

    uint32 proposalTimestamp = block.timestamp.toUint32();
    uint32 responseWindowStart = _getNextWithdrawalWindowStart(hookedMarket, proposalTimestamp)
      .toUint32();
    uint32 responseWindowEnd = responseWindowStart + hookedMarket.withdrawalWindowDuration;

    if (_pendingAprChanges[market].proposalTimestamp != 0) {
      emit AnnualInterestBipsReductionProposalCancelled(market);
    }

    _pendingAprChanges[market] = PendingAprChangeStorage({
      annualInterestBips: annualInterestBips,
      proposalTimestamp: proposalTimestamp,
      responseWindowStart: responseWindowStart,
      responseWindowEnd: responseWindowEnd
    });

    emit AnnualInterestBipsReductionProposed(
      market,
      annualInterestBips,
      proposalTimestamp,
      responseWindowStart,
      responseWindowEnd
    );
  }

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  function isMarketTransferDisabled(address marketAddress) external view override returns (bool) {
    HookedMarket storage market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return market.transfersDisabled;
  }

  function getHookedMarket(address marketAddress) external view returns (HookedMarket memory) {
    return _hookedMarkets[marketAddress];
  }

  function getHookedMarkets(
    address[] calldata marketAddresses
  ) external view returns (HookedMarket[] memory hookedMarkets) {
    hookedMarkets = new HookedMarket[](marketAddresses.length);
    for (uint256 i = 0; i < marketAddresses.length; i++) {
      hookedMarkets[i] = _hookedMarkets[marketAddresses[i]];
    }
  }

  function isWithdrawalWindowOpen(address marketAddress) external view returns (bool) {
    HookedMarket memory market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return _isWithdrawalWindowOpen(market, block.timestamp);
  }

  function getPendingAprChange(
    address marketAddress
  )
    external
    view
    returns (
      PendingAprChange memory pendingAprChange,
      uint32 responseWindowStart,
      uint32 responseWindowEnd
    )
  {
    HookedMarket memory market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();

    PendingAprChangeStorage memory stored = _pendingAprChanges[marketAddress];
    pendingAprChange = PendingAprChange({
      annualInterestBips: stored.annualInterestBips,
      proposalTimestamp: stored.proposalTimestamp
    });
    if (stored.proposalTimestamp != 0) {
      responseWindowStart = stored.responseWindowStart;
      responseWindowEnd = stored.responseWindowEnd;
    }
  }

  function _isWithdrawalWindowOpen(
    HookedMarket memory market,
    uint256 timestamp
  ) internal pure returns (bool) {
    if (market.isClosed) return true;
    if (timestamp < market.firstWithdrawalWindowStart) return false;

    uint256 timeInPeriod = (timestamp - market.firstWithdrawalWindowStart) % market.periodDuration;
    return timeInPeriod < market.withdrawalWindowDuration;
  }

  function _getNextWithdrawalWindowStart(
    HookedMarket memory market,
    uint256 timestamp
  ) internal pure returns (uint256 windowStart) {
    if (timestamp < market.firstWithdrawalWindowStart) {
      return market.firstWithdrawalWindowStart;
    }

    uint256 periodsElapsed = (timestamp - market.firstWithdrawalWindowStart) /
      market.periodDuration;
    return market.firstWithdrawalWindowStart + ((periodsElapsed + 1) * market.periodDuration);
  }

  function _validatePeriodicTerm(
    uint32 firstWithdrawalWindowStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration,
    uint256 currentTimestamp
  ) internal pure {
    if (periodDuration < MinimumPeriodDuration || periodDuration > MaximumPeriodDuration) {
      revert PeriodDurationOutOfBounds();
    }
    if (
      withdrawalWindowDuration < MinimumWithdrawalWindowDuration ||
      withdrawalWindowDuration >= periodDuration
    ) {
      revert WithdrawalWindowDurationOutOfBounds();
    }

    // Once the schedule has started a window always begins within one period,
    // and periods are capped at the maximum delay, so only a future
    // `firstWithdrawalWindowStart` can push the first window too far out.
    if (firstWithdrawalWindowStart > currentTimestamp + MaximumInitialWithdrawalWindowDelay) {
      revert InitialWithdrawalWindowTooFarInFuture();
    }
  }

  // ========================================================================== //
  //                                    Hooks                                   //
  // ========================================================================== //

  /**
   * @dev Called when a lender attempts to deposit.
   *      Passes the check if the deposit amount is at least the minimum deposit
   *      amount, the lender is not blocked from depositing, and either the lender
   *      has a valid credential or the market does not require access for deposits.
   */
  function onDeposit(
    address lender,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();

    // Retrieve the lender's status from storage
    LenderStatus memory status = _lenderStatus[lender];

    // Check that the lender is not blocked
    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    // Check that the deposit amount is at or above the market's minimum.
    // The market floors the scaled amount (v2.5), so an exact-minimum tender
    // can round-trip below the minimum; compare in scaled units, flooring
    // both sides identically. Tolerance is at most one scaled token. Skips
    // the conversion when no minimum is set (deposit hook enabled for access
    // control only).
    if (market.minimumDeposit > 0) {
      if (MathUtils.mulDiv(market.minimumDeposit, RAY, state.scaleFactor) > scaledAmount) {
        revert DepositBelowMinimum();
      }
    }

    // Attempt to validate the lender's access
    // Uses the inner method here as storage may need to be updated if this
    // is their first deposit
    (bool hasValidCredential, bool roleUpdated) = _tryValidateAccessInner(
      status,
      lender,
      hooksData
    );

    if (market.depositRequiresAccess.and(!hasValidCredential)) {
      revert NotApprovedLender();
    }

    _writeLenderStatus(status, lender, hasValidCredential, roleUpdated, true);
  }

  /**
   * @dev Called when a lender attempts to queue a withdrawal.
   *      Reverts if the market is open and no withdrawal window is active.
   *      If the market requires access for withdrawals, passes the check if
   *      the lender is a known lender or has a valid credential from an
   *      approved role provider.
   */
  function onQueueWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint /* scaledAmount */,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (!state.isClosed && !_isWithdrawalWindowOpen(market, block.timestamp)) {
      revert WithdrawOutsideWindow();
    }

    if (market.withdrawalRequiresAccess) {
      LenderStatus memory status = _lenderStatus[lender];
      if (
        !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
      ) {
        revert NotApprovedLender();
      }
    }
  }

  /**
   * @dev Hook not implemented for this contract.
   */
  function onExecuteWithdrawal(
    address /* lender */,
    uint128 /* normalizedAmountWithdrawn */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /**
   * @dev Called when a lender attempts to transfer market tokens on a market
   *      that requires credentials for either transfers or withdrawals.
   *
   *      Allows the transfer if the recipient:
   *      - is a known lender OR
   *      - is not blocked AND
   *        - has a valid credential OR
   *        - market does not require a credential for transfers
   *
   *    If the recipient is not a known lender but does have a valid
   *    credential, they will be marked as a known lender.
   */
  function onTransfer(
    address /* caller */,
    address /* from */,
    address to,
    uint /* scaledAmount */,
    MarketState calldata /* state */,
    bytes calldata extraData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];

    if (!market.isHooked) revert NotHookedMarket();

    if (market.transfersDisabled) {
      revert TransfersDisabled();
    }

    // If the recipient is a known lender, skip access control checks.
    if (!isKnownLenderOnMarket[to][msg.sender]) {
      LenderStatus memory toStatus = _lenderStatus[to];
      // Respect `isBlockedFromDeposits` only if the recipient is not a known lender
      if (toStatus.isBlockedFromDeposits) revert NotApprovedLender();

      // Attempt to validate the lender's access even if the market does not require
      // a credential for transfers, as the recipient may need to be updated to reflect
      // their new status as a known lender.
      (bool hasValidCredential, bool wasUpdated) = _tryValidateAccessInner(toStatus, to, extraData);

      // Revert if the recipient does not have a valid credential and the market requires one
      if (market.transferRequiresAccess.and(!hasValidCredential)) {
        revert NotApprovedLender();
      }

      _writeLenderStatus(toStatus, to, hasValidCredential, wasUpdated, true);
    }
  }

  /**
   * @dev Hook not implemented for this contract.
   */
  function onBorrow(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}

  /**
   * @dev Hook not implemented for this contract.
   */
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  function onCloseMarket(
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    market.isClosed = true;
    // A closed market can never execute an APR change, so cancel any pending
    // reduction proposal rather than leave it in storage forever.
    if (_pendingAprChanges[msg.sender].proposalTimestamp != 0) {
      delete _pendingAprChanges[msg.sender];
      emit AnnualInterestBipsReductionProposalCancelled(msg.sender);
    }
    emit PeriodicTermClosed(msg.sender);
  }

  /**
   * @dev Hook not implemented for this contract.
   */
  function onNukeFromOrbit(
    address /* lender */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /**
   * @dev Hook not implemented for this contract.
   */
  function onSetMaxTotalSupply(
    uint256 /* maxTotalSupply */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /**
   * @dev Applies a pending APR reduction proposal for the market (msg.sender).
   *      Reverts unless `annualInterestBips` matches the proposal, the response
   *      window has ended, the proposal has not expired and there are no
   *      unpaid withdrawal batches.
   */
  function _executePendingAnnualInterestBipsReduction(
    HookedMarket memory hookedMarket,
    MarketState calldata intermediateState,
    uint16 annualInterestBips,
    PendingAprChangeStorage memory pendingAprChange
  ) internal returns (uint16 updatedAnnualInterestBips) {
    if (pendingAprChange.proposalTimestamp == 0) revert NoPendingAprChange();
    if (pendingAprChange.annualInterestBips != annualInterestBips) {
      revert AprChangeDoesNotMatchProposal();
    }
    if (annualInterestBips >= intermediateState.annualInterestBips) {
      revert AprReductionProposalNotReduction();
    }
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );

    uint256 responseWindowEnd = pendingAprChange.responseWindowEnd;
    if (block.timestamp < responseWindowEnd) revert AprChangeNotReady();
    if (
      block.timestamp >=
      pendingAprChange.responseWindowStart +
        uint256(hookedMarket.periodDuration) *
        AprReductionProposalValidityPeriods
    ) {
      revert AprReductionProposalExpired();
    }
    if (intermediateState.scaledPendingWithdrawals != 0) revert UnpaidWithdrawalsExist();

    delete _pendingAprChanges[msg.sender];
    emit AnnualInterestBipsReductionExecuted(msg.sender, annualInterestBips);
    updatedAnnualInterestBips = annualInterestBips;
  }

  /**
   * @dev Called when the market's permissionless
   *      `executePendingAnnualInterestBipsReduction` is invoked, letting
   *      anyone apply a matured reduction proposal without the borrower
   *      calling `setAnnualInterestAndReserveRatioBips`.
   */
  function executePendingAnnualInterestBipsReduction(
    MarketState calldata intermediateState
  ) external returns (uint16 annualInterestBips) {
    HookedMarket memory hookedMarket = _hookedMarkets[msg.sender];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    PendingAprChangeStorage memory pendingAprChange = _pendingAprChanges[msg.sender];
    annualInterestBips = _executePendingAnnualInterestBipsReduction(
      hookedMarket,
      intermediateState,
      pendingAprChange.annualInterestBips,
      pendingAprChange
    );
  }

  /**
   * @dev Called when the borrower changes the market's APR or reserve ratio.
   *      An increase cancels any pending reduction proposal; a reduction must
   *      execute a matured proposal; an unchanged APR defers to the parent.
   */
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata hooksData
  )
    public
    virtual
    override
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips)
  {
    HookedMarket memory hookedMarket = _hookedMarkets[msg.sender];
    if (!hookedMarket.isHooked) revert NotHookedMarket();

    // Range checks: increase/equal paths assert in the parent hook,
    // the reduction path asserts in the execution function.
    if (annualInterestBips > intermediateState.annualInterestBips) {
      if (_pendingAprChanges[msg.sender].proposalTimestamp != 0) {
        delete _pendingAprChanges[msg.sender];
        emit AnnualInterestBipsReductionProposalCancelled(msg.sender);
      }
    } else if (annualInterestBips < intermediateState.annualInterestBips) {
      PendingAprChangeStorage memory pendingAprChange = _pendingAprChanges[msg.sender];
      annualInterestBips = _executePendingAnnualInterestBipsReduction(
        hookedMarket,
        intermediateState,
        annualInterestBips,
        pendingAprChange
      );
      return (annualInterestBips, intermediateState.reserveRatioBips);
    }

    return
      super.onSetAnnualInterestAndReserveRatioBips(
        annualInterestBips,
        reserveRatioBips,
        intermediateState,
        hooksData
      );
  }

  /**
   * @dev Hook not implemented for this contract.
   */
  function onSetProtocolFeeBips(
    uint16 /* protocolFeeBips */,
    MarketState memory /* intermediateState */,
    bytes calldata /* extraData */
  ) external override {}
}

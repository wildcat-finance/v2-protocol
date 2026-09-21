// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './MarketConstraintHooks.sol';
import './IMarketTransferPolicy.sol';
import '../libraries/SafeCastLib.sol';
import './BaseAccessControls.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/// @dev per-market schedule and access settings, packed into 31 bytes so the hot callbacks need one
///      storage slot. `minimumDeposit` is `uint96`; the external setter keeps its older `uint128`
///      ABI and checks the downcast.
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

/// @notice compatibility view of an APR reduction proposal.
struct PendingAprChange {
  uint16 annualInterestBips;
  uint32 proposalTimestamp;
}

/// @dev one-slot proposal state. response-window bounds are fixed at proposal time. this stays
///      separate from `PendingAprChange` to preserve the first template version's external tuple.
struct PendingAprChangeStorage {
  uint16 annualInterestBips;
  uint32 proposalTimestamp;
  uint32 responseWindowStart;
  uint32 responseWindowEnd;
}

/// @dev narrow market query used to prove a proposal is a strict reduction when it is created.
interface IMarketApr {
  /// @notice returns the market's current base annual interest rate, in bips.
  function annualInterestBips() external view returns (uint256);
}

/// @title PeriodicTermHooks
/// @notice credential policy with recurring windows for queueing withdrawals.
/// @dev closing a market removes the window restriction. APR reductions need advance notice: the
///      next window is fixed as the lender response window, and execution is available after it
///      closes until the following window begins, provided no pending withdrawals remain unpaid.
///      entry with a valid credential permanently marks a lender known on that market. the hooks
///      administrator can block deposits wherever `onDeposit` is enabled.
contract PeriodicTermHooks is BaseAccessControls, MarketConstraintHooks, IMarketTransferPolicy {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  /// @notice emitted when a hooked market's minimum deposit changes.
  event MinimumDepositUpdated(
    address indexed market,
    address indexed caller,
    uint128 previousMinimumDeposit,
    uint128 newMinimumDeposit
  );
  /// @notice emitted when a market's recurring withdrawal schedule is fixed at deployment.
  event PeriodicTermUpdated(
    address indexed market,
    address indexed administrator,
    uint32 firstWithdrawalWindowStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration
  );
  /// @notice emitted when market closure permanently opens withdrawal queueing.
  event PeriodicTermClosed(address indexed market);
  /// @notice emitted when an APR reduction fixes its lender response window.
  event AnnualInterestBipsReductionProposed(
    address indexed market,
    uint16 annualInterestBips,
    uint32 proposalTimestamp,
    uint32 responseWindowStart,
    uint32 responseWindowEnd
  );
  /// @notice emitted when a pending APR reduction is replaced or cancelled.
  event AnnualInterestBipsReductionProposalCancelled(address indexed market);
  /// @notice emitted when the market applies a matured APR reduction.
  event AnnualInterestBipsReductionExecuted(address indexed market, uint16 annualInterestBips);

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  /// @dev the caller supplied a market not bound to this hooks instance.
  error NotHookedMarket();
  /// @dev the scaled deposit is below the market's configured minimum.
  error DepositBelowMinimum();
  /// @dev transfers are disabled for this market.
  error TransfersDisabled();
  /// @dev the requested hook flags leave an uncredentialed path into a gated withdrawal policy.
  error InvalidAccessConfiguration();
  /// @dev market-creation hook data omitted the required periodic schedule.
  error PeriodicWindowNotProvided();
  /// @dev the first future withdrawal window is beyond the configured maximum delay.
  error InitialWithdrawalWindowTooFarInFuture();
  /// @dev the period duration is outside this template's inclusive bounds.
  error PeriodDurationOutOfBounds();
  /// @dev the withdrawal window is too short or not shorter than its period.
  error WithdrawalWindowDurationOutOfBounds();
  /// @dev a positive minimum was requested for a market without the deposit callback.
  error DepositHookNotEnabled();
  /// @dev an open market tried to queue a withdrawal outside its current window.
  error WithdrawOutsideWindow();
  /// @dev an APR reduction was proposed while its market's withdrawal window was open.
  error AprReductionProposalDuringWithdrawalWindow();
  /// @dev the proposed APR is not below the market's current APR.
  error AprReductionProposalNotReduction();
  /// @dev no APR reduction is pending for this market.
  error NoPendingAprChange();
  /// @dev the APR being executed does not exactly match the pending proposal.
  error AprChangeDoesNotMatchProposal();
  /// @dev the pending reduction's lender response window has not ended.
  error AprChangeNotReady();
  /// @dev the pending reduction reached its next withdrawal window before execution.
  error AprReductionProposalExpired();
  /// @dev APR reductions cannot be proposed after market closure.
  error AprReductionProposalOnClosedMarket();
  /// @dev scaled pending withdrawals remain unpaid.
  error UnpaidWithdrawalsExist();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  HooksDeploymentConfig public immutable override config;

  // TODO FOR MAINNET: Finalize the minimum period duration with the team.
  /// @notice shortest supported time between withdrawal-window starts.
  uint32 public constant MinimumPeriodDuration = 6 minutes;
  // TODO FOR MAINNET: Finalize the maximum period duration with the team.
  /// @notice longest supported time between withdrawal-window starts.
  uint32 public constant MaximumPeriodDuration = 365 days;
  // TODO FOR MAINNET: Finalize the minimum withdrawal window duration with the team.
  /// @notice shortest supported withdrawal window.
  uint32 public constant MinimumWithdrawalWindowDuration = 1 minutes;
  // TODO FOR MAINNET: Finalize the maximum initial withdrawal window delay with the team.
  /// @notice longest delay allowed before the first withdrawal window starts.
  uint32 public constant MaximumInitialWithdrawalWindowDelay = MaximumPeriodDuration;

  /// @notice number of periods from response-window start until an APR proposal expires.
  /// @dev number of periods from response-window start before a proposal expires. one makes the
  ///      execution interval `[responseWindowEnd, nextWindowStart)`.
  uint32 public constant AprReductionProposalValidityPeriods = 1;

  mapping(address => HookedMarket) internal _hookedMarkets;
  mapping(address => PendingAprChangeStorage) internal _pendingAprChanges;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /// @param _administrator initial hooks administrator. this does not grant provider authority.
  /// @param args optional ABI-encoded `NameAndProviderInputs` for the name and initial providers.
  constructor(
    address _administrator,
    bytes memory args
  ) BaseAccessControls(_administrator) IHooks() {
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

  /// @notice returns this template's ABI revision.
  /// @dev `version()` stays `PeriodicTermHooks` because integrations match that exact string.
  function templateVersion() external pure returns (uint256) {
    return 2;
  }

  /// @notice returns the proposed APR and proposal time in the first template version's ABI.
  /// @dev use `getPendingAprChange` when the fixed response-window bounds are also needed.
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

  /// @dev binds one market to this instance. `administrator_` must be the current hooks
  ///      administrator. `hooksData` is `(uint32 firstWithdrawalWindowStart, uint32 periodDuration,
  ///      uint32 withdrawalWindowDuration, uint96 minimumDeposit?, bool transfersDisabled?)`.
  ///      the first three words are required; optional missing words read as zero. withdrawal
  ///      gating is accepted only when deposits are gated and transfers are gated or disabled,
  ///      otherwise an uncredentialed entry path could trap the recipient.
  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
    if (administrator_ != administrator) revert CallerNotAdministrator();
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
      administrator_,
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
      emit MinimumDepositUpdated(
        marketAddress,
        administrator_,
        0,
        hookedMarket.minimumDeposit
      );
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

  /// @notice updates a hooked market's minimum deposit.
  /// @dev callback flags are immutable. a positive initial minimum enables `onDeposit`, but a
  ///      market created with no minimum and no deposit callback can't add a positive minimum
  ///      later.
  ///      values above `uint96` revert even though the compatibility ABI accepts `uint128`.
  /// @param newMinimumDeposit normalized underlying-asset units required per deposit.
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyAdministrator {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (newMinimumDeposit > 0 && !hookedMarket.depositHookEnabled) revert DepositHookNotEnabled();
    // External signature kept as uint128 for ABI stability; storage is uint96.
    uint128 previousMinimumDeposit = hookedMarket.minimumDeposit;
    hookedMarket.minimumDeposit = uint256(newMinimumDeposit).toUint96();
    emit MinimumDepositUpdated(market, msg.sender, previousMinimumDeposit, newMinimumDeposit);
  }

  /// @notice proposes a strict APR reduction and fixes the next window as the lender response
  ///         window.
  /// @dev only the hooks administrator may propose. the market must be hooked, open, and outside a
  ///      withdrawal window. a new valid proposal replaces the old one and emits its cancellation.
  /// @param annualInterestBips proposed APR in basis points, below the market's current APR.
  function proposeAnnualInterestBips(
    address market,
    uint16 annualInterestBips
  ) external onlyAdministrator {
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

  /// @notice says whether every market-token transfer is disabled for this market.
  /// @dev reverts for a market not bound to this hooks instance. false is permanent because this
  ///      template has no setter for the deployment-time flag.
  function isMarketTransferDisabled(address marketAddress) external view override returns (bool) {
    HookedMarket storage market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return market.transfersDisabled;
  }

  /// @notice says whether `recipient` can receive tokens now without hook data.
  /// @dev returns false for disabled transfers, an unknown blocked recipient, or a required
  ///      credential that cannot be resolved from cache or pull providers. reverts for an unknown
  ///      market.
  function isMarketTransferRecipientAllowed(
    address marketAddress,
    address recipient
  ) external view override returns (bool) {
    HookedMarket storage market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return
      !market.transfersDisabled &&
      _isMarketTransferRecipientAllowed(marketAddress, recipient, market.transferRequiresAccess);
  }

  /// @notice returns the periodic-term configuration stored for `marketAddress`.
  /// @dev an unattached market returns the zero-value struct.
  function getHookedMarket(address marketAddress) external view returns (HookedMarket memory) {
    return _hookedMarkets[marketAddress];
  }

  /// @notice batch version of `getHookedMarket`, preserving input order.
  function getHookedMarkets(
    address[] calldata marketAddresses
  ) external view returns (HookedMarket[] memory hookedMarkets) {
    hookedMarkets = new HookedMarket[](marketAddresses.length);
    for (uint256 i = 0; i < marketAddresses.length; i++) {
      hookedMarkets[i] = _hookedMarkets[marketAddresses[i]];
    }
  }

  /// @notice says whether withdrawals may be queued at the current timestamp.
  /// @dev closed markets always return true. for open markets, window start is inclusive and end is
  ///      exclusive. reverts for a market not bound to this hooks instance.
  function isWithdrawalWindowOpen(address marketAddress) external view returns (bool) {
    HookedMarket memory market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return _isWithdrawalWindowOpen(market, block.timestamp);
  }

  /// @notice returns a proposal and the response-window bounds fixed when it was created.
  /// @dev an expired proposal remains readable until it is replaced, cancelled by an APR increase
  ///      or closure, or executed.
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

  /// @dev the schedule anchor may be in the past. a future anchor can't exceed the configured
  ///      maximum delay, and each withdrawal window must be nonzero and shorter than its period.
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

  /// @notice enforces the market's minimum deposit and lender entry policy.
  /// @dev the minimum is compared in scaled units using the same floor as the market. a valid
  ///      credential marks the lender permanently known on this market, even when deposit access
  ///      itself is optional.
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

  /// @notice limits queueing to scheduled windows while the market is open.
  /// @dev window start is inclusive and end is exclusive. a closed market may queue at any time.
  ///      gated withdrawals additionally need market-specific known status or a current credential.
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

  /// @dev execution is not window-gated once the lender has queued the withdrawal.
  function onExecuteWithdrawal(
    address /* lender */,
    uint32 /* expiry */,
    uint128 /* normalizedAmountWithdrawn */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @notice enforces the recipient side of the market's transfer policy.
  /// @dev known recipients and the market's registered wrapper bypass later credential and
  ///      deposit-block checks. any other unknown recipient must not be blocked and, when transfers
  ///      are gated, must supply or resolve a credential. successful credential validation
  ///      permanently marks the recipient known on this market.
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
      // Wrapper entry is an ordinary market-token transfer without credential data. Only the
      // canonical wrapper registered by this market receives the protocol exemption.
      if (_isRegisteredWrapper(msg.sender, to)) return;

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

  /// @dev periodic-term policy does not constrain borrower draws.
  function onBorrow(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}

  /// @dev periodic-term policy does not constrain repayments.
  function onRepay(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @notice marks the schedule closed and cancels any pending APR reduction.
  /// @dev closing permanently opens withdrawal queueing; this template has no reopen transition.
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

  /// @dev quarantine reaches the window check in the ordinary queue callback that follows.
  function onNukeFromOrbit(
    address /* lender */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @dev this template adds no supply-cap policy.
  function onSetMaxTotalSupply(
    uint256 /* maxTotalSupply */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @dev applies an exact pending reduction after its response window and before expiry. the APR
  ///      must still be a strict reduction, and all scaled pending withdrawals must be paid first.
  ///      success deletes the proposal.
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

  /// @notice lets a hooked market apply its matured APR reduction through the permissionless path.
  /// @dev users call the market; the market calls this hook and keeps its current reserve ratio.
  /// @return annualInterestBips exact proposed APR for the market to apply.
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

  /// @notice handles borrower-initiated APR updates under the periodic notice policy.
  /// @dev an increase cancels a pending reduction. a decrease must exactly match a matured proposal
  ///      and keeps the current reserve ratio. an unchanged APR uses the shared reserve policy and
  ///      does not cancel the proposal.
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

  /// @dev this template adds no protocol-fee policy.
  function onSetProtocolFeeBips(
    uint16 /* protocolFeeBips */,
    MarketState memory /* intermediateState */,
    bytes calldata /* extraData */
  ) external override {}
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './BaseHooks.sol';
import '../libraries/SafeCastLib.sol';

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
contract PeriodicTermHooks is BaseHooks {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

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

  /// @dev market-creation hook data omitted the required periodic schedule.
  error PeriodicWindowNotProvided();
  /// @dev the first future withdrawal window is beyond the configured maximum delay.
  error InitialWithdrawalWindowTooFarInFuture();
  /// @dev the period duration is outside this template's inclusive bounds.
  error PeriodDurationOutOfBounds();
  /// @dev the withdrawal window is too short or not shorter than its period.
  error WithdrawalWindowDurationOutOfBounds();
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
  )
    BaseHooks(
      _administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
          .setFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction)
      )
    )
  {}

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

  /// @dev binds the market after BaseHooks checks `administrator_` against the current
  ///      administrator. `hooksData` is `(uint32 firstWithdrawalWindowStart, uint32 periodDuration,
  ///      uint32 withdrawalWindowDuration, uint96 minimumDeposit?, bool transfersDisabled?)`.
  ///      the first three words are required; missing optional words read as zero. gated
  ///      withdrawals need gated deposits and gated or disabled transfers. otherwise a lender can
  ///      enter without credentials and get stuck on exit.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    if (hooksData.length < 0x60) revert PeriodicWindowNotProvided();
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

    uint96 minimumDeposit = _readUint96Cd(hooksData, 0x60);
    (
      AccessConfig memory access,
      bool depositHookEnabled,
      HooksConfig effective
    ) = _configureMarketAccess(
        administrator_,
        marketAddress,
        parameters.hooks,
        minimumDeposit,
        _readBoolCd(hooksData, 0x80)
      );
    _hookedMarkets[marketAddress] = HookedMarket({
      isHooked: access.isHooked,
      transferRequiresAccess: access.transferRequiresAccess,
      depositRequiresAccess: access.depositRequiresAccess,
      withdrawalRequiresAccess: access.withdrawalRequiresAccess,
      depositHookEnabled: depositHookEnabled,
      firstWithdrawalWindowStart: firstWithdrawalWindowStart,
      periodDuration: periodDuration,
      withdrawalWindowDuration: withdrawalWindowDuration,
      isClosed: false,
      minimumDeposit: minimumDeposit,
      transfersDisabled: access.transfersDisabled
    });
    return effective;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  function _readAccessConfig(
    address market
  ) internal view virtual override returns (AccessConfig memory) {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    return
      AccessConfig({
        isHooked: hookedMarket.isHooked,
        transferRequiresAccess: hookedMarket.transferRequiresAccess,
        depositRequiresAccess: hookedMarket.depositRequiresAccess,
        withdrawalRequiresAccess: hookedMarket.withdrawalRequiresAccess,
        minimumDeposit: hookedMarket.minimumDeposit,
        transfersDisabled: hookedMarket.transfersDisabled
      });
  }

  function _isDepositHookEnabled(address market) internal view virtual override returns (bool) {
    return _hookedMarkets[market].depositHookEnabled;
  }

  function _writeMinimumDeposit(address market, uint128 value) internal virtual override {
    // the public setter takes uint128 for ABI compatibility. storage still needs to fit uint96.
    _hookedMarkets[market].minimumDeposit = uint256(value).toUint96();
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

  /// @dev either closed flag opens the schedule. access checks still run afterward.
  function _checkWithdrawalSchedule(
    address,
    uint32,
    uint256,
    MarketState calldata state,
    bytes calldata
  ) internal view virtual override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!state.isClosed && !_isWithdrawalWindowOpen(market, block.timestamp)) {
      revert WithdrawOutsideWindow();
    }
  }

  function _validateCloseMarket(
    MarketState calldata,
    bytes calldata
  ) internal view virtual override {
    _validatePeriodicCloseMarket();
  }

  function _applyCloseMarket(MarketState calldata, bytes calldata) internal virtual override {
    _applyPeriodicCloseMarket();
  }

  function _validatePeriodicCloseMarket() internal view {
    if (!_hookedMarkets[msg.sender].isHooked) revert NotHookedMarket();
  }

  /// @dev validation must run first. close the schedule, cancel any proposal, then emit closure.
  function _applyPeriodicCloseMarket() internal {
    _hookedMarkets[msg.sender].isClosed = true;
    // a closed market can't execute the proposal. don't leave it sitting there forever.
    if (_pendingAprChanges[msg.sender].proposalTimestamp != 0) {
      delete _pendingAprChanges[msg.sender];
      emit AnnualInterestBipsReductionProposalCancelled(msg.sender);
    }
    emit PeriodicTermClosed(msg.sender);
  }

  /// @dev applies an exact pending reduction after its response window and before expiry. the APR
  ///      must still be a strict reduction, and all scaled pending withdrawals must be paid first.
  ///      success deletes the proposal.
  function _executePeriodicReduction(
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
    annualInterestBips = _executePeriodicReduction(
      hookedMarket,
      intermediateState,
      pendingAprChange.annualInterestBips,
      pendingAprChange
    );
    // `executePendingAnnualInterestBipsReduction` only returns an APR. the market keeps
    // `intermediateState.reserveRatioBips`, so validate that ratio and pass empty callback data.
    _checkAprChange(
      AprChange({
        market: msg.sender,
        route: AprRoute.PendingReduction,
        requestedApr: pendingAprChange.annualInterestBips,
        requestedReserve: intermediateState.reserveRatioBips,
        effectiveApr: annualInterestBips,
        effectiveReserve: intermediateState.reserveRatioBips
      }),
      intermediateState,
      msg.data[msg.data.length:]
    );
  }

  /// @dev an APR increase cancels `_pendingAprChanges[msg.sender]` before `_applyDefaultAprUpdate`.
  ///      equal APRs keep the proposal and also use `_applyDefaultAprUpdate`.
  ///      reductions must execute the exact matured proposal through `_executePeriodicReduction`,
  ///      return `intermediateState.reserveRatioBips`, and leave `temporaryExcessReserveRatio`
  ///      untouched. don't call `_applyDefaultAprUpdate` on that reduction path.
  function _applyAprUpdate(
    uint16 annualInterestBips,
    uint16,
    MarketState calldata intermediateState,
    bytes calldata
  ) internal virtual override returns (uint16 effectiveApr, uint16 effectiveReserve) {
    HookedMarket memory hookedMarket = _hookedMarkets[msg.sender];
    if (!hookedMarket.isHooked) revert NotHookedMarket();

    // `_applyDefaultAprUpdate` checks APR bounds for increases/equality.
    // `_executePeriodicReduction` checks them for proposal-backed reductions.
    if (annualInterestBips > intermediateState.annualInterestBips) {
      if (_pendingAprChanges[msg.sender].proposalTimestamp != 0) {
        delete _pendingAprChanges[msg.sender];
        emit AnnualInterestBipsReductionProposalCancelled(msg.sender);
      }
    } else if (annualInterestBips < intermediateState.annualInterestBips) {
      PendingAprChangeStorage memory pendingAprChange = _pendingAprChanges[msg.sender];
      annualInterestBips = _executePeriodicReduction(
        hookedMarket,
        intermediateState,
        annualInterestBips,
        pendingAprChange
      );
      return (annualInterestBips, intermediateState.reserveRatioBips);
    }

    return _applyDefaultAprUpdate(annualInterestBips, intermediateState);
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './MarketConstraintHooks.sol';
import '../libraries/SafeCastLib.sol';
import './BaseAccessControls.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/**
 * @dev Sized to fit one storage slot (31 bytes): the hot hooks (deposit,
 *      transfer, queueWithdrawal) load the whole struct on every call, and the
 *      open/fixed templates' equivalents are single-slot. `minimumDeposit` is
 *      uint96 (max ~7.9e28) rather than uint128 to stay under 32 bytes; the
 *      external `setMinimumDeposit(address,uint128)` signature and the
 *      `MinimumDepositUpdated(address,uint128)` event are unchanged, with a
 *      checked downcast at the boundary.
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
 * @dev Storage layout for pending APR reduction proposals. The response window
 *      is stored at proposal time rather than recomputed at execution so the
 *      proposal is self-contained and would survive any future change to term
 *      mutability. Kept separate from `PendingAprChange` so the external ABI of
 *      `pendingAprChanges` and `getPendingAprChange` is unchanged from the
 *      first template version. Fits one storage slot.
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
 */
contract PeriodicTermHooks is BaseAccessControls, MarketConstraintHooks {
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

  uint32 public constant MinimumPeriodDuration = 6 minutes;
  uint32 public constant MaximumPeriodDuration = 365 days;
  uint32 public constant MinimumWithdrawalWindowDuration = 1 minutes;
  uint32 public constant MaximumInitialWithdrawalWindowDelay = MaximumPeriodDuration;

  /**
   * @dev Number of full periods after the response window ends during which a
   *      proposed APR reduction remains executable. Bounds how stale a proposal
   *      can be when executed (lenders who responded did so against a recent
   *      market state) while leaving slack for unpaid-batch settlement before
   *      execution. Provisional value pending team feedback.
   */
  uint32 public constant AprReductionProposalValidityPeriods = 2;

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
      .setFlag(Bit_Enabled_CloseMarket);
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
   * @dev Discriminates template revisions. `version()` is pinned to
   *      'PeriodicTermHooks' because the subgraph matches templates and
   *      instances by that exact string; this constant identifies which
   *      revision of the template an instance was deployed from.
   */
  function templateVersion() external pure returns (uint256) {
    return 2;
  }

  /**
   * @dev ABI-compatible replacement for the public-mapping getter from the
   *      first template version (same selector and return shape).
   */
  function pendingAprChanges(
    address market
  ) external view returns (uint16 annualInterestBips, uint32 proposalTimestamp) {
    PendingAprChangeStorage storage pendingAprChange = _pendingAprChanges[market];
    return (pendingAprChange.annualInterestBips, pendingAprChange.proposalTimestamp);
  }

  function _readBoolCd(bytes calldata data, uint256 offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint32Cd(bytes calldata data, uint256 offset) internal pure returns (uint32 value) {
    uint256 _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint32();
  }

  function _readUint96Cd(bytes calldata data, uint256 offset) internal pure returns (uint96 value) {
    uint256 _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint96();
  }

  /**
   * @dev Called when market is deployed using this contract as its `hooks`.
   *
   *     `hooksData` is a tuple of (
   *        uint32 firstWithdrawalWindowStart,
   *        uint32 periodDuration,
   *        uint32 withdrawalWindowDuration,
   *        uint128? minimumDeposit,
   *        bool? transfersDisabled
   *     )
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

    emit PeriodicTermUpdated(
      marketAddress,
      firstWithdrawalWindowStart,
      periodDuration,
      withdrawalWindowDuration
    );

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

  function _getCurrentOrNextWithdrawalWindowStart(
    uint32 firstWithdrawalWindowStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration,
    uint256 timestamp
  ) internal pure returns (uint256 windowStart) {
    if (timestamp < firstWithdrawalWindowStart) return firstWithdrawalWindowStart;

    uint256 timeInPeriod = (timestamp - firstWithdrawalWindowStart) % periodDuration;
    windowStart = timestamp - timeInPeriod;
    if (timeInPeriod >= withdrawalWindowDuration) {
      windowStart += periodDuration;
    }
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

    uint256 nextWindowStart = _getCurrentOrNextWithdrawalWindowStart(
      firstWithdrawalWindowStart,
      periodDuration,
      withdrawalWindowDuration,
      currentTimestamp
    );
    if (nextWindowStart > currentTimestamp + MaximumInitialWithdrawalWindowDelay) {
      revert InitialWithdrawalWindowTooFarInFuture();
    }
  }

  // ========================================================================== //
  //                                    Hooks                                   //
  // ========================================================================== //

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();

    LenderStatus memory status = _lenderStatus[lender];

    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    // Skip normalization when no minimum is set (deposit hook enabled for
    // access control only) — the comparison against zero cannot fail.
    if (market.minimumDeposit > 0) {
      uint256 normalizedAmount = scaledAmount.rayMul(state.scaleFactor);
      if (market.minimumDeposit > normalizedAmount) {
        revert DepositBelowMinimum();
      }
    }

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

  function onQueueWithdrawal(
    address lender,
    uint32,
    /* expiry */
    uint256,
    /* scaledAmount */
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (!state.isClosed && !_isWithdrawalWindowOpen(market, block.timestamp))
      revert WithdrawOutsideWindow();

    if (market.withdrawalRequiresAccess) {
      LenderStatus memory status = _lenderStatus[lender];
      if (
        !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
      ) {
        revert NotApprovedLender();
      }
    }
  }

  function onExecuteWithdrawal(
    address,
    /* lender */
    uint128,
    /* normalizedAmountWithdrawn */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onTransfer(
    address,
    /* caller */
    address,
    /* from */
    address to,
    uint256,
    /* scaledAmount */
    MarketState calldata,
    /* state */
    bytes calldata extraData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];

    if (!market.isHooked) revert NotHookedMarket();

    if (market.transfersDisabled) {
      revert TransfersDisabled();
    }

    if (!isKnownLenderOnMarket[to][msg.sender]) {
      LenderStatus memory toStatus = _lenderStatus[to];
      if (toStatus.isBlockedFromDeposits) revert NotApprovedLender();

      (bool hasValidCredential, bool wasUpdated) = _tryValidateAccessInner(toStatus, to, extraData);

      if (market.transferRequiresAccess.and(!hasValidCredential)) {
        revert NotApprovedLender();
      }

      _writeLenderStatus(toStatus, to, hasValidCredential, wasUpdated, true);
    }
  }

  function onBorrow(
    uint256,
    /* normalizedAmount */
    MarketState calldata,
    /* state */
    bytes calldata /* extraData */
  ) external override {}

  function onRepay(
    uint256,
    /* normalizedAmount */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onCloseMarket(
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    market.isClosed = true;
    // A closed market can never execute an APR change, so a pending reduction
    // proposal would otherwise linger in storage (and indexed state) forever.
    if (_pendingAprChanges[msg.sender].proposalTimestamp != 0) {
      delete _pendingAprChanges[msg.sender];
      emit AnnualInterestBipsReductionProposalCancelled(msg.sender);
    }
    emit PeriodicTermClosed(msg.sender);
  }

  function onNukeFromOrbit(
    address,
    /* lender */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onSetMaxTotalSupply(
    uint256,
    /* maxTotalSupply */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

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
    // Note: this duplicates the range assert in the parent hook for the
    // increase/equal paths, but it is the only live range check on the
    // reduction path below, which returns before reaching the parent.
    assertValueInRange(
      annualInterestBips,
      MinimumAnnualInterestBips,
      MaximumAnnualInterestBips,
      AnnualInterestBipsOutOfBounds.selector
    );

    if (annualInterestBips > intermediateState.annualInterestBips) {
      if (_pendingAprChanges[msg.sender].proposalTimestamp != 0) {
        delete _pendingAprChanges[msg.sender];
        emit AnnualInterestBipsReductionProposalCancelled(msg.sender);
      }
    } else if (annualInterestBips < intermediateState.annualInterestBips) {
      PendingAprChangeStorage memory pendingAprChange = _pendingAprChanges[msg.sender];
      if (pendingAprChange.proposalTimestamp == 0) revert NoPendingAprChange();
      if (pendingAprChange.annualInterestBips != annualInterestBips) {
        revert AprChangeDoesNotMatchProposal();
      }

      uint256 responseWindowEnd = pendingAprChange.responseWindowEnd;
      if (block.timestamp < responseWindowEnd) revert AprChangeNotReady();
      if (
        block.timestamp >=
        responseWindowEnd +
          uint256(hookedMarket.periodDuration) *
          AprReductionProposalValidityPeriods
      ) {
        revert AprReductionProposalExpired();
      }
      if (intermediateState.scaledPendingWithdrawals != 0) revert UnpaidWithdrawalsExist();

      delete _pendingAprChanges[msg.sender];
      emit AnnualInterestBipsReductionExecuted(msg.sender, annualInterestBips);
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

  function onSetProtocolFeeBips(
    uint16,
    /* protocolFeeBips */
    MarketState memory,
    /* intermediateState */
    bytes calldata /* extraData */
  ) external override {}
}

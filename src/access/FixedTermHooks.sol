// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './MarketConstraintHooks.sol';
import './IMarketTransferPolicy.sol';
import '../libraries/SafeCastLib.sol';
import './BaseAccessControls.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/// @dev per-market maturity and access settings owned by one reusable hooks instance.
struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  uint128 minimumDeposit;
  uint32 fixedTermEndTime;
  bool transfersDisabled;
  bool allowClosureBeforeTerm;
  bool allowTermReduction;
}

/// @title FixedTermHooks
/// @notice credential policy with one maturity timestamp before which queueing is blocked.
/// @dev maturity may move earlier when configured, but never later. entry with a valid credential
///      marks a lender permanently known on that market, so losing the credential can't trap an
///      existing position after maturity. the hooks administrator can still block deposits wherever
///      `onDeposit` is enabled.
contract FixedTermHooks is BaseAccessControls, MarketConstraintHooks, IMarketTransferPolicy {
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
  /// @notice emitted when an allowed term reduction moves a market's maturity earlier.
  event FixedTermUpdated(
    address indexed market,
    address indexed caller,
    uint32 previousFixedTermEndTime,
    uint32 newFixedTermEndTime
  );

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  /// @dev the caller supplied a market not bound to this hooks instance.
  error NotHookedMarket();
  /// @dev the scaled deposit is below the market's configured minimum.
  error DepositBelowMinimum();
  /// @dev a positive minimum was requested for a market without the deposit callback.
  error DepositHookNotEnabled();
  /// @dev market-creation hook data omitted the fixed-term timestamp.
  error FixedTermNotProvided();
  /// @dev the requested hook flags leave an uncredentialed path into a gated withdrawal policy.
  error InvalidAccessConfiguration();
  /// @dev maturity is earlier than now or more than 365 days away.
  error InvalidFixedTerm();
  /// @dev a term update tried to move maturity later.
  error IncreaseFixedTerm();
  /// @dev the lender tried to queue a withdrawal before maturity.
  error WithdrawBeforeTermEnd();
  /// @dev the borrower tried to reduce APR before maturity.
  error NoReducingAprBeforeTermEnd();
  /// @dev transfers are disabled for this market.
  error TransfersDisabled();
  /// @dev the borrower tried to close before maturity without permission.
  error ClosureDisabledBeforeTerm();
  /// @dev this market was not configured to allow term reductions.
  error TermReductionDisabled();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  /// @notice longest fixed term accepted when a market is attached.
  uint32 public constant MaximumLoanTerm = 365 days;

  HooksDeploymentConfig public immutable override config;

  mapping(address => HookedMarket) internal _hookedMarkets;
  // tracks immutable deposit-hook dispatch without changing the public HookedMarket ABI.
  mapping(address => bool) internal _depositHookEnabled;

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
      .setFlag(Bit_Enabled_CloseMarket)
      .setFlag(Bit_Enabled_QueueWithdrawal);
    config = encodeHooksDeploymentConfig(optionalFlags, requiredFlags);

    if (args.length > 0) {
      NameAndProviderInputs memory inputs = abi.decode(args, (NameAndProviderInputs));
      _initialize(inputs);
    }
  }

  function version() external pure override returns (string memory) {
    return 'FixedTermHooks';
  }

  function _readBoolCd(bytes calldata data, uint offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint32Cd(bytes calldata data) internal pure returns (uint32 value) {
    uint _value;
    assembly {
      _value := calldataload(data.offset)
    }
    return _value.toUint32();
  }

  function _readUint128Cd(bytes calldata data, uint offset) internal pure returns (uint128 value) {
    uint _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint128();
  }

  /// @dev binds one market to this instance. `administrator_` must be the current hooks
  ///      administrator. `hooksData` is `(uint32 fixedTermEndTime, uint128 minimumDeposit?,
  ///      bool transfersDisabled?, bool allowClosureBeforeTerm?, bool allowTermReduction?)`.
  ///      maturity is required, can't be in the past, and can't be more than 365 days away.
  ///      withdrawal gating is accepted only when deposits are gated and transfers are gated or
  ///      disabled, otherwise an uncredentialed entry path could trap the recipient.
  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    // Validate the deploy parameters
    super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
    if (administrator_ != administrator) revert CallerNotAdministrator();
    if (hooksData.length < 32) revert FixedTermNotProvided();

    marketHooksConfig = parameters.hooks;

    uint32 fixedTermEndTime = _readUint32Cd(hooksData);

    if (
      fixedTermEndTime < block.timestamp || (fixedTermEndTime - block.timestamp) > MaximumLoanTerm
    ) {
      revert InvalidFixedTerm();
    }
    emit FixedTermUpdated(marketAddress, administrator_, 0, fixedTermEndTime);

    // Use the deposit and transfer flags to determine whether those require
    // access control. These are tracked separately because if the market
    // enables `onQueueWithdrawal`, deposit and transfer hooks will also be
    // enabled, but may not require access control.
    // Initialisations to zero here (and subsequent updates) are just because
    // of stack-too-deep errors otherwise.

    // Read `minimumDeposit`, `transfersDisabled`, `allowClosureBeforeTerm` and `allowTermReduction`
    // from `hooksData`.
    // If the calldata does not contain sufficient bytes for a parameter, it will be read as zero.
    HookedMarket memory hookedMarket = HookedMarket({
      isHooked: true,
      transferRequiresAccess: marketHooksConfig.useOnTransfer(),
      depositRequiresAccess: marketHooksConfig.useOnDeposit(),
      withdrawalRequiresAccess: marketHooksConfig.useOnQueueWithdrawal(),
      fixedTermEndTime: fixedTermEndTime,
      minimumDeposit: _readUint128Cd(hooksData, 0x20),
      transfersDisabled: _readBoolCd(hooksData, 0x40),
      allowClosureBeforeTerm: _readBoolCd(hooksData, 0x60),
      allowTermReduction: _readBoolCd(hooksData, 0x80)
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
    marketHooksConfig = marketHooksConfig.mergeFlags(config);
    _depositHookEnabled[marketAddress] = marketHooksConfig.useOnDeposit();
    _hookedMarkets[address(marketAddress)] = hookedMarket;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  /// @notice updates a hooked market's minimum deposit.
  /// @dev callback flags are immutable. a positive initial minimum enables `onDeposit`, but a
  ///      market created with no minimum and no deposit callback can't add a positive minimum
  ///      later.
  /// @param newMinimumDeposit normalized underlying-asset units required per deposit.
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyAdministrator {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (newMinimumDeposit > 0 && !_depositHookEnabled[market]) revert DepositHookNotEnabled();
    uint128 previousMinimumDeposit = hookedMarket.minimumDeposit;
    hookedMarket.minimumDeposit = newMinimumDeposit;
    emit MinimumDepositUpdated(market, msg.sender, previousMinimumDeposit, newMinimumDeposit);
  }

  /// @notice moves a hooked market's maturity earlier when term reduction was enabled at creation.
  /// @dev the new time may be now or in the past. maturity can never be extended.
  function setFixedTermEndTime(
    address market,
    uint32 newFixedTermEndTime
  ) external onlyAdministrator {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (!hookedMarket.allowTermReduction && newFixedTermEndTime <= hookedMarket.fixedTermEndTime)
      revert TermReductionDisabled();
    if (newFixedTermEndTime > hookedMarket.fixedTermEndTime) revert IncreaseFixedTerm();
    uint32 previousFixedTermEndTime = hookedMarket.fixedTermEndTime;
    hookedMarket.fixedTermEndTime = newFixedTermEndTime;
    emit FixedTermUpdated(
      market,
      msg.sender,
      previousFixedTermEndTime,
      newFixedTermEndTime
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

  /// @notice returns the fixed-term configuration stored for `marketAddress`.
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
    // the conversion when no minimum is set.
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

  /// @notice blocks withdrawal queueing before maturity, then applies any withdrawal access policy.
  /// @dev at and after maturity, a gated withdrawal needs either market-specific known-lender
  ///      status or a current credential. execution of an existing request is never term-gated.
  function onQueueWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint /* scaledAmount */,
    MarketState calldata /* state */,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (market.fixedTermEndTime > block.timestamp) {
      revert WithdrawBeforeTermEnd();
    }
    LenderStatus memory status = _lenderStatus[lender];
    if (market.withdrawalRequiresAccess) {
      if (
        !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
      ) {
        revert NotApprovedLender();
      }
    }
  }

  /// @dev execution stays permissionless once the lender has queued the withdrawal.
  function onExecuteWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint128 /* normalizedAmountWithdrawn */,
    MarketState calldata /* state */,
    bytes calldata hooksData
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

  /// @dev fixed-term policy does not constrain borrower draws.
  function onBorrow(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}

  /// @dev fixed-term policy does not constrain repayments.
  function onRepay(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {}

  /// @notice enforces the deployment-time early-closure policy.
  /// @dev before maturity, closure needs either `allowClosureBeforeTerm` or `allowTermReduction`.
  ///      an allowed early close moves maturity to the closure timestamp. closure at or after
  ///      maturity needs no term-policy permission.
  function onCloseMarket(
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (block.timestamp < market.fixedTermEndTime) {
      if (!(market.allowTermReduction || market.allowClosureBeforeTerm)) {
        revert ClosureDisabledBeforeTerm();
      }
      uint32 previousFixedTermEndTime = market.fixedTermEndTime;
      market.fixedTermEndTime = uint32(block.timestamp);
      emit FixedTermUpdated(
        msg.sender,
        msg.sender,
        previousFixedTermEndTime,
        market.fixedTermEndTime
      );
    }
  }

  /// @dev quarantine reaches the maturity check in the ordinary queue callback that follows.
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

  /// @notice rejects APR reductions before maturity, then applies the shared reserve policy.
  /// @dev equal or higher APRs are allowed during the term, subject to the shared bounds.
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
    HookedMarket storage hookedMarket = _hookedMarkets[msg.sender];

    /* Revert if market is still in fixed term and new APR is lower than it was */
    if (
      (hookedMarket.fixedTermEndTime > block.timestamp) &&
      (annualInterestBips < intermediateState.annualInterestBips)
    ) {
      revert NoReducingAprBeforeTermEnd();
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

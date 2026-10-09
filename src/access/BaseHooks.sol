// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // BaseHooks
//  \ ^ /   Market setup, lender policy, and callback extension points.
//    V
//
//  MARKET SETUP
//  constructor(...)
//  _onCreateMarket(...)
//  _initializeMarket(...)
//  _readWordCd(...)
//  _readBoolCd(...)
//  _configureMarketAccess(...)
//  _onMarketConfigured(...)
//  _requireHookedMarket(...)
//  _readAccessConfig(...)
//
//  MINIMUM DEPOSITS
//  setMinimumDeposit(...)
//  _isDepositHookEnabled(...)
//  _writeMinimumDeposit(...)
//
//  DEPOSITS
//  onDeposit(...)
//  _processDeposit(...)
//  _checkDeposit(...)
//
//  TRANSFERS
//  onTransfer(...)
//  _processTransfer(...)
//  _checkTransfer(...)
//  isMarketTransferDisabled(...)
//  isMarketTransferRecipientAllowed(...)
//  _defaultTransferRecipientAllowed(...)
//  _featureTransferRecipientAllowed(...)
//
//  BORROWING
//  onBorrow(...)
//  _checkBorrow(...)
//
//  REPAYMENT
//  onRepay(...)
//  _checkRepay(...)
//
//  WITHDRAWAL QUEUEING
//  onQueueWithdrawal(...)
//  _checkWithdrawalSchedule(...)
//  _processWithdrawalAccess(...)
//  _checkQueueWithdrawal(...)
//
//  CLAIM COLLECTION
//  onExecuteWithdrawal(...)
//  _checkExecuteWithdrawal(...)
//
//  CLOSURE
//  onCloseMarket(...)
//  _validateCloseMarket(...)
//  _applyCloseMarket(...)
//
//  SANCTIONS
//  onNukeFromOrbit(...)
//  _checkNukeFromOrbit(...)
//
//  SUPPLY CAPACITY
//  onSetMaxTotalSupply(...)
//  _checkMaxTotalSupply(...)
//
//  INTEREST AND RESERVES
//  onSetAnnualInterestAndReserveRatioBips(...)
//  _applyAprUpdate(...)
//  _checkAprChange(...)
//
//  PROTOCOL FEES
//  onSetProtocolFeeBips(...)
//  _checkProtocolFeeBips(...)
// ═════

import './BaseAccessControls.sol';
import './MarketConstraintHooks.sol';
import './IMarketTransferPolicy.sol';

using BoolUtils for bool;

/// @dev memory view of the template's packed config. keep the stored config in the template.
struct AccessConfig {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

enum AprRoute {
  Ordinary,
  PendingReduction
}

/// @dev `_checkAprChange` validates `effectiveApr` and `effectiveReserve`, which the market will
///      apply. `requestedApr` and `requestedReserve` let rules inspect the original request too.
///      `AprRoute.PendingReduction` cannot change reserves: both reserve fields hold the market's
///      current reserve ratio from `intermediateState.reserveRatioBips`.
struct AprChange {
  address market;
  AprRoute route;
  uint16 requestedApr;
  uint16 requestedReserve;
  uint16 effectiveApr;
  uint16 effectiveReserve;
}

// ┌─ BaseHooks ────────────────────────────────────────────────────────────────
/// @title BaseHooks
///
/// @notice shared initialization, lender actions, and access configuration for hook templates.
///
/// @dev each template still owns its packed storage and public getters. the adapters read/write it.
abstract contract BaseHooks is BaseAccessControls, MarketConstraintHooks, IMarketTransferPolicy {
  // these empty defaults accept unknown callers too. a stateful feature must enable its callback
  // and authenticate the market before trusting it. don't change that for every existing template.

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when a hooked market's minimum deposit changes.
  event MinimumDepositUpdated(
    address indexed market,
    address indexed caller,
    uint128 previousMinimumDeposit,
    uint128 newMinimumDeposit
  );

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev this hooks instance hasn't registered the supplied market.
  error NotHookedMarket();

  /// @dev financial settings are frozen from the market's repayment date.
  error MarketInRepayment();

  /// @dev the scaled deposit is below the market's configured minimum.
  error DepositBelowMinimum();

  /// @dev the deposit callback is disabled, so a positive minimum can't be enforced.
  error DepositHookNotEnabled();

  /// @dev these flags can let a lender enter without the credentials needed to withdraw.
  error InvalidAccessConfiguration();

  /// @dev transfers are disabled for this market.
  error TransfersDisabled();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  HooksDeploymentConfig public immutable override config;

  // ░░▒▒▓▓██ [ MARKET SETUP ] ─────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(
    address _administrator,
    bytes memory args,
    HooksDeploymentConfig deploymentConfig
  )
    BaseAccessControls(_administrator)
    IHooks()
  {
    config = deploymentConfig;
    if (args.length > 0) {
      NameAndProviderInputs memory inputs = abi.decode(args, (NameAndProviderInputs));
      _initialize(inputs);
    }
  }

  // ┌─ _onCreateMarket ─────
  /// @dev keep bounds and administrator checks ahead of template decoding.
  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  )
    internal
    override
    returns (HooksConfig marketHooksConfig)
  {
    super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
    if (administrator_ != administrator) revert CallerNotAdministrator();
    marketHooksConfig = _initializeMarket(administrator_, marketAddress, parameters, hooksData);
    _onMarketConfigured(administrator_, marketAddress, parameters, hooksData, marketHooksConfig);
  }

  // ┌─ _initializeMarket ─────
  /// @dev keep the template's decode order; it decides which failure the caller sees first.
  ///      write the packed config once, after decoding.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  )
    internal
    virtual
    returns (HooksConfig);

  // ┌─ _readWordCd ─────
  /// @dev preserve the policy payload's raw calldata reads, including optional/trailing words.
  ///      callers apply their own checked narrowing; this deliberately does not ABI-decode bytes.
  function _readWordCd(bytes calldata data, uint256 offset) internal pure returns (uint256 value) {
    assembly {
      value := calldataload(add(data.offset, offset))
    }
  }

  // ┌─ _readBoolCd ─────
  /// @dev policy flags use the low bit, including for noncanonical boolean words.
  function _readBoolCd(bytes calldata data, uint256 offset) internal pure returns (bool) {
    return _readWordCd(data, offset) & 1 != 0;
  }

  // ┌─ _configureMarketAccess ─────
  /// @dev capture access requirements before forcing or merging callback flags. an enabled
  ///      callback doesn't necessarily require credentials.
  function _configureMarketAccess(
    address administrator_,
    address market,
    HooksConfig requested,
    uint128 minimumDeposit,
    bool transfersDisabled
  )
    internal
    returns (AccessConfig memory access, bool depositHookEnabled, HooksConfig effective)
  {
    access = AccessConfig({
      isHooked: true,
      transferRequiresAccess: requested.useOnTransfer(),
      depositRequiresAccess: requested.useOnDeposit(),
      withdrawalRequiresAccess: requested.useOnQueueWithdrawal(),
      minimumDeposit: minimumDeposit,
      transfersDisabled: transfersDisabled
    });
    if (access.withdrawalRequiresAccess) {
      if (!access.depositRequiresAccess) revert InvalidAccessConfiguration();
      if (!transfersDisabled && !access.transferRequiresAccess) revert InvalidAccessConfiguration();
    }

    effective = requested;
    if (minimumDeposit > 0) {
      effective = effective.setFlag(Bit_Enabled_Deposit);
      emit MinimumDepositUpdated(market, administrator_, 0, minimumDeposit);
    }
    if (transfersDisabled) effective = effective.setFlag(Bit_Enabled_Transfer);
    if (access.withdrawalRequiresAccess) {
      effective = effective.setFlag(Bit_Enabled_Transfer).setFlag(Bit_Enabled_Deposit);
    }
    effective = effective.mergeFlags(config);
    depositHookEnabled = effective.useOnDeposit();
  }

  // ┌─ _onMarketConfigured ─────
  /// @dev the packed config is written, but the market isn't deployed yet. add feature setup
  ///      and checks here. reverting rolls back config and every event from this creation callback.
  function _onMarketConfigured(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    HooksConfig effective
  )
    internal
    virtual { }

  // ┌─ _requireHookedMarket ─────
  /// @dev markets can register before they're deployed. don't query market code or state here.
  function _requireHookedMarket(address market) internal view returns (AccessConfig memory access) {
    access = _readAccessConfig(market);
    if (!access.isHooked) revert NotHookedMarket();
  }

  // ┌─ _readAccessConfig ─────
  function _readAccessConfig(address market) internal view virtual returns (AccessConfig memory);

  // ░░▒▒▓▓██ [ MINIMUM DEPOSITS ] ─────────────────────────────────────────────

  // ┌─ setMinimumDeposit ─────
  /// @notice update a hooked market's minimum deposit.
  ///
  /// @dev callback flags can't change. a positive minimum needs `onDeposit` already enabled.
  ///      the minimum is frozen from an enabled repayment date.
  ///      leave the width check to the adapter, after the caller, market and dispatch checks.
  ///
  /// @param newMinimumDeposit normalized underlying-asset units required per deposit.
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyAdministrator {
    AccessConfig memory access = _requireHookedMarket(market);
    if (_isMarketInRepayment(market)) revert MarketInRepayment();
    if (newMinimumDeposit > 0 && !_isDepositHookEnabled(market)) revert DepositHookNotEnabled();
    uint128 previousMinimumDeposit = access.minimumDeposit;
    _writeMinimumDeposit(market, newMinimumDeposit);
    emit MinimumDepositUpdated(market, msg.sender, previousMinimumDeposit, newMinimumDeposit);
  }

  // ┌─ _isDepositHookEnabled ─────
  function _isDepositHookEnabled(address market) internal view virtual returns (bool);

  // ┌─ _writeMinimumDeposit ─────
  function _writeMinimumDeposit(address market, uint128 value) internal virtual;

  // ░░▒▒▓▓██ [ DEPOSITS ] ─────────────────────────────────────────────────────

  // ┌─ onDeposit ─────
  /// @notice enforce the minimum deposit, lender entry policy, and additional deposit rules.
  ///
  /// @dev default processing can update credentials and known-lender state. a later check reverting
  ///      rolls those changes back, before the market does its deposit accounting.
  function onDeposit(
    address lender,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  )
    external
    override
  {
    AccessConfig memory access = _requireHookedMarket(msg.sender);
    _processDeposit(access, lender, scaledAmount, state, hooksData);
    _checkDeposit(lender, scaledAmount, state, hooksData);
  }

  // ┌─ _processDeposit ─────
  /// @dev replacing this default means owning any skipped block, minimum, or credential checks
  ///      and their bookkeeping. additional restrictions belong in `_checkDeposit`.
  function _processDeposit(
    AccessConfig memory access,
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual
  {
    LenderStatus memory status = _lenderStatus[lender];
    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    // floor both sides the same way as the market. converting back to normalized units can
    // reject an exact-minimum deposit; the rounding tolerance is at most one scaled token.
    if (access.minimumDeposit > 0) {
      if (MathUtils.mulDiv(access.minimumDeposit, RAY, state.scaleFactor) > scaledAmount) {
        revert DepositBelowMinimum();
      }
    }

    // resolve credentials even when they're optional, so a valid one still makes the lender known.
    (bool hasValidCredential, bool roleUpdated) = _tryValidateAccessInner(status, lender, extraData);
    if (access.depositRequiresAccess.and(!hasValidCredential)) revert NotApprovedLender();
    _writeLenderStatus(status, lender, hasValidCredential, roleUpdated, true);
  }

  // ┌─ _checkDeposit ─────
  function _checkDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual { }

  // ░░▒▒▓▓██ [ TRANSFERS ] ────────────────────────────────────────────────────

  // ┌─ onTransfer ─────
  /// @notice enforce the recipient's transfer policy and additional transfer rules.
  ///
  /// @dev known recipients and the registered wrapper skip default credential/block checks.
  ///      they still reach `_checkTransfer`; an exemption isn't permission to skip feature rules.
  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    external
    override
  {
    AccessConfig memory access = _requireHookedMarket(msg.sender);
    _processTransfer(access, caller, from, to, scaledAmount, state, extraData);
    _checkTransfer(caller, from, to, scaledAmount, state, extraData);
  }

  // ┌─ _processTransfer ─────
  /// @dev replacement owns the disabled-transfer check, credential exemptions, and bookkeeping.
  ///      keep exemption returns in this helper so the coordinator still runs feature checks.
  function _processTransfer(
    AccessConfig memory access,
    address caller,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual
  {
    if (access.transfersDisabled) revert TransfersDisabled();
    if (isKnownLenderOnMarket[to][msg.sender]) return;
    if (_isRegisteredWrapper(msg.sender, to)) return;

    LenderStatus memory status = _lenderStatus[to];
    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    // optional credentials still count as entry. don't lose known-lender state on an open transfer.
    (bool hasValidCredential, bool wasUpdated) = _tryValidateAccessInner(status, to, extraData);
    if (access.transferRequiresAccess.and(!hasValidCredential)) revert NotApprovedLender();
    _writeLenderStatus(status, to, hasValidCredential, wasUpdated, true);
  }

  // ┌─ _checkTransfer ─────
  function _checkTransfer(
    address caller,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual { }

  // ┌─ isMarketTransferDisabled ─────
  /// @notice report whether every market-token transfer is disabled for this market.
  ///
  /// @dev reverts for an unregistered market. false is permanent; features must preserve that
  ///      promise when adding transfer rules.
  function isMarketTransferDisabled(address marketAddress) external view override returns (bool) {
    return _requireHookedMarket(marketAddress).transfersDisabled;
  }

  // ┌─ isMarketTransferRecipientAllowed ─────
  /// @notice report whether `recipient` can receive tokens now without hook data.
  ///
  /// @dev reverts for an unregistered market. credential exemptions still need feature approval.
  function isMarketTransferRecipientAllowed(
    address marketAddress,
    address recipient
  )
    external
    view
    override
    returns (bool)
  {
    AccessConfig memory access = _requireHookedMarket(marketAddress);
    return _defaultTransferRecipientAllowed(marketAddress, recipient, access)
      && _featureTransferRecipientAllowed(marketAddress, recipient);
  }

  // ┌─ _defaultTransferRecipientAllowed ─────
  function _defaultTransferRecipientAllowed(
    address market,
    address recipient,
    AccessConfig memory access
  )
    internal
    view
    returns (bool)
  {
    return
      !access.transfersDisabled && _isMarketTransferRecipientAllowed(market, recipient, access.transferRequiresAccess);
  }

  // ┌─ _featureTransferRecipientAllowed ─────
  /// @dev keep this in sync with any recipient restriction added by `_checkTransfer`.
  function _featureTransferRecipientAllowed(address market, address recipient) internal view virtual returns (bool) {
    return true;
  }

  // ░░▒▒▓▓██ [ BORROWING ] ────────────────────────────────────────────────────

  // ┌─ onBorrow ─────
  function onBorrow(uint normalizedAmount, MarketState calldata state, bytes calldata extraData) external override {
    _checkBorrow(normalizedAmount, state, extraData);
  }

  // ┌─ _checkBorrow ─────
  function _checkBorrow(uint256 amount, MarketState calldata state, bytes calldata extraData) internal virtual { }

  // ░░▒▒▓▓██ [ REPAYMENT ] ────────────────────────────────────────────────────

  // ┌─ onRepay ─────
  function onRepay(uint normalizedAmount, MarketState calldata state, bytes calldata hooksData) external override {
    _checkRepay(normalizedAmount, state, hooksData);
  }

  // ┌─ _checkRepay ─────
  function _checkRepay(uint256 amount, MarketState calldata state, bytes calldata extraData) internal virtual { }

  // ░░▒▒▓▓██ [ WITHDRAWAL QUEUEING ] ──────────────────────────────────────────

  // ┌─ onQueueWithdrawal ─────
  /// @notice check the withdrawal schedule, lender access, and additional queue rules.
  ///
  /// @dev the market still chooses the batch and expiry. queueing doesn't make a lender known.
  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  )
    external
    override
  {
    AccessConfig memory access = _requireHookedMarket(msg.sender);
    _checkWithdrawalSchedule(lender, expiry, scaledAmount, state, hooksData);
    _processWithdrawalAccess(access, lender, hooksData);
    _checkQueueWithdrawal(lender, expiry, scaledAmount, state, hooksData);
  }

  // ┌─ _checkWithdrawalSchedule ─────
  function _checkWithdrawalSchedule(
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    view
    virtual { }

  // ┌─ _processWithdrawalAccess ─────
  /// @dev known status survives credential loss and deposit blocks. keep exemptions here so
  ///      they don't skip the coordinator's additional queue check.
  function _processWithdrawalAccess(
    AccessConfig memory access,
    address lender,
    bytes calldata extraData
  )
    internal
    virtual
  {
    if (!access.withdrawalRequiresAccess) return;
    LenderStatus memory status = _lenderStatus[lender];
    if (!isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, extraData)) {
      revert NotApprovedLender();
    }
  }

  // ┌─ _checkQueueWithdrawal ─────
  function _checkQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual { }

  // ░░▒▒▓▓██ [ CLAIM COLLECTION ] ─────────────────────────────────────────────

  // ┌─ onExecuteWithdrawal ─────
  /// @dev compatibility callback; v2.5 markets never dispatch it. the default adds no claim restrictions.
  ///      don't reuse the queue's credential/window checks.
  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata state,
    bytes calldata hooksData
  )
    external
    override
  {
    _checkExecuteWithdrawal(lender, expiry, normalizedAmountWithdrawn, state, hooksData);
  }

  // ┌─ _checkExecuteWithdrawal ─────
  function _checkExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 amount,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual { }

  // ░░▒▒▓▓██ [ CLOSURE ] ──────────────────────────────────────────────────────

  // ┌─ onCloseMarket ─────
  /// @notice validate explicit closure before applying the hook's closure effects.
  ///
  /// @dev the term policy owns caller checks. open-term closure stays an unguarded no-op.
  ///      the market resets APR/reserves after this; don't invent an APR callback here.
  ///      automatic closure from an enabled repayment date bypasses this callback and its effects.
  function onCloseMarket(MarketState calldata state, bytes calldata hooksData) external override {
    _validateCloseMarket(state, hooksData);
    _applyCloseMarket(state, hooksData);
  }

  // ┌─ _validateCloseMarket ─────
  function _validateCloseMarket(MarketState calldata state, bytes calldata extraData) internal view virtual { }

  // ┌─ _applyCloseMarket ─────
  function _applyCloseMarket(MarketState calldata state, bytes calldata extraData) internal virtual { }

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  // ┌─ onNukeFromOrbit ─────
  /// @dev quarantine uses the ordinary queue path. its callback and schedule checks run only
  ///      before an enabled repayment date.
  function onNukeFromOrbit(address lender, MarketState calldata state, bytes calldata hooksData) external override {
    _checkNukeFromOrbit(lender, state, hooksData);
  }

  // ┌─ _checkNukeFromOrbit ─────
  function _checkNukeFromOrbit(address lender, MarketState calldata state, bytes calldata extraData)
    internal
    virtual { }

  // ░░▒▒▓▓██ [ SUPPLY CAPACITY ] ──────────────────────────────────────────────

  // ┌─ onSetMaxTotalSupply ─────
  /// @notice reject capacity changes from an enabled repayment date, then run feature checks.
  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata state,
    bytes calldata hooksData
  )
    external
    override
  {
    if (_isMarketInRepayment(msg.sender)) revert MarketInRepayment();
    _checkMaxTotalSupply(maxTotalSupply, state, hooksData);
  }

  // ┌─ _checkMaxTotalSupply ─────
  function _checkMaxTotalSupply(uint256 amount, MarketState calldata state, bytes calldata extraData)
    internal
    virtual { }

  // ░░▒▒▓▓██ [ INTEREST AND RESERVES ] ────────────────────────────────────────

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  /// @notice calculate the APR/reserve update, then validate the values the market will apply.
  ///
  /// @dev `_applyAprUpdate` may change hook state and emit events. if `_checkAprChange` reverts,
  ///      those effects revert too, including temporary reserves and pending APR proposal changes.
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata hooksData
  )
    external
    override
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips)
  {
    (updatedAnnualInterestBips, updatedReserveRatioBips) =
      _applyAprUpdate(annualInterestBips, reserveRatioBips, intermediateState, hooksData);
    _checkAprChange(
      AprChange({
        market: msg.sender,
        route: AprRoute.Ordinary,
        requestedApr: annualInterestBips,
        requestedReserve: reserveRatioBips,
        effectiveApr: updatedAnnualInterestBips,
        effectiveReserve: updatedReserveRatioBips
      }),
      intermediateState,
      hooksData
    );
  }

  // ┌─ _applyAprUpdate ─────
  /// @dev delegates to `_applyDefaultAprUpdate`, which ignores the requested `reserveRatioBips`
  ///      and derives reserves from `state` and `temporaryExcessReserveRatio[msg.sender]`.
  ///      override `_applyAprUpdate` if the calculation needs the requested ratio or callback data.
  ///      call only the chosen calculation: discarding its return values doesn't undo its state
  ///      changes or events.
  function _applyAprUpdate(
    uint16 annualInterestBips,
    uint16,
    MarketState calldata state,
    bytes calldata
  )
    internal
    virtual
    returns (uint16 effectiveApr, uint16 effectiveReserve)
  {
    return _applyDefaultAprUpdate(annualInterestBips, state);
  }

  // ┌─ _checkAprChange ─────
  /// @dev validate `change.effectiveApr` and `change.effectiveReserve`; revert to reject.
  ///      runs after APR effects on both `AprRoute.Ordinary` and `AprRoute.PendingReduction`.
  ///      overrides can add constraints or feature state, but don't return replacement values.
  function _checkAprChange(
    AprChange memory change,
    MarketState calldata state,
    bytes calldata extraData
  )
    internal
    virtual { }

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  // ┌─ onSetProtocolFeeBips ─────
  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState memory intermediateState,
    bytes calldata extraData
  )
    external
    override
  {
    _checkProtocolFeeBips(protocolFeeBips, intermediateState, extraData);
  }

  // ┌─ _checkProtocolFeeBips ─────
  function _checkProtocolFeeBips(uint16 bips, MarketState memory state, bytes calldata extraData) internal virtual { }
}

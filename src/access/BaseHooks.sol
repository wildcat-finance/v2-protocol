// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

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

/// @title BaseHooks
/// @notice shared initialization, lender actions, and access configuration for hook templates.
/// @dev each template still owns its packed storage and public getters. the adapters read/write it.
abstract contract BaseHooks is BaseAccessControls, MarketConstraintHooks, IMarketTransferPolicy {
  /// @notice emitted when a hooked market's minimum deposit changes.
  event MinimumDepositUpdated(
    address indexed market,
    address indexed caller,
    uint128 previousMinimumDeposit,
    uint128 newMinimumDeposit
  );

  /// @dev this hooks instance hasn't registered the supplied market.
  error NotHookedMarket();
  /// @dev the scaled deposit is below the market's configured minimum.
  error DepositBelowMinimum();
  /// @dev the deposit callback is disabled, so a positive minimum can't be enforced.
  error DepositHookNotEnabled();
  /// @dev these flags can let a lender enter without the credentials needed to withdraw.
  error InvalidAccessConfiguration();
  /// @dev transfers are disabled for this market.
  error TransfersDisabled();

  HooksDeploymentConfig public immutable override config;

  constructor(
    address _administrator,
    bytes memory args,
    HooksDeploymentConfig deploymentConfig
  ) BaseAccessControls(_administrator) IHooks() {
    config = deploymentConfig;
    if (args.length > 0) {
      NameAndProviderInputs memory inputs = abi.decode(args, (NameAndProviderInputs));
      _initialize(inputs);
    }
  }

  function _readAccessConfig(address market) internal view virtual returns (AccessConfig memory);

  function _isDepositHookEnabled(address market) internal view virtual returns (bool);

  function _writeMinimumDeposit(address market, uint128 value) internal virtual;

  /// @dev markets can register before they're deployed. don't query market code or state here.
  function _requireHookedMarket(address market) internal view returns (AccessConfig memory access) {
    access = _readAccessConfig(market);
    if (!access.isHooked) revert NotHookedMarket();
  }

  /// @dev keep bounds and administrator checks ahead of template decoding.
  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
    if (administrator_ != administrator) revert CallerNotAdministrator();
    marketHooksConfig = _initializeMarket(administrator_, marketAddress, parameters, hooksData);
    _onMarketConfigured(administrator_, marketAddress, parameters, hooksData, marketHooksConfig);
  }

  /// @dev keep the template's decode order; it decides which failure the caller sees first.
  ///      write the packed config once, after decoding.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual returns (HooksConfig);

  /// @dev capture access requirements before forcing or merging callback flags. an enabled
  ///      callback doesn't necessarily require credentials.
  function _configureMarketAccess(
    address administrator_,
    address market,
    HooksConfig requested,
    uint128 minimumDeposit,
    bool transfersDisabled
  ) internal returns (AccessConfig memory access, bool depositHookEnabled, HooksConfig effective) {
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

  /// @dev the packed config is written, but the market isn't deployed yet. add feature setup
  ///      and checks here. reverting rolls back config and every event from this creation callback.
  function _onMarketConfigured(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    HooksConfig effective
  ) internal virtual {}

  /// @notice updates a hooked market's minimum deposit.
  /// @dev callback flags can't change. a positive minimum needs `onDeposit` already enabled.
  ///      leave the width check to the adapter, after the caller, market and dispatch checks.
  /// @param newMinimumDeposit normalized underlying-asset units required per deposit.
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyAdministrator {
    AccessConfig memory access = _requireHookedMarket(market);
    if (newMinimumDeposit > 0 && !_isDepositHookEnabled(market)) revert DepositHookNotEnabled();
    uint128 previousMinimumDeposit = access.minimumDeposit;
    _writeMinimumDeposit(market, newMinimumDeposit);
    emit MinimumDepositUpdated(market, msg.sender, previousMinimumDeposit, newMinimumDeposit);
  }

  /// @notice says whether every market-token transfer is disabled for this market.
  /// @dev reverts for an unregistered market. false is permanent; features must preserve that
  ///      promise when adding transfer rules.
  function isMarketTransferDisabled(address marketAddress) external view override returns (bool) {
    return _requireHookedMarket(marketAddress).transfersDisabled;
  }

  /// @notice says whether `recipient` can receive tokens now without hook data.
  /// @dev reverts for an unregistered market. credential exemptions still need feature approval.
  function isMarketTransferRecipientAllowed(
    address marketAddress,
    address recipient
  ) external view override returns (bool) {
    AccessConfig memory access = _requireHookedMarket(marketAddress);
    return
      _defaultTransferRecipientAllowed(marketAddress, recipient, access) &&
      _featureTransferRecipientAllowed(marketAddress, recipient);
  }

  function _defaultTransferRecipientAllowed(
    address market,
    address recipient,
    AccessConfig memory access
  ) internal view returns (bool) {
    return
      !access.transfersDisabled &&
      _isMarketTransferRecipientAllowed(market, recipient, access.transferRequiresAccess);
  }

  /// @dev keep this in sync with any recipient restriction added by `_checkTransfer`.
  function _featureTransferRecipientAllowed(
    address market,
    address recipient
  ) internal view virtual returns (bool) {
    return true;
  }

  /// @notice enforces the minimum deposit, lender entry policy, and additional deposit rules.
  /// @dev default processing can update credentials and known-lender state. a later check reverting
  ///      rolls those changes back, before the market does its deposit accounting.
  function onDeposit(
    address lender,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    AccessConfig memory access = _requireHookedMarket(msg.sender);
    _processDeposit(access, lender, scaledAmount, state, hooksData);
    _checkDeposit(lender, scaledAmount, state, hooksData);
  }

  /// @dev replacing this default means owning any skipped block, minimum, or credential checks
  ///      and their bookkeeping. additional restrictions belong in `_checkDeposit`.
  function _processDeposit(
    AccessConfig memory access,
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {
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
    (bool hasValidCredential, bool roleUpdated) = _tryValidateAccessInner(
      status,
      lender,
      extraData
    );
    if (access.depositRequiresAccess.and(!hasValidCredential)) revert NotApprovedLender();
    _writeLenderStatus(status, lender, hasValidCredential, roleUpdated, true);
  }

  function _checkDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  /// @notice enforces the recipient's transfer policy and additional transfer rules.
  /// @dev known recipients and the registered wrapper skip default credential/block checks.
  ///      they still reach `_checkTransfer`; an exemption isn't permission to skip feature rules.
  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {
    AccessConfig memory access = _requireHookedMarket(msg.sender);
    _processTransfer(access, caller, from, to, scaledAmount, state, extraData);
    _checkTransfer(caller, from, to, scaledAmount, state, extraData);
  }

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
  ) internal virtual {
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

  function _checkTransfer(
    address caller,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  /// @notice checks the withdrawal schedule, lender access, and additional queue rules.
  /// @dev the market still chooses the batch and expiry. queueing doesn't make a lender known.
  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    AccessConfig memory access = _requireHookedMarket(msg.sender);
    _checkWithdrawalSchedule(lender, expiry, scaledAmount, state, hooksData);
    _processWithdrawalAccess(access, lender, hooksData);
    _checkQueueWithdrawal(lender, expiry, scaledAmount, state, hooksData);
  }

  function _checkWithdrawalSchedule(
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal view virtual {}

  /// @dev known status survives credential loss and deposit blocks. keep exemptions here so
  ///      they don't skip the coordinator's additional queue check.
  function _processWithdrawalAccess(
    AccessConfig memory access,
    address lender,
    bytes calldata extraData
  ) internal virtual {
    if (!access.withdrawalRequiresAccess) return;
    LenderStatus memory status = _lenderStatus[lender];
    if (
      !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, extraData)
    ) {
      revert NotApprovedLender();
    }
  }

  function _checkQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  /// @notice validates closure before applying the hook's closure effects.
  /// @dev the term policy owns caller checks. open-term closure stays an unguarded no-op.
  ///      the market resets APR/reserves after this; don't invent an APR callback here.
  function onCloseMarket(MarketState calldata state, bytes calldata hooksData) external override {
    _validateCloseMarket(state, hooksData);
    _applyCloseMarket(state, hooksData);
  }

  function _validateCloseMarket(
    MarketState calldata state,
    bytes calldata extraData
  ) internal view virtual {}

  function _applyCloseMarket(
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  // these empty defaults accept unknown callers too. a stateful feature must enable its callback
  // and authenticate the market before trusting it. don't change that for every existing template.

  /// @dev queued claims stay ungated by default. don't reuse the queue's credential/window checks.
  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    _checkExecuteWithdrawal(lender, expiry, normalizedAmountWithdrawn, state, hooksData);
  }

  function _checkExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 amount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata extraData
  ) external override {
    _checkBorrow(normalizedAmount, state, extraData);
  }

  function _checkBorrow(
    uint256 amount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  function onRepay(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    _checkRepay(normalizedAmount, state, hooksData);
  }

  function _checkRepay(
    uint256 amount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  /// @dev quarantine reaches the ordinary queue callback next, including its schedule checks.
  function onNukeFromOrbit(
    address lender,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    _checkNukeFromOrbit(lender, state, hooksData);
  }

  function _checkNukeFromOrbit(
    address lender,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    _checkMaxTotalSupply(maxTotalSupply, state, hooksData);
  }

  function _checkMaxTotalSupply(
    uint256 amount,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  /// @notice calculates the APR/reserve update, then validates the values the market will apply.
  /// @dev `_applyAprUpdate` may change hook state and emit events. if `_checkAprChange` reverts,
  ///      those effects revert too, including temporary reserves and pending APR proposal changes.
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata hooksData
  ) external override returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips) {
    (updatedAnnualInterestBips, updatedReserveRatioBips) = _applyAprUpdate(
      annualInterestBips,
      reserveRatioBips,
      intermediateState,
      hooksData
    );
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
  ) internal virtual returns (uint16 effectiveApr, uint16 effectiveReserve) {
    return _applyDefaultAprUpdate(annualInterestBips, state);
  }

  /// @dev validate `change.effectiveApr` and `change.effectiveReserve`; revert to reject.
  ///      runs after APR effects on both `AprRoute.Ordinary` and `AprRoute.PendingReduction`.
  ///      overrides can add constraints or feature state, but don't return replacement values.
  function _checkAprChange(
    AprChange memory change,
    MarketState calldata state,
    bytes calldata extraData
  ) internal virtual {}

  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState memory intermediateState,
    bytes calldata extraData
  ) external override {
    _checkProtocolFeeBips(protocolFeeBips, intermediateState, extraData);
  }

  function _checkProtocolFeeBips(
    uint16 bips,
    MarketState memory state,
    bytes calldata extraData
  ) internal virtual {}
}

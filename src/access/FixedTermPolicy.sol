// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // FixedTermPolicy
//  \ ^ /   Fixed maturity, term reductions, withdrawal and APR rules.
//    V
//
//  MARKET SETUP
//  _getParameterConstraints()
//  _initializeMarket(...)
//
//  ACCESS CONFIGURATION
//  _readAccessConfig(...)
//  _isDepositHookEnabled(...)
//  _writeMinimumDeposit(...)
//
//  TERM CHANGES
//  setFixedTermEndTime(...)
//  _validateFixedTermChange(...)
//  _afterFixedTermChange(...)
//
//  WITHDRAWAL QUEUEING
//  _checkWithdrawalSchedule(...)
//
//  CLOSURE
//  _validateCloseMarket(...)
//  _applyCloseMarket(...)
//
//  INTEREST
//  _applyAprUpdate(...)
//  _validateFixedAprUpdate(...)
// ═════

import './BaseHooks.sol';
import './types/FixedTermHookTypes.sol';
import '../libraries/SafeCastLib.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

// ┌─ FixedTermPolicy ──────────────────────────────────────────────────────────
/// @title FixedTermPolicy
///
/// @notice reusable fixed-term configuration and rules over BaseHooks.
///
/// @dev `_hookedMarkets` owns the maturity used by queueing, APR updates, closure and term changes.
///      the concrete hook supplies BaseHooks constructor arguments and public
///      configuration getters.
abstract contract FixedTermPolicy is BaseHooks {
  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when an allowed term reduction moves a market's maturity earlier.
  event FixedTermUpdated(
    address indexed market,
    address indexed caller,
    uint32 previousFixedTermEndTime,
    uint32 newFixedTermEndTime
  );

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev market-creation hook data omitted the fixed-term timestamp.
  error FixedTermNotProvided();

  /// @dev maturity is earlier than now or more than 365 days away.
  error InvalidFixedTerm();

  /// @dev a term update tried to move maturity later.
  error IncreaseFixedTerm();

  /// @dev the lender tried to queue a withdrawal before maturity.
  error WithdrawBeforeTermEnd();

  /// @dev the borrower tried to reduce APR before maturity.
  error NoReducingAprBeforeTermEnd();

  /// @dev the borrower tried to close before maturity without permission.
  error ClosureDisabledBeforeTerm();

  /// @dev this market was not configured to allow term reductions.
  error TermReductionDisabled();
  error RepaymentBeforeMaturity();

  // ░░▒▒▓▓██ [ STATE ] ────────────────────────────────────────────────────────

  /// @notice longest fixed term accepted when a market is attached.
  uint32 public constant MaximumLoanTerm = 365 days;

  mapping(address => HookedMarket) internal _hookedMarkets;
  // keep immutable dispatch separate; adding it to HookedMarket would change the public tuple.
  mapping(address => bool) internal _depositHookEnabled;

  // ░░▒▒▓▓██ [ MARKET SETUP ] ─────────────────────────────────────────────────

  // ┌─ _getParameterConstraints ─────
  function _getParameterConstraints()
    internal
    view
    virtual
    override
    returns (MarketParameterConstraints memory constraints)
  {
    constraints = super._getParameterConstraints();
    constraints.maximumRepaymentDateDelay = type(uint32).max;
  }

  // ┌─ _initializeMarket ─────
  /// @dev bind the market after BaseHooks checks `administrator_` against the current
  ///      administrator. `hooksData` is `(uint32 fixedTermEndTime, uint128 minimumDeposit?,
  ///      bool transfersDisabled?, bool allowClosureBeforeTerm?, bool allowTermReduction?)`.
  ///      maturity is required, can't be in the past, and can't be more than 365 days away.
  ///      gated withdrawals need gated deposits and gated or disabled transfers. otherwise a
  ///      lender can enter without credentials and get stuck on exit.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  )
    internal
    virtual
    override
    returns (HooksConfig marketHooksConfig)
  {
    if (hooksData.length < 32) revert FixedTermNotProvided();
    uint32 fixedTermEndTime = _readWordCd(hooksData, 0).toUint32();
    if (fixedTermEndTime < block.timestamp || (fixedTermEndTime - block.timestamp) > MaximumLoanTerm) {
      revert InvalidFixedTerm();
    }
    if (parameters.repaymentDate != 0 && parameters.repaymentDate < fixedTermEndTime) {
      revert RepaymentBeforeMaturity();
    }
    emit FixedTermUpdated(marketAddress, administrator_, 0, fixedTermEndTime);

    (AccessConfig memory access, bool depositHookEnabled, HooksConfig effective) = _configureMarketAccess(
      administrator_,
      marketAddress,
      parameters.hooks,
      _readWordCd(hooksData, 0x20).toUint128(),
      _readBoolCd(hooksData, 0x40)
    );
    _depositHookEnabled[marketAddress] = depositHookEnabled;
    _hookedMarkets[marketAddress] = HookedMarket({
      isHooked: access.isHooked,
      transferRequiresAccess: access.transferRequiresAccess,
      depositRequiresAccess: access.depositRequiresAccess,
      withdrawalRequiresAccess: access.withdrawalRequiresAccess,
      fixedTermEndTime: fixedTermEndTime,
      allowClosureBeforeTerm: _readBoolCd(hooksData, 0x60),
      allowTermReduction: _readBoolCd(hooksData, 0x80),
      minimumDeposit: access.minimumDeposit,
      transfersDisabled: access.transfersDisabled
    });
    return effective;
  }

  // ░░▒▒▓▓██ [ ACCESS CONFIGURATION ] ─────────────────────────────────────────

  // ┌─ _readAccessConfig ─────
  function _readAccessConfig(address market) internal view virtual override returns (AccessConfig memory) {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    return AccessConfig({
      isHooked: hookedMarket.isHooked,
      transferRequiresAccess: hookedMarket.transferRequiresAccess,
      depositRequiresAccess: hookedMarket.depositRequiresAccess,
      withdrawalRequiresAccess: hookedMarket.withdrawalRequiresAccess,
      minimumDeposit: hookedMarket.minimumDeposit,
      transfersDisabled: hookedMarket.transfersDisabled
    });
  }

  // ┌─ _isDepositHookEnabled ─────
  function _isDepositHookEnabled(address market) internal view virtual override returns (bool) {
    return _depositHookEnabled[market];
  }

  // ┌─ _writeMinimumDeposit ─────
  function _writeMinimumDeposit(address market, uint128 value) internal virtual override {
    _hookedMarkets[market].minimumDeposit = value;
  }

  // ░░▒▒▓▓██ [ TERM CHANGES ] ─────────────────────────────────────────────────

  // ┌─ setFixedTermEndTime ─────
  /// @notice move a hooked market's maturity earlier when term reduction was enabled at creation.
  ///
  /// @dev the new time may be now or in the past. maturity can never be extended.
  ///      term changes are frozen from an enabled repayment date.
  function setFixedTermEndTime(address market, uint32 newFixedTermEndTime) external onlyAdministrator {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (_isMarketInRepayment(market)) revert MarketInRepayment();
    if (!hookedMarket.allowTermReduction && newFixedTermEndTime <= hookedMarket.fixedTermEndTime) {
      revert TermReductionDisabled();
    }
    if (newFixedTermEndTime > hookedMarket.fixedTermEndTime) revert IncreaseFixedTerm();
    uint32 previousFixedTermEndTime = hookedMarket.fixedTermEndTime;
    _validateFixedTermChange(market, previousFixedTermEndTime, newFixedTermEndTime);
    hookedMarket.fixedTermEndTime = newFixedTermEndTime;
    emit FixedTermUpdated(market, msg.sender, previousFixedTermEndTime, newFixedTermEndTime);
    _afterFixedTermChange(market, previousFixedTermEndTime, newFixedTermEndTime);
  }

  // ┌─ _validateFixedTermChange ─────
  /// @dev `setFixedTermEndTime` has passed its native checks; stored maturity is still
  ///      `previousTime`. add restrictions here before writing `newTime`.
  ///      creation and early closure use `_onMarketConfigured` and the closure helpers instead.
  function _validateFixedTermChange(address market, uint32 previousTime, uint32 newTime) internal view virtual { }

  // ┌─ _afterFixedTermChange ─────
  /// @dev stored maturity is now `newTime` and `FixedTermUpdated` has been emitted.
  ///      reverting rolls back the maturity, event, and any feature state written here.
  ///      this runs only from `setFixedTermEndTime`, not creation or early closure.
  function _afterFixedTermChange(address market, uint32 previousTime, uint32 newTime) internal virtual { }

  // ░░▒▒▓▓██ [ WITHDRAWAL QUEUEING ] ──────────────────────────────────────────

  // ┌─ _checkWithdrawalSchedule ─────
  /// @dev registration runs first in BaseHooks. maturity still wins over an access failure.
  function _checkWithdrawalSchedule(
    address,
    uint32,
    uint256,
    MarketState calldata,
    bytes calldata
  )
    internal
    view
    virtual
    override
  {
    if (_hookedMarkets[msg.sender].fixedTermEndTime > block.timestamp) {
      revert WithdrawBeforeTermEnd();
    }
  }

  // ░░▒▒▓▓██ [ CLOSURE ] ──────────────────────────────────────────────────────

  // ┌─ _validateCloseMarket ─────
  /// @dev before maturity, either `allowTermReduction` or `allowClosureBeforeTerm` permits closure.
  function _validateCloseMarket(MarketState calldata, bytes calldata) internal view virtual override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (block.timestamp < market.fixedTermEndTime) {
      if (!(market.allowTermReduction || market.allowClosureBeforeTerm)) {
        revert ClosureDisabledBeforeTerm();
      }
    }
  }

  // ┌─ _applyCloseMarket ─────
  /// @dev validation must run first. an allowed early close brings maturity forward to now.
  function _applyCloseMarket(MarketState calldata, bytes calldata) internal virtual override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (block.timestamp < market.fixedTermEndTime) {
      uint32 previousFixedTermEndTime = market.fixedTermEndTime;
      market.fixedTermEndTime = uint32(block.timestamp);
      emit FixedTermUpdated(msg.sender, msg.sender, previousFixedTermEndTime, market.fixedTermEndTime);
    }
  }

  // ░░▒▒▓▓██ [ INTEREST ] ─────────────────────────────────────────────────────

  // ┌─ _applyAprUpdate ─────
  /// @dev `_validateFixedAprUpdate` blocks APR reductions before `fixedTermEndTime`.
  ///      equal or higher APRs proceed to the bounds/reserve logic in `_applyDefaultAprUpdate`.
  ///      overriding `_applyDefaultAprUpdate` keeps that term check; overriding `_applyAprUpdate`
  ///      must call `_validateFixedAprUpdate` or explicitly replace the fixed-term APR restriction.
  function _applyAprUpdate(
    uint16 annualInterestBips,
    uint16,
    MarketState calldata intermediateState,
    bytes calldata
  )
    internal
    virtual
    override
    returns (uint16 effectiveApr, uint16 effectiveReserve)
  {
    _validateFixedAprUpdate(annualInterestBips, intermediateState);
    return _applyDefaultAprUpdate(annualInterestBips, intermediateState);
  }

  // ┌─ _validateFixedAprUpdate ─────
  /// @dev no registration check here: the existing APR callback accepts unknown callers.
  function _validateFixedAprUpdate(uint16 annualInterestBips, MarketState calldata intermediateState) internal view {
    HookedMarket storage hookedMarket = _hookedMarkets[msg.sender];

    if (
      (hookedMarket.fixedTermEndTime > block.timestamp) && (annualInterestBips < intermediateState.annualInterestBips)
    ) {
      revert NoReducingAprBeforeTermEnd();
    }
  }
}

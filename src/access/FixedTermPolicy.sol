// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './BaseHooks.sol';
import './types/FixedTermHookTypes.sol';
import '../libraries/SafeCastLib.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/// @title FixedTermPolicy
/// @notice reusable fixed-term configuration and rules over BaseHooks.
/// @dev `_hookedMarkets` owns the maturity used by queueing, APR updates, closure and term changes.
///      the concrete hook supplies BaseHooks constructor arguments and public
///      configuration getters.
abstract contract FixedTermPolicy is BaseHooks {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

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

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  /// @notice longest fixed term accepted when a market is attached.
  uint32 public constant MaximumLoanTerm = 365 days;

  mapping(address => HookedMarket) internal _hookedMarkets;
  // keep immutable dispatch separate; adding it to HookedMarket would change the public tuple.
  mapping(address => bool) internal _depositHookEnabled;

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

  /// @dev binds the market after BaseHooks checks `administrator_` against the current
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
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    if (hooksData.length < 32) revert FixedTermNotProvided();
    uint32 fixedTermEndTime = _readUint32Cd(hooksData);
    if (
      fixedTermEndTime < block.timestamp || (fixedTermEndTime - block.timestamp) > MaximumLoanTerm
    ) {
      revert InvalidFixedTerm();
    }
    emit FixedTermUpdated(marketAddress, administrator_, 0, fixedTermEndTime);

    (
      AccessConfig memory access,
      bool depositHookEnabled,
      HooksConfig effective
    ) = _configureMarketAccess(
        administrator_,
        marketAddress,
        parameters.hooks,
        _readUint128Cd(hooksData, 0x20),
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
    return _depositHookEnabled[market];
  }

  function _writeMinimumDeposit(address market, uint128 value) internal virtual override {
    _hookedMarkets[market].minimumDeposit = value;
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
    emit FixedTermUpdated(market, msg.sender, previousFixedTermEndTime, newFixedTermEndTime);
  }

  // ========================================================================== //
  //                                    Hooks                                   //
  // ========================================================================== //

  /// @dev registration runs first in BaseHooks. maturity still wins over an access failure.
  function _checkWithdrawalSchedule(
    address,
    uint32,
    uint256,
    MarketState calldata,
    bytes calldata
  ) internal view virtual override {
    if (_hookedMarkets[msg.sender].fixedTermEndTime > block.timestamp)
      revert WithdrawBeforeTermEnd();
  }

  function _validateCloseMarket(
    MarketState calldata,
    bytes calldata
  ) internal view virtual override {
    _validateFixedCloseMarket();
  }

  function _applyCloseMarket(MarketState calldata, bytes calldata) internal virtual override {
    _applyFixedCloseMarket();
  }

  /// @dev either early-close permission is enough. keep the existing OR rule.
  function _validateFixedCloseMarket() internal view {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (block.timestamp < market.fixedTermEndTime) {
      if (!(market.allowTermReduction || market.allowClosureBeforeTerm)) {
        revert ClosureDisabledBeforeTerm();
      }
    }
  }

  /// @dev validation must run first. an allowed early close brings maturity forward to now.
  function _applyFixedCloseMarket() internal {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (block.timestamp < market.fixedTermEndTime) {
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

  /// @dev `_validateFixedAprUpdate` blocks APR reductions before `fixedTermEndTime`.
  ///      equal or higher APRs proceed to the bounds/reserve logic in `_applyDefaultAprUpdate`.
  ///      overriding `_applyDefaultAprUpdate` keeps that term check; overriding `_applyAprUpdate`
  ///      must call `_validateFixedAprUpdate` or explicitly replace the fixed-term APR restriction.
  function _applyAprUpdate(
    uint16 annualInterestBips,
    uint16,
    MarketState calldata intermediateState,
    bytes calldata
  ) internal virtual override returns (uint16 effectiveApr, uint16 effectiveReserve) {
    _validateFixedAprUpdate(annualInterestBips, intermediateState);
    return _applyDefaultAprUpdate(annualInterestBips, intermediateState);
  }

  /// @dev no registration check here: the existing APR callback accepts unknown callers.
  function _validateFixedAprUpdate(
    uint16 annualInterestBips,
    MarketState calldata intermediateState
  ) internal view {
    HookedMarket storage hookedMarket = _hookedMarkets[msg.sender];

    /* Revert if market is still in fixed term and new APR is lower than it was */
    if (
      (hookedMarket.fixedTermEndTime > block.timestamp) &&
      (annualInterestBips < intermediateState.annualInterestBips)
    ) {
      revert NoReducingAprBeforeTermEnd();
    }
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WildcatMarketConfig
//  \ ^ /   Supply limits, interest terms, wrapper setup, and sanctions.
//    V
//
//  PERIODIC APR CALLBACK
//  executePendingAnnualInterestBipsReduction(...)
//
//  SUPPLY CAPACITY
//  setMaxTotalSupply(...)
//  maxTotalSupply()
//  maximumDeposit()
//
//  INTEREST AND RESERVES
//  setAnnualInterestAndReserveRatioBips(...)
//  executePendingAnnualInterestBipsReduction()
//  _applyAnnualInterestAndReserveRatioBips(...)
//  annualInterestBips()
//  reserveRatioBips()
//
//  PROTOCOL FEES
//  setProtocolFeeBips(...)
//
//  WRAPPER REGISTRATION
//  registerWrapper(...)
//
//  SANCTIONS
//  nukeFromOrbit(...)
//
//  STATUS
//  isClosed()
// ═════

import './WildcatMarketBase.sol';
import '../libraries/SafeCastLib.sol';

// ┌─ IPeriodicTermAprReductionHooks ───────────────────────────────────────────
/// @dev narrow callback used to execute a pending periodic-term APR reduction.
interface IPeriodicTermAprReductionHooks {
  // ░░▒▒▓▓██ [ PERIODIC APR CALLBACK ] ────────────────────────────────────────

  // ┌─ executePendingAnnualInterestBipsReduction ─────
  /// @dev validate the pending proposal against `intermediateState`, then consume it.
  ///
  /// @param intermediateState market state after current accrual and batch processing.
  ///
  /// @return annualInterestBips exact reduced APR the market should apply, in bips.
  function executePendingAnnualInterestBipsReduction(MarketState calldata intermediateState)
    external
    returns (uint16 annualInterestBips);
}

// ┌─ WildcatMarketConfig ──────────────────────────────────────────────────────
/// @notice market configuration, sanctions quarantine, and term-change entry points.
contract WildcatMarketConfig is WildcatMarketBase {
  using SafeCastLib for uint256;
  using FunctionTypeCasts for *;

  // ░░▒▒▓▓██ [ SUPPLY CAPACITY ] ──────────────────────────────────────────────

  // ┌─ setMaxTotalSupply ─────
  /// @notice set the normalized supply cap for future deposits.
  ///
  /// @dev only the borrower can call. the hook may accept or revert but can't rewrite the value.
  ///      this does not cap interest growth or force existing supply down.
  ///
  /// @param _maxTotalSupply new normalized deposit cap.
  function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyBorrower nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revertWithSelector(CapacityChangeOnClosedMarket_ErrorSelector);

    hooks.onSetMaxTotalSupply(_maxTotalSupply, state);
    uint256 previousMaxTotalSupply = state.maxTotalSupply;
    state.maxTotalSupply = _maxTotalSupply.toUint128();
    _writeState(state);
    emit_MaxTotalSupplyUpdated(msg.sender, previousMaxTotalSupply, _maxTotalSupply);
  }

  // ┌─ maxTotalSupply ─────
  /// @notice return the normalized supply cap applied to deposits.
  ///
  /// @dev interest can grow total supply above this value.
  function maxTotalSupply() external view returns (uint256) {
    return _state.maxTotalSupply;
  }

  // ┌─ maximumDeposit ─────
  /// @notice return the most underlying assets a deposit can currently add.
  ///
  /// @dev includes interest accrued through this block and saturates at zero.
  function maximumDeposit() external view returns (uint256) {
    if (_isInRepayment()) return 0;
    MarketState memory state = _calculateCurrentStatePointers.asReturnsMarketState()();
    return state.maximumDeposit();
  }

  // ░░▒▒▓▓██ [ INTEREST AND RESERVES ] ────────────────────────────────────────

  // ┌─ setAnnualInterestAndReserveRatioBips ─────
  /// @notice ask the market hook to apply new lender APR and reserve-ratio values.
  ///
  /// @dev only the borrower can call. the hook may rewrite both values and each result must stay at
  ///      or below 10,000 bips. a flat or lower reserve ratio requires the market to be healthy
  ///      already; a higher ratio must leave it healthy.
  ///
  /// @param _annualInterestBips proposed base annual lender rate, in bips.
  /// @param _reserveRatioBips   proposed reserve requirement, in bips.
  function setAnnualInterestAndReserveRatioBips(
    uint16 _annualInterestBips,
    uint16 _reserveRatioBips
  )
    external
    onlyBorrower
    nonReentrant
    sphereXGuardExternal
  {
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revertWithSelector(AprChangeOnClosedMarket_ErrorSelector);

    uint256 initialReserveRatioBips = state.reserveRatioBips;

    (_annualInterestBips, _reserveRatioBips) =
      hooks.onSetAnnualInterestAndReserveRatioBips(_annualInterestBips, _reserveRatioBips, state);

    _applyAnnualInterestAndReserveRatioBips(state, _annualInterestBips, _reserveRatioBips, initialReserveRatioBips);
  }

  // ┌─ executePendingAnnualInterestBipsReduction ─────
  /// @notice apply an executable periodic-term APR reduction; anyone can call.
  ///
  /// @dev the hook supplies the APR. the caller can't choose it or change the reserve ratio. the
  ///      hook enforces proposal timing and withdrawal conditions; non-periodic markets revert.
  function executePendingAnnualInterestBipsReduction() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revertWithSelector(AprChangeOnClosedMarket_ErrorSelector);
    if (!hooks.useOnExecutePendingAnnualInterestBipsReduction()) {
      revertWithSelector(ExecutePendingAprReductionNotEnabled_ErrorSelector);
    }

    uint16 currentAnnualInterestBips = state.annualInterestBips;
    uint16 _annualInterestBips =
      IPeriodicTermAprReductionHooks(hooks.hooksAddress()).executePendingAnnualInterestBipsReduction(state);

    if (_annualInterestBips >= currentAnnualInterestBips) {
      revertWithSelector(AprReductionNotReduction_ErrorSelector);
    }

    uint16 currentReserveRatioBips = state.reserveRatioBips;
    _applyAnnualInterestAndReserveRatioBips(
      state, _annualInterestBips, currentReserveRatioBips, currentReserveRatioBips
    );
  }

  // ┌─ _applyAnnualInterestAndReserveRatioBips ─────
  /// @dev when the ratio stays flat or falls, the market must be healthy under the current ratio.
  ///      when it rises, the market must remain healthy under the new ratio.
  function _applyAnnualInterestAndReserveRatioBips(
    MarketState memory state,
    uint16 _annualInterestBips,
    uint16 _reserveRatioBips,
    uint256 initialReserveRatioBips
  )
    internal
  {
    uint256 previousAnnualInterestBips = state.annualInterestBips;
    uint256 previousReserveRatioBips = state.reserveRatioBips;
    if (_annualInterestBips > BIP) {
      revertWithSelector(AnnualInterestBipsTooHigh_ErrorSelector);
    }

    if (_reserveRatioBips > BIP) {
      revertWithSelector(ReserveRatioBipsTooHigh_ErrorSelector);
    }
    if (_isInRepayment() && _reserveRatioBips != BIP) revertWithSelector(RepaymentReserveRequired_ErrorSelector);

    uint256 currentTotalAssets = totalAssets();
    if (_reserveRatioBips <= initialReserveRatioBips) {
      if (state.liquidityRequired() > currentTotalAssets) {
        revertWithSelector(InsufficientReservesForOldLiquidityRatio_ErrorSelector);
      }
    }
    state.reserveRatioBips = _reserveRatioBips;
    state.annualInterestBips = _annualInterestBips;
    if (_reserveRatioBips > initialReserveRatioBips) {
      if (state.liquidityRequired() > currentTotalAssets) {
        revertWithSelector(InsufficientReservesForNewLiquidityRatio_ErrorSelector);
      }
    }

    _writeState(state, currentTotalAssets);
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      msg.sender, previousAnnualInterestBips, _annualInterestBips, previousReserveRatioBips, _reserveRatioBips
    );
  }

  // ┌─ annualInterestBips ─────
  /// @notice return the stored base annual lender rate, in bips.
  function annualInterestBips() external view returns (uint256) {
    return _state.annualInterestBips;
  }

  // ┌─ reserveRatioBips ─────
  /// @notice return the stored reserve requirement on outstanding supply, in bips.
  function reserveRatioBips() external view returns (uint256) {
    return _state.reserveRatioBips;
  }

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  // ┌─ setProtocolFeeBips ─────
  /// @notice update the protocol share of base interest from the deploying factory.
  ///
  /// @dev capped at 1,000 bips. a positive fee needs a nonzero immutable recipient, and the hook
  ///      may reject the update. closed markets can't change fees.
  ///
  /// @param _protocolFeeBips new protocol share of base interest, in bips.
  function setProtocolFeeBips(uint16 _protocolFeeBips) external nonReentrant sphereXGuardExternal {
    if (msg.sender != factory) revertWithSelector(NotFactory_ErrorSelector);
    if (_protocolFeeBips > 1_000) revertWithSelector(ProtocolFeeTooHigh_ErrorSelector);
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revertWithSelector(ProtocolFeeChangeOnClosedMarket_ErrorSelector);
    if (_protocolFeeBips > 0 && feeRecipient == address(0)) {
      revertWithSelector(ProtocolFeeRecipientRequired_ErrorSelector);
    }
    if (_protocolFeeBips != state.protocolFeeBips) {
      uint256 previousProtocolFeeBips = state.protocolFeeBips;
      hooks.onSetProtocolFeeBips(_protocolFeeBips, state);
      state.protocolFeeBips = _protocolFeeBips;
      emit_ProtocolFeeBipsUpdated(msg.sender, previousProtocolFeeBips, _protocolFeeBips);
    }
    _writeState(state);
  }

  // ░░▒▒▓▓██ [ WRAPPER REGISTRATION ] ─────────────────────────────────────────

  // ┌─ registerWrapper ─────
  /// @notice store the canonical ERC-4626 wrapper supplied by `wrapperFactory`.
  ///
  /// @dev normally called during wrapper deployment. a nonzero stored wrapper blocks replacement.
  ///
  /// @param wrapper canonical wrapper address to store.
  function registerWrapper(address wrapper) external {
    if (msg.sender != wrapperFactory) revertWithSelector(NotWrapperFactory_ErrorSelector);
    if (registeredWrapper() != address(0)) revertWithSelector(WrapperAlreadyRegistered_ErrorSelector);
    _setAddress(REGISTERED_WRAPPER_STORAGE_SLOT, wrapper);
    emit WrapperRegistered(wrapper);
  }

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  // ******************************************************************
  //          *  |\**/|  *          *                                *
  //          *  \ == /  *          *                                *
  //          *   | b|   *          *                                *
  //          *   | y|   *          *                                *
  //          *   \ e/   *          *                                *
  //          *    \/    *          *                                *
  //          *          *          *                                *
  //          *          *          *                                *
  //          *          *  |\**/|  *                                *
  //          *          *  \ == /  *         _.-^^---....,,--       *
  //          *          *   | b|   *    _--                  --_    *
  //          *          *   | y|   *   <                        >)  *
  //          *          *   \ e/   *   |         O-FAC!          |  *
  //          *          *    \/    *    \._                   _./   *
  //          *          *          *       ```--. . , ; .--'''      *
  //          *          *          *   💸        | |   |            *
  //          *          *          *          .-=||  | |=-.    💸   *
  //  💰🤑💰  *    😅    *    😐    *    💸    `-=#$%&%$#=-'         *
  //   \|/    *   /|\    *   /|\    *  🌪         | ;  :|    🌪      *
  //   /\     * 💰/\ 💰  * 💰/\ 💰  *    _____.,-#%&$@%#&#~,._____   *
  // ******************************************************************
  // ┌─ nukeFromOrbit ─────
  /// @notice quarantine a sanctioned lender by queueing its full direct balance for withdrawal.
  ///
  /// @dev permissionless. before an enabled repayment date, the target must pass the normal
  ///      queue-withdrawal hook, so term policy can defer quarantine until withdrawals open.
  ///      from that date, queueing bypasses the hook. the canonical wrapper is excluded.
  ///
  /// @param accountAddress sanctioned lender to quarantine.
  function nukeFromOrbit(address accountAddress) external nonReentrant sphereXGuardExternal {
    if (accountAddress != address(0) && accountAddress == registeredWrapper()) {
      revertWithSelector(CannotNukeWrapper_ErrorSelector);
    }
    if (!_isSanctioned(accountAddress)) revertWithSelector(BadLaunchCode_ErrorSelector);
    MarketState memory state = _getUpdatedState();
    hooks.onNukeFromOrbit(accountAddress, state);
    _blockAccount(state, accountAddress);
    _writeState(state);
  }

  // ░░▒▒▓▓██ [ STATUS ] ───────────────────────────────────────────────────────

  // ┌─ isClosed ─────
  /// @notice return whether the market has been permanently closed.
  function isClosed() external view returns (bool) {
    // scheduled completion can close the market between writes. no hook call is needed here.
    return _state.isClosed || (_isInRepayment() && _calculateCurrentStatePointers.asReturnsMarketState()().isClosed);
  }
}

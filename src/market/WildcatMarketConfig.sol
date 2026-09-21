// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './WildcatMarketBase.sol';
import '../libraries/SafeCastLib.sol';

/// @dev narrow callback used to execute a pending periodic-term APR reduction.
interface IPeriodicTermAprReductionHooks {
  /// @dev validates the pending proposal against `intermediateState` and consumes it.
  /// @param intermediateState market state after current accrual and batch processing.
  /// @return annualInterestBips exact reduced APR the market should apply, in bips.
  function executePendingAnnualInterestBipsReduction(
    MarketState calldata intermediateState
  ) external returns (uint16 annualInterestBips);
}

/// @notice market configuration, sanctions quarantine, and term-change entry points.
contract WildcatMarketConfig is WildcatMarketBase {
  using SafeCastLib for uint256;
  using FunctionTypeCasts for *;

  // ===================================================================== //
  //                      External Config Getters                          //
  // ===================================================================== //

  /// @notice returns whether the market has been permanently closed.
  function isClosed() external view returns (bool) {
    // Use stored state because the state update can not affect whether
    // the market is closed.
    return _state.isClosed;
  }

  /// @notice returns the most underlying assets a deposit can currently add.
  /// @dev includes interest accrued through this block and saturates at zero.
  function maximumDeposit() external view returns (uint256) {
    MarketState memory state = _calculateCurrentStatePointers.asReturnsMarketState()();
    return state.maximumDeposit();
  }

  /// @notice returns the normalized supply cap applied to deposits.
  /// @dev interest can grow total supply above this value.
  function maxTotalSupply() external view returns (uint256) {
    return _state.maxTotalSupply;
  }

  /// @notice returns the stored base annual lender rate, in bips.
  function annualInterestBips() external view returns (uint256) {
    return _state.annualInterestBips;
  }

  /// @notice returns the stored reserve requirement on outstanding supply, in bips.
  function reserveRatioBips() external view returns (uint256) {
    return _state.reserveRatioBips;
  }

  // ========================================================================== //
  //                                  Sanctions                                 //
  // ========================================================================== //

  /// @notice stores the canonical ERC-4626 wrapper supplied by `wrapperFactory`.
  /// @dev normally called during wrapper deployment. a nonzero stored wrapper blocks replacement.
  /// @param wrapper canonical wrapper address to store.
  function registerWrapper(address wrapper) external {
    if (msg.sender != wrapperFactory) revert_NotWrapperFactory();
    if (registeredWrapper() != address(0)) revert_WrapperAlreadyRegistered();
    _setAddress(REGISTERED_WRAPPER_STORAGE_SLOT, wrapper);
    emit WrapperRegistered(wrapper);
  }

  /// @notice quarantines a sanctioned lender by queueing its full direct balance for withdrawal.
  /// @dev permissionless. the target must still pass the normal queue-withdrawal hook, so a term
  ///      policy can defer quarantine until withdrawals open. the canonical wrapper is excluded.
  /// @param accountAddress sanctioned lender to quarantine.
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
  function nukeFromOrbit(address accountAddress) external nonReentrant sphereXGuardExternal {
    if (accountAddress != address(0) && accountAddress == registeredWrapper()) {
      revert_CannotNukeWrapper();
    }
    if (!_isSanctioned(accountAddress)) revert_BadLaunchCode();
    MarketState memory state = _getUpdatedState();
    hooks.onNukeFromOrbit(accountAddress, state);
    _blockAccount(state, accountAddress);
    _writeState(state);
  }

  // ========================================================================== //
  //                           External Config Setters                          //
  // ========================================================================== //

  /// @notice sets the normalized supply cap for future deposits.
  /// @dev only the borrower can call. the hook may accept or revert but can't rewrite the value.
  ///      this does not cap interest growth or force existing supply down.
  /// @param _maxTotalSupply new normalized deposit cap.
  function setMaxTotalSupply(
    uint256 _maxTotalSupply
  ) external onlyBorrower nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_CapacityChangeOnClosedMarket();

    hooks.onSetMaxTotalSupply(_maxTotalSupply, state);
    uint256 previousMaxTotalSupply = state.maxTotalSupply;
    state.maxTotalSupply = _maxTotalSupply.toUint128();
    _writeState(state);
    emit_MaxTotalSupplyUpdated(msg.sender, previousMaxTotalSupply, _maxTotalSupply);
  }

  /// @dev when the ratio stays flat or falls, the market must be healthy under the current ratio.
  ///      when it rises, the market must remain healthy under the new ratio.
  function _applyAnnualInterestAndReserveRatioBips(
    MarketState memory state,
    uint16 _annualInterestBips,
    uint16 _reserveRatioBips,
    uint256 initialReserveRatioBips
  ) internal {
    uint256 previousAnnualInterestBips = state.annualInterestBips;
    uint256 previousReserveRatioBips = state.reserveRatioBips;
    if (_annualInterestBips > BIP) {
      revert_AnnualInterestBipsTooHigh();
    }

    if (_reserveRatioBips > BIP) {
      revert_ReserveRatioBipsTooHigh();
    }

    uint256 currentTotalAssets = totalAssets();
    if (_reserveRatioBips <= initialReserveRatioBips) {
      if (state.liquidityRequired() > currentTotalAssets) {
        revert_InsufficientReservesForOldLiquidityRatio();
      }
    }
    state.reserveRatioBips = _reserveRatioBips;
    state.annualInterestBips = _annualInterestBips;
    if (_reserveRatioBips > initialReserveRatioBips) {
      if (state.liquidityRequired() > currentTotalAssets) {
        revert_InsufficientReservesForNewLiquidityRatio();
      }
    }

    _writeState(state, currentTotalAssets);
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      msg.sender,
      previousAnnualInterestBips,
      _annualInterestBips,
      previousReserveRatioBips,
      _reserveRatioBips
    );
  }

  /// @notice asks the market hook to apply new lender APR and reserve-ratio values.
  /// @dev only the borrower can call. the hook may rewrite both values and each result must stay at
  ///      or below 10,000 bips. a flat or lower reserve ratio requires the market to be healthy
  ///      already; a higher ratio must leave it healthy.
  /// @param _annualInterestBips proposed base annual lender rate, in bips.
  /// @param _reserveRatioBips proposed reserve requirement, in bips.
  function setAnnualInterestAndReserveRatioBips(
    uint16 _annualInterestBips,
    uint16 _reserveRatioBips
  ) external onlyBorrower nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_AprChangeOnClosedMarket();

    uint256 initialReserveRatioBips = state.reserveRatioBips;

    (_annualInterestBips, _reserveRatioBips) = hooks.onSetAnnualInterestAndReserveRatioBips(
      _annualInterestBips,
      _reserveRatioBips,
      state
    );

    _applyAnnualInterestAndReserveRatioBips(
      state,
      _annualInterestBips,
      _reserveRatioBips,
      initialReserveRatioBips
    );
  }

  /// @notice permissionlessly applies an executable periodic-term APR reduction.
  /// @dev the hook supplies the APR. the caller can't choose it or change the reserve ratio. the
  ///      hook enforces proposal timing and withdrawal conditions; non-periodic markets revert.
  function executePendingAnnualInterestBipsReduction() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_AprChangeOnClosedMarket();
    if (!hooks.useOnExecutePendingAnnualInterestBipsReduction()) {
      revert_ExecutePendingAprReductionNotEnabled();
    }

    uint16 currentAnnualInterestBips = state.annualInterestBips;
    uint16 _annualInterestBips = IPeriodicTermAprReductionHooks(hooks.hooksAddress())
      .executePendingAnnualInterestBipsReduction(state);

    if (_annualInterestBips >= currentAnnualInterestBips) {
      revert_AprReductionNotReduction();
    }

    uint16 currentReserveRatioBips = state.reserveRatioBips;
    _applyAnnualInterestAndReserveRatioBips(
      state,
      _annualInterestBips,
      currentReserveRatioBips,
      currentReserveRatioBips
    );
  }

  /// @notice updates the protocol share of base interest from the deploying factory.
  /// @dev capped at 1,000 bips. a positive fee needs a nonzero immutable recipient, and the hook
  ///      may reject the update. closed markets can't change fees.
  /// @param _protocolFeeBips new protocol share of base interest, in bips.
  function setProtocolFeeBips(uint16 _protocolFeeBips) external nonReentrant sphereXGuardExternal {
    if (msg.sender != factory) revert_NotFactory();
    if (_protocolFeeBips > 1_000) revert_ProtocolFeeTooHigh();
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_ProtocolFeeChangeOnClosedMarket();
    if (_protocolFeeBips > 0 && feeRecipient == address(0)) {
      revert_ProtocolFeeRecipientRequired();
    }
    if (_protocolFeeBips != state.protocolFeeBips) {
      uint256 previousProtocolFeeBips = state.protocolFeeBips;
      hooks.onSetProtocolFeeBips(_protocolFeeBips, state);
      state.protocolFeeBips = _protocolFeeBips;
      emit_ProtocolFeeBipsUpdated(msg.sender, previousProtocolFeeBips, _protocolFeeBips);
    }
    _writeState(state);
  }
}

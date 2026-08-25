// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './WildcatMarketBase.sol';
import '../libraries/SafeCastLib.sol';

interface IPeriodicTermAprReductionHooks {
  function executePendingAnnualInterestBipsReduction(
    MarketState calldata intermediateState
  ) external returns (uint16 annualInterestBips);
}

contract WildcatMarketConfig is WildcatMarketBase {
  using SafeCastLib for uint256;
  using FunctionTypeCasts for *;

  // ===================================================================== //
  //                      External Config Getters                          //
  // ===================================================================== //

  /**
   * @dev Returns whether or not a market has been closed.
   */
  function isClosed() external view returns (bool) {
    // Use stored state because the state update can not affect whether
    // the market is closed.
    return _state.isClosed;
  }

  /**
   * @dev Returns the maximum amount of underlying asset that can
   *      currently be deposited to the market.
   */
  function maximumDeposit() external view returns (uint256) {
    MarketState memory state = _calculateCurrentStatePointers.asReturnsMarketState()();
    return state.maximumDeposit();
  }

  /**
   * @dev Returns the maximum supply the market can reach via
   *      deposits (does not apply to interest accrual).
   */
  function maxTotalSupply() external view returns (uint256) {
    return _state.maxTotalSupply;
  }

  /**
   * @dev Returns the annual interest rate earned by lenders
   *      in bips.
   */
  function annualInterestBips() external view returns (uint256) {
    return _state.annualInterestBips;
  }

  function reserveRatioBips() external view returns (uint256) {
    return _state.reserveRatioBips;
  }

  // ========================================================================== //
  //                                  Sanctions                                 //
  // ========================================================================== //

  /// @dev Register the optional canonical ERC-4626 wrapper. The wrapper factory
  ///      calls this atomically during permissionless wrapper deployment.
  function registerWrapper(address wrapper) external {
    if (msg.sender != wrapperFactory) revert_NotWrapperFactory();
    if (registeredWrapper() != address(0)) revert_WrapperAlreadyRegistered();
    _setAddress(REGISTERED_WRAPPER_STORAGE_SLOT, wrapper);
    emit WrapperRegistered(wrapper);
  }

  /// @dev Block a sanctioned account from interacting with the market
  ///      and transfer its balance to an escrow contract.
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

  /**
   * @dev Sets the maximum total supply - this only limits deposits and
   *      does not affect interest accrual.
   *
   *      The hooks contract may block the change but can not modify the
   *      value being set.
   */
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

  /**
   * @dev Sets the annual interest rate earned by lenders in bips.
   *
   *      If the new reserve ratio is lower than the old ratio,
   *      asserts that the market is not currently delinquent.
   *
   *      If the new reserve ratio is higher than the old ratio,
   *      asserts that the market will not become delinquent
   *      because of the change.
   */
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

  /**
   * @dev Permissionlessly applies an already-proposed periodic-term APR reduction.
   *
   *      This does not let the caller choose a new APR or reserve ratio. The
   *      borrower must have proposed the reduction through PeriodicTermHooks,
   *      the response withdrawal window must have elapsed, the proposal must not
   *      have expired, and all outstanding withdrawal obligations must be paid.
   *      Non-periodic markets revert because their hooks config does not enable
   *      the periodic-term execution hook.
   */
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

  /**
   * @dev Updates protocol fee bips from the factory.
   *      Reverts if caller is not factory, fee is above 1,000 bips, market is closed,
   *      or the hooks contract rejects the change.
   */
  function setProtocolFeeBips(uint16 _protocolFeeBips) external nonReentrant sphereXGuardExternal {
    if (msg.sender != factory) revert_NotFactory();
    if (_protocolFeeBips > 1_000) revert_ProtocolFeeTooHigh();
    MarketState memory state = _getUpdatedState();
    if (state.isClosed) revert_ProtocolFeeChangeOnClosedMarket();
    if (_protocolFeeBips != state.protocolFeeBips) {
      uint256 previousProtocolFeeBips = state.protocolFeeBips;
      hooks.onSetProtocolFeeBips(_protocolFeeBips, state);
      state.protocolFeeBips = _protocolFeeBips;
      emit_ProtocolFeeBipsUpdated(msg.sender, previousProtocolFeeBips, _protocolFeeBips);
    }
    _writeState(state);
  }
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import { FixedTermHooks, HookedMarket as FixedTermHookedMarket } from './FixedTermHooks.sol';
import './IWrapperAwareSingletonMarket.sol';
import './ProviderStructs.sol';
import '../interfaces/WildcatStructsAndEnums.sol';
import '../providers/ISingletonRoleProvider.sol';
import '../providers/ISingletonRoleProviderFactory.sol';
import '../providers/SingletonRoleProviderFactory.sol';
import '../types/HooksConfig.sol';

/// @notice Constructor input for fixed-term hooks with immutable lender admission.
struct SingletonFixedTermHooksInputs {
  NameAndProviderInputs accessControlInputs;
  address lender;
}

/// @notice Fixed-term access hooks with one factory-bound immutable direct market lender.
/// @dev The template fixes the lender set, blocks pre-maturity closure and term reduction, and
///      prevents APR or reserve-ratio changes before the fixed term ends.
contract SingletonFixedTermHooks is FixedTermHooks {
  error InvalidSingletonProviderInputs();
  error DepositAccessRequired();
  error TransferHookRequired();
  error InvalidMarketHooksData();
  error ClosureBeforeTermNotAllowed();
  error TermReductionNotAllowed();
  error RateOrReserveRatioChangeBeforeTermEnd();
  error UnexpectedSingletonProvider();
  error UnexpectedSingletonLender();

  constructor(
    address administrator,
    bytes memory args
  ) FixedTermHooks(administrator, _accessControlArgs(args)) {
    SingletonFixedTermHooksInputs memory inputs = abi.decode(args, (SingletonFixedTermHooksInputs));
    address provider = _pullProviders[0].providerAddress();
    address expectedProvider = _validateSingletonInputs(inputs);
    if (provider != expectedProvider) revert UnexpectedSingletonProvider();
    if (ISingletonRoleProvider(provider).lender() != inputs.lender)
      revert UnexpectedSingletonLender();
    _sealRoleProviderConfiguration();
  }

  function version() external pure override returns (string memory) {
    return 'SingletonFixedTermHooks';
  }

  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    if (!parameters.hooks.useOnDeposit()) revert DepositAccessRequired();
    if (!parameters.hooks.useOnTransfer()) revert TransferHookRequired();
    if (hooksData.length != 160) revert InvalidMarketHooksData();

    (, , , bool allowClosureBeforeTerm, bool allowTermReduction) = abi.decode(
      hooksData,
      (uint32, uint128, bool, bool, bool)
    );
    if (allowClosureBeforeTerm) revert ClosureBeforeTermNotAllowed();
    if (allowTermReduction) revert TermReductionNotAllowed();

    return super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
  }

  /// @dev The canonical wrapper is authenticated by the market: only its immutable wrapper factory
  ///      can register it, and registration is one-time. Every other recipient follows the
  ///      singleton credential check in FixedTermHooks.
  function _isTransferRecipientExempt(
    address market,
    address recipient
  ) internal view override returns (bool) {
    address wrapper = IWrapperAwareSingletonMarket(market).registeredWrapper();
    return wrapper != address(0) && recipient == wrapper;
  }

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata hooksData
  )
    public
    override
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips)
  {
    FixedTermHookedMarket storage market = _hookedMarkets[msg.sender];
    if (
      market.fixedTermEndTime > block.timestamp &&
      (
        annualInterestBips != intermediateState.annualInterestBips ||
        reserveRatioBips != intermediateState.reserveRatioBips
      )
    ) {
      revert RateOrReserveRatioChangeBeforeTermEnd();
    }
    return
      super.onSetAnnualInterestAndReserveRatioBips(
        annualInterestBips,
        reserveRatioBips,
        intermediateState,
        hooksData
      );
  }

  function _accessControlArgs(bytes memory args) private pure returns (bytes memory) {
    SingletonFixedTermHooksInputs memory inputs = abi.decode(args, (SingletonFixedTermHooksInputs));
    return abi.encode(inputs.accessControlInputs);
  }

  function _validateSingletonInputs(
    SingletonFixedTermHooksInputs memory inputs
  ) private view returns (address expectedProvider) {
    NameAndProviderInputs memory accessControlInputs = inputs.accessControlInputs;
    if (
      inputs.lender == address(0) ||
      accessControlInputs.roleProviderFactory.codehash !=
      keccak256(type(SingletonRoleProviderFactory).runtimeCode) ||
      accessControlInputs.newProviderInputs.length != 1 ||
      accessControlInputs.existingProviders.length != 0 ||
      accessControlInputs.newProviderInputs[0].timeToLive != 0
    ) revert InvalidSingletonProviderInputs();

    SingletonRoleProviderFactoryInputs memory providerInputs = abi.decode(
      accessControlInputs.newProviderInputs[0].providerFactoryCalldata,
      (SingletonRoleProviderFactoryInputs)
    );
    if (providerInputs.lender != inputs.lender) revert UnexpectedSingletonLender();
    expectedProvider = ISingletonRoleProviderFactory(accessControlInputs.roleProviderFactory)
      .computeRoleProviderAddress(address(this), providerInputs);
  }
}

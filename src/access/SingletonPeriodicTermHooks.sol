// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import { PeriodicTermHooks } from './PeriodicTermHooks.sol';
import './IWrapperAwareSingletonMarket.sol';
import './ProviderStructs.sol';
import '../interfaces/WildcatStructsAndEnums.sol';
import '../providers/ISingletonRoleProvider.sol';
import '../providers/ISingletonRoleProviderFactory.sol';
import '../providers/SingletonRoleProviderFactory.sol';
import '../types/HooksConfig.sol';

/// @notice Constructor input for periodic-term hooks with immutable lender admission.
struct SingletonPeriodicTermHooksInputs {
  NameAndProviderInputs accessControlInputs;
  address lender;
}

/// @notice Periodic-term access hooks with one factory-bound immutable direct market lender.
contract SingletonPeriodicTermHooks is PeriodicTermHooks {
  error InvalidSingletonProviderInputs();
  error DepositAccessRequired();
  error TransferHookRequired();
  error InvalidMarketHooksData();
  error UnexpectedSingletonProvider();
  error UnexpectedSingletonLender();

  constructor(
    address administrator,
    bytes memory args
  ) PeriodicTermHooks(administrator, _accessControlArgs(args)) {
    SingletonPeriodicTermHooksInputs memory inputs = abi.decode(
      args,
      (SingletonPeriodicTermHooksInputs)
    );
    address provider = _pullProviders[0].providerAddress();
    address expectedProvider = _validateSingletonInputs(inputs);
    if (provider != expectedProvider) revert UnexpectedSingletonProvider();
    if (ISingletonRoleProvider(provider).lender() != inputs.lender)
      revert UnexpectedSingletonLender();
    _sealRoleProviderConfiguration();
  }

  function version() external pure override returns (string memory) {
    return 'SingletonPeriodicTermHooks';
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
    abi.decode(hooksData, (uint32, uint32, uint32, uint128, bool));
    return super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
  }

  /// @dev The canonical wrapper is authenticated by the market: only its immutable wrapper factory
  ///      can register it, and registration is one-time. Every other recipient follows the
  ///      singleton credential check in PeriodicTermHooks.
  function _isTransferRecipientExempt(
    address market,
    address recipient
  ) internal view override returns (bool) {
    address wrapper = IWrapperAwareSingletonMarket(market).registeredWrapper();
    return wrapper != address(0) && recipient == wrapper;
  }

  function _accessControlArgs(bytes memory args) private pure returns (bytes memory) {
    SingletonPeriodicTermHooksInputs memory inputs = abi.decode(
      args,
      (SingletonPeriodicTermHooksInputs)
    );
    return abi.encode(inputs.accessControlInputs);
  }

  function _validateSingletonInputs(
    SingletonPeriodicTermHooksInputs memory inputs
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

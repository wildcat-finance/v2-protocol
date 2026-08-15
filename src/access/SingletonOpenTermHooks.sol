// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './OpenTermHooks.sol';
import './ProviderStructs.sol';
import './IWrapperAwareSingletonMarket.sol';
import '../interfaces/WildcatStructsAndEnums.sol';
import '../providers/ISingletonRoleProvider.sol';
import '../providers/ISingletonRoleProviderFactory.sol';
import '../providers/SingletonRoleProviderFactory.sol';
import '../types/HooksConfig.sol';

/// @notice Constructor input for an OpenTerm hook with immutable lender admission.
struct SingletonOpenTermHooksInputs {
  NameAndProviderInputs accessControlInputs;
  address lender;
}

/// @notice Open-term access hooks with one factory-bound immutable direct market lender.
/// @dev Deploy the template with the canonical singleton-provider factory, then register that
///      template with HooksFactory. HooksFactory.deployMarketAndHooks appends the administrator
///      and `args`, so the borrower remains the hook administrator and market borrower.
contract SingletonOpenTermHooks is OpenTermHooks {
  error InvalidSingletonProviderInputs();
  error DepositAccessRequired();
  error TransferHookRequired();
  error InvalidMarketHooksData();
  error UnexpectedSingletonProvider();
  error UnexpectedSingletonLender();

  constructor(
    address administrator,
    bytes memory args
  ) OpenTermHooks(administrator, _accessControlArgs(args)) {
    SingletonOpenTermHooksInputs memory inputs = abi.decode(args, (SingletonOpenTermHooksInputs));
    address provider = _pullProviders[0].providerAddress();
    address expectedProvider = _validateSingletonInputs(inputs);
    if (provider != expectedProvider) revert UnexpectedSingletonProvider();
    if (ISingletonRoleProvider(provider).lender() != inputs.lender)
      revert UnexpectedSingletonLender();
    _sealRoleProviderConfiguration();
  }

  function version() external pure virtual override returns (string memory) {
    return 'SingletonOpenTermHooks';
  }

  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    if (!parameters.hooks.useOnDeposit()) revert DepositAccessRequired();
    if (!parameters.hooks.useOnTransfer()) revert TransferHookRequired();
    if (hooksData.length != 64) revert InvalidMarketHooksData();
    // Preserve strict ABI validation without requiring either value of the
    // transfersDisabled flag.
    abi.decode(hooksData, (uint128, bool));
    return super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
  }

  /// @dev The canonical wrapper is authenticated by the market: only its
  ///      immutable wrapper factory can register it, and registration is
  ///      one-time. Every other recipient follows the singleton credential
  ///      check in OpenTermHooks. Wrapper-share ownership is outside the
  ///      market-token admission policy enforced here.
  function _isTransferRecipientExempt(
    address market,
    address recipient
  ) internal view override returns (bool) {
    address wrapper = IWrapperAwareSingletonMarket(market).registeredWrapper();
    return wrapper != address(0) && recipient == wrapper;
  }

  function _accessControlArgs(bytes memory args) private pure returns (bytes memory) {
    SingletonOpenTermHooksInputs memory inputs = abi.decode(args, (SingletonOpenTermHooksInputs));
    return abi.encode(inputs.accessControlInputs);
  }

  function _validateSingletonInputs(
    SingletonOpenTermHooksInputs memory inputs
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

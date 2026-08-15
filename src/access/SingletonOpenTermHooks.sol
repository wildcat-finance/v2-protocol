// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './OpenTermHooks.sol';
import './ProviderStructs.sol';
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

/// @notice Open-term access hooks with one factory-bound immutable lender provider.
/// @dev Deploy the template with the canonical singleton-provider factory, then register that
///      template with HooksFactory. HooksFactory.deployMarketAndHooks appends the administrator
///      and `args`, so the borrower remains the hook administrator and market borrower.
contract SingletonOpenTermHooks is OpenTermHooks {
  error InvalidSingletonProviderInputs();
  error DepositAccessRequired();
  error TransferHookRequired();
  error InvalidMarketHooksData();
  error MarketTokenTransfersMustBeDisabled();
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
    if (ISingletonRoleProvider(provider).lender() != inputs.lender) revert UnexpectedSingletonLender();
    _sealRoleProviderConfiguration();
  }

  function version() external pure override returns (string memory) {
    return 'SingletonOpenTermHooks';
  }

  function _onCreateMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    if (!parameters.hooks.useOnDeposit()) revert DepositAccessRequired();
    if (!parameters.hooks.useOnTransfer()) revert TransferHookRequired();
    if (hooksData.length != 64) revert InvalidMarketHooksData();
    (, bool transfersDisabled) = abi.decode(hooksData, (uint128, bool));
    if (!transfersDisabled) revert MarketTokenTransfersMustBeDisabled();
    return super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
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
      accessControlInputs.roleProviderFactory.codehash != keccak256(type(SingletonRoleProviderFactory).runtimeCode) ||
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

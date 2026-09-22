// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './BaseAccessControls.sol';
import './MarketConstraintHooks.sol';
import './IMarketTransferPolicy.sol';

/// @dev memory view of the template's packed config. keep the stored config in the template.
struct AccessConfig {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

/// @title BaseHooks
/// @notice shared initialization and market access configuration for hook templates.
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
}

// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HooksFactory
//  \ ^ /   Hooks lifecycle and deterministic standard-market deployment.
//    V
//
//  SETUP
//  constructor(...)
//  name()
//
//  MARKET DEPLOYMENT
//  deployMarket(...)
//  deployMarketAndHooks(...)
// ═════

import './HooksFactoryBase.sol';

// ┌─ HooksFactory ─────────────────────────────────────────────────────────────
/// @title Wildcat hooks factory
///
/// @notice manage hooks templates and instances, then deploy standard Wildcat markets with them.
///
/// @dev templates, instances, and the shared deployment path live in `HooksFactoryBase`.
contract HooksFactory is HooksFactoryBase, IHooksFactory {
  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(
    address archController_,
    address _sanctionsSentinel,
    address _wrapperFactory,
    address _marketInitCodeStorage,
    uint256 _marketInitCodeHash,
    address _borrowerIdentityRegistry
  )
    HooksFactoryBase(
      archController_,
      _sanctionsSentinel,
      _wrapperFactory,
      _marketInitCodeStorage,
      _marketInitCodeHash,
      _borrowerIdentityRegistry
    )
  { }

  // ┌─ name ─────
  /// @notice return the stable factory name `WildcatHooksFactory`.
  function name() external pure override returns (string memory) {
    return 'WildcatHooksFactory';
  }

  // ░░▒▒▓▓██ [ MARKET DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ deployMarket ─────
  /// @inheritdoc IHooksFactory
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  )
    external
    override
    nonReentrant
    returns (address market)
  {
    address borrowerPrincipal = _resolveBorrowerPrincipal(msg.sender);
    address hooksInstance = parameters.hooks.hooksAddress();
    address hooksTemplate = getHooksTemplateForInstance[hooksInstance];
    if (hooksTemplate == address(0)) {
      revert HooksInstanceNotFound();
    }
    DeployMarketRuntimeParameters memory runtimeParams = DeployMarketRuntimeParameters({
      borrowerPrincipal: borrowerPrincipal,
      hooksTemplate: hooksTemplate,
      requestedHooks: parameters.hooks,
      salt: salt,
      originationFeeAsset: originationFeeAsset,
      originationFeeAmount: originationFeeAmount,
      commitmentFeeBips: 0
    });
    market = _deployMarket(parameters, hooksData, runtimeParams);
  }

  // ┌─ deployMarketAndHooks ─────
  /// @inheritdoc IHooksFactory
  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksTemplateArgs,
    DeployMarketInputs memory parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  )
    external
    override
    nonReentrant
    returns (address market, address hooksInstance)
  {
    address borrowerPrincipal = _resolveBorrowerPrincipal(msg.sender);
    // `_deployHooksInstance` reverts with `HooksTemplateNotFound` first for an unknown template.
    hooksInstance = _deployHooksInstance(borrowerPrincipal, hooksTemplate, hooksTemplateArgs);
    parameters.hooks = parameters.hooks.setHooksAddress(hooksInstance);
    DeployMarketRuntimeParameters memory runtimeParams = DeployMarketRuntimeParameters({
      borrowerPrincipal: borrowerPrincipal,
      hooksTemplate: hooksTemplate,
      requestedHooks: parameters.hooks,
      salt: salt,
      originationFeeAsset: originationFeeAsset,
      originationFeeAmount: originationFeeAmount,
      commitmentFeeBips: 0
    });
    market = _deployMarket(parameters, hooksData, runtimeParams);
  }
}

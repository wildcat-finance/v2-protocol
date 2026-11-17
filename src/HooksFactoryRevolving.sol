// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HooksFactoryRevolving
//  \ ^ /   Hooks lifecycle and deterministic revolving-market deployment.
//    V
//
//  SETUP
//  constructor(...)
//  name()
//
//  MARKET DEPLOYMENT
//  deployMarket(...)
//  deployMarketAndHooks(...)
//  _decodeMarketData(...)
//
//  MARKET DATA
//  getRevolvingMarketCommitmentFeeBips()
//  _storeMarketData(...)
//  _clearMarketData()
//  _emitMarketData(...)
// ═════

import './HooksFactoryBase.sol';
import './IHooksFactoryRevolving.sol';

// ┌─ HooksFactoryRevolving ────────────────────────────────────────────────────
/// @title Wildcat revolving hooks factory
///
/// @notice mirrors `HooksFactory`, with an extra fixed commitment fee passed to revolving markets.
///
/// @dev factory-owned `marketData` is versioned separately from hook-owned `hooksData`.
///      constructors read both ordinary and revolving parameters from transient storage.
contract HooksFactoryRevolving is HooksFactoryBase, IHooksFactoryRevolving {
  // ░░▒▒▓▓██ [ DEPLOYMENT CONSTANTS ] ─────────────────────────────────────────

  TransientBytesArray internal constant _tmpRevolvingMarketData =
    TransientBytesArray.wrap(uint256(keccak256('Transient:TmpRevolvingMarketData')) - 1);

  /// @dev length of `abi.encode(uint8 version, uint16 commitmentFeeBips)`.
  uint256 internal constant _MARKET_DATA_LENGTH = 0x40;

  uint8 internal constant _MARKET_DATA_VERSION = 1;

  uint16 internal constant _MAX_COMMITMENT_FEE_BIPS = 10_000;

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
  /// @notice return the stable factory name `WildcatHooksFactoryRevolving`.
  function name() external pure override returns (string memory) {
    return 'WildcatHooksFactoryRevolving';
  }

  // ░░▒▒▓▓██ [ MARKET DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ deployMarket ─────
  /// @inheritdoc IHooksFactoryRevolving
  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
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
    uint16 commitmentFeeBips = _decodeMarketData(marketData);
    address hooksTemplate = getHooksTemplateForInstance[parameters.hooks.hooksAddress()];
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
      commitmentFeeBips: commitmentFeeBips
    });
    market = _deployMarket(parameters, hooksData, runtimeParams);
  }

  // ┌─ deployMarketAndHooks ─────
  /// @inheritdoc IHooksFactoryRevolving
  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksConstructorArgs,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes calldata marketData,
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
    uint16 commitmentFeeBips = _decodeMarketData(marketData);
    // `_deployHooksInstance` reverts if the template does not exist or is disabled.
    hooksInstance = _deployHooksInstance(borrowerPrincipal, hooksTemplate, hooksConstructorArgs);
    DeployMarketInputs memory marketInputs = parameters;
    marketInputs.hooks = marketInputs.hooks.setHooksAddress(hooksInstance);
    DeployMarketRuntimeParameters memory runtimeParams = DeployMarketRuntimeParameters({
      borrowerPrincipal: borrowerPrincipal,
      hooksTemplate: hooksTemplate,
      requestedHooks: marketInputs.hooks,
      salt: salt,
      originationFeeAsset: originationFeeAsset,
      originationFeeAmount: originationFeeAmount,
      commitmentFeeBips: commitmentFeeBips
    });
    market = _deployMarket(marketInputs, hooksData, runtimeParams);
  }

  // ┌─ _decodeMarketData ─────
  /// @dev decode factory-owned `marketData`: `abi.encode(uint8 version, uint16 commitmentFeeBips)`.
  function _decodeMarketData(bytes calldata marketData) internal pure returns (uint16 commitmentFeeBips) {
    if (marketData.length != _MARKET_DATA_LENGTH) {
      revert InvalidMarketData();
    }

    (uint8 version, uint16 decodedCommitmentFeeBips) = abi.decode(marketData, (uint8, uint16));
    if (version != _MARKET_DATA_VERSION) {
      revert UnsupportedMarketDataVersion();
    }
    if (decodedCommitmentFeeBips > _MAX_COMMITMENT_FEE_BIPS) {
      revert InvalidCommitmentFeeBips();
    }
    commitmentFeeBips = decodedCommitmentFeeBips;
  }

  // ░░▒▒▓▓██ [ MARKET DATA ] ──────────────────────────────────────────────────

  // ┌─ getRevolvingMarketCommitmentFeeBips ─────
  /// @inheritdoc IHooksFactoryRevolving
  function getRevolvingMarketCommitmentFeeBips() external view override returns (uint16) {
    return abi.decode(_tmpRevolvingMarketData.read(), (uint16));
  }

  // ┌─ _storeMarketData ─────
  /// @dev store the commitment fee for the deployment callback.
  function _storeMarketData(DeployMarketRuntimeParameters memory runtimeParams) internal override {
    _tmpRevolvingMarketData.write(abi.encode(runtimeParams.commitmentFeeBips));
  }

  // ┌─ _clearMarketData ─────
  function _clearMarketData() internal override {
    _tmpRevolvingMarketData.setEmpty();
  }

  // ┌─ _emitMarketData ─────
  function _emitMarketData(address market, DeployMarketRuntimeParameters memory runtimeParams) internal override {
    emit RevolvingMarketDeployed(market, runtimeParams.commitmentFeeBips);
  }
}

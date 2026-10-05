// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LensMocks
//  \ ^ /   Lens metadata, capability, and malformed-response fixtures.
//    V
//
//  CONTROLLER REGISTRATION
//  setControllers(...)
//  getRegisteredControllers()
//
//  BORROWER REGISTRATION
//  setRegisteredBorrower(...)
//  isRegisteredBorrower(...)
//
//  HOOK METADATA
//  constructor(...)
//  version()
//  config()
//
//  FACTORY FAILURE MODES
//  setReverts(...)
//
//  FACTORY TEMPLATES
//  setTemplates(...)
//  getHooksTemplatesCount()
//  getHooksTemplates()
//  setTemplateDetails(...)
//  getHooksTemplateDetails(...)
//
//  FACTORY INSTANCES
//  setInstances(...)
//  getHooksInstancesForBorrower(...)
//  setInstanceTemplate(...)
//  getHooksTemplateForInstance(...)
//  getMarketsForHooksInstanceCount(...)
//
//  FACTORY MARKETS
//  setMarkets(...)
//  getMarketsForHooksTemplateCount(...)
//  getMarketsForHooksTemplate(...)
//  getMarketsForHooksTemplate(...)
//
//  DELEGATED RESPONSES
//  constructor(...)
//  fallback()
//
//  VERSION STRINGS
//  constructor(...)
//  version()
//
//  V1 MARKET METADATA
//  constructor(...)
//  version()
//
//  REVERTING VERSION
//  version()
//
//  MALFORMED VERSION
//  constructor(...)
//  fallback()
//
//  OPTIONAL UINT RESPONSES
//  constructor(...)
//  fallback()
//
//  CAPABILITY PROBES
//  isV2Market(...)
//  hooksKind(...)
//
//  METADATA PROBES
//  constraints(...)
//  lifecycle(...)
//  pendingAprChange(...)
//  decodeFlags(...)
//  optionalUint(...)
// ═════

import { HooksConfigData, HooksConfigDataLib } from 'src/lens/HooksConfigData.sol';
import { HooksInstanceKind } from 'src/lens/HooksConfigData.sol';
import { HooksTemplate } from 'src/IHooksFactory.sol';
import { MarketDataLib, OptionalUintDataV2_5 } from 'src/lens/MarketData.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { HooksInstanceDataLib, MarketParameterConstraints } from 'src/lens/HooksInstanceData.sol';
import { PeriodicPendingAprChangeData } from 'src/lens/HooksConfigData.sol';
import { MarketLifecycleData, WildcatMarket } from 'src/lens/MarketLifecycleData.sol';

// ┌─ LensArchControllerMock ───────────────────────────────────────────────────
contract LensArchControllerMock {
  address[] internal _controllers;
  mapping(address borrower => bool registered) internal _registeredBorrowers;

  // ░░▒▒▓▓██ [ CONTROLLER REGISTRATION ] ──────────────────────────────────────

  // ┌─ setControllers ─────
  function setControllers(address[] calldata controllers) external {
    _controllers = controllers;
  }

  // ┌─ getRegisteredControllers ─────
  function getRegisteredControllers() external view returns (address[] memory) {
    return _controllers;
  }

  // ░░▒▒▓▓██ [ BORROWER REGISTRATION ] ────────────────────────────────────────

  // ┌─ setRegisteredBorrower ─────
  function setRegisteredBorrower(address borrower, bool registered) external {
    _registeredBorrowers[borrower] = registered;
  }

  // ┌─ isRegisteredBorrower ─────
  function isRegisteredBorrower(address borrower) external view returns (bool) {
    return _registeredBorrowers[borrower];
  }
}

// ┌─ LensNonHooksControllerMock ───────────────────────────────────────────────
contract LensNonHooksControllerMock { }

// ┌─ LensHooksMock ────────────────────────────────────────────────────────────
contract LensHooksMock {
  address public immutable pendingAdministrator;

  // ░░▒▒▓▓██ [ HOOK METADATA ] ────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address pendingAdministrator_) {
    pendingAdministrator = pendingAdministrator_;
  }

  // ┌─ version ─────
  function version() external pure returns (string memory) {
    return 'UnknownHooks';
  }

  // ┌─ config ─────
  function config() external pure returns (HooksDeploymentConfig) {
    return HooksDeploymentConfig.wrap(0);
  }
}

// ┌─ LensFactoryMock ──────────────────────────────────────────────────────────
contract LensFactoryMock {
  address[] internal _templates;
  address[] internal _instances;
  mapping(address template => HooksTemplate details) internal _templateDetails;
  mapping(address instance => address template) internal _instanceTemplates;
  mapping(address template => address[] markets) internal _templateMarkets;

  bool internal _revertProbe;
  bool internal _revertTemplates;
  bool internal _revertInstances;
  bool internal _revertMarkets;

  // ░░▒▒▓▓██ [ FACTORY FAILURE MODES ] ────────────────────────────────────────

  // ┌─ setReverts ─────
  function setReverts(bool probe, bool templates, bool instances, bool markets) external {
    _revertProbe = probe;
    _revertTemplates = templates;
    _revertInstances = instances;
    _revertMarkets = markets;
  }

  // ░░▒▒▓▓██ [ FACTORY TEMPLATES ] ────────────────────────────────────────────

  // ┌─ setTemplates ─────
  function setTemplates(address[] calldata templates) external {
    _templates = templates;
  }

  // ┌─ getHooksTemplatesCount ─────
  function getHooksTemplatesCount() external view returns (uint256) {
    if (_revertProbe) revert('probe');
    return _templates.length;
  }

  // ┌─ getHooksTemplates ─────
  function getHooksTemplates() external view returns (address[] memory) {
    if (_revertTemplates) revert('templates');
    return _templates;
  }

  // ┌─ setTemplateDetails ─────
  function setTemplateDetails(
    address template,
    string calldata name,
    uint24 index,
    uint16 protocolFeeBips,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount
  )
    external
  {
    HooksTemplate storage details = _templateDetails[template];
    details.originationFeeAsset = originationFeeAsset;
    details.originationFeeAmount = originationFeeAmount;
    details.protocolFeeBips = protocolFeeBips;
    details.exists = true;
    details.enabled = true;
    details.index = index;
    details.feeRecipient = feeRecipient;
    details.name = name;
  }

  // ┌─ getHooksTemplateDetails ─────
  function getHooksTemplateDetails(address template) external view returns (HooksTemplate memory) {
    return _templateDetails[template];
  }

  // ░░▒▒▓▓██ [ FACTORY INSTANCES ] ────────────────────────────────────────────

  // ┌─ setInstances ─────
  function setInstances(address[] calldata instances) external {
    _instances = instances;
  }

  // ┌─ getHooksInstancesForBorrower ─────
  function getHooksInstancesForBorrower(address) external view returns (address[] memory) {
    if (_revertInstances) revert('instances');
    return _instances;
  }

  // ┌─ setInstanceTemplate ─────
  function setInstanceTemplate(address instance, address template) external {
    _instanceTemplates[instance] = template;
  }

  // ┌─ getHooksTemplateForInstance ─────
  function getHooksTemplateForInstance(address instance) external view returns (address) {
    return _instanceTemplates[instance];
  }

  // ┌─ getMarketsForHooksInstanceCount ─────
  function getMarketsForHooksInstanceCount(address) external pure returns (uint256) {
    return 1;
  }

  // ░░▒▒▓▓██ [ FACTORY MARKETS ] ──────────────────────────────────────────────

  // ┌─ setMarkets ─────
  function setMarkets(address template, address[] calldata markets) external {
    _templateMarkets[template] = markets;
  }

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(address template) external view returns (uint256) {
    if (_revertMarkets) revert('markets');
    return _templateMarkets[template].length;
  }

  // ┌─ getMarketsForHooksTemplate ─────
  function getMarketsForHooksTemplate(address template) external view returns (address[] memory) {
    if (_revertMarkets) revert('markets');
    return _templateMarkets[template];
  }

  // ┌─ getMarketsForHooksTemplate ─────
  function getMarketsForHooksTemplate(
    address template,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory markets)
  {
    if (_revertMarkets) revert('markets');
    address[] storage source = _templateMarkets[template];
    if (end > source.length) end = source.length;
    markets = new address[](end - start);
    for (uint256 i; i < markets.length; i++) {
      markets[i] = source[start + i];
    }
  }
}

// ┌─ LensDelegateTargetMock ───────────────────────────────────────────────────
contract LensDelegateTargetMock {
  error DelegatedCallFailed();

  uint256 internal immutable _response;
  bool internal immutable _shouldRevert;

  // ░░▒▒▓▓██ [ DELEGATED RESPONSES ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(uint256 response, bool shouldRevert) {
    _response = response;
    _shouldRevert = shouldRevert;
  }

  // ┌─ fallback ─────
  fallback() external {
    if (_shouldRevert) revert DelegatedCallFailed();
    uint256 response = _response;
    assembly ('memory-safe') {
      mstore(0, response)
      return(0, 0x20)
    }
  }
}

// ┌─ VersionStringMock ────────────────────────────────────────────────────────
contract VersionStringMock {
  string internal _version;

  // ░░▒▒▓▓██ [ VERSION STRINGS ] ──────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(string memory version_) {
    _version = version_;
  }

  // ┌─ version ─────
  function version() external view returns (string memory) {
    return _version;
  }
}

// ┌─ LensV1MarketMock ─────────────────────────────────────────────────────────
contract LensV1MarketMock {
  address public immutable asset;
  string public constant name = 'Wildcat V1';
  string public constant symbol = 'WCV1';
  uint8 public constant decimals = 18;

  // ░░▒▒▓▓██ [ V1 MARKET METADATA ] ───────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address asset_) {
    asset = asset_;
  }

  // ┌─ version ─────
  function version() external pure returns (string memory) {
    return '1.0.0';
  }
}

// ┌─ RevertingVersionMock ─────────────────────────────────────────────────────
contract RevertingVersionMock {
  error VersionReadFailed();

  // ░░▒▒▓▓██ [ REVERTING VERSION ] ────────────────────────────────────────────

  // ┌─ version ─────
  function version() external pure returns (string memory) {
    revert VersionReadFailed();
  }
}

// ┌─ MalformedVersionMock ─────────────────────────────────────────────────────
contract MalformedVersionMock {
  enum Shape {
    ShortHead,
    WrongOffset,
    MissingData
  }

  Shape internal immutable _shape;

  // ░░▒▒▓▓██ [ MALFORMED VERSION ] ────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(Shape shape) {
    _shape = shape;
  }

  // ┌─ fallback ─────
  fallback() external {
    Shape shape = _shape;
    assembly ('memory-safe') {
      switch shape
      case 0 {
        mstore(0, 0x20)
        return(0, 0x20)
      }
      case 1 {
        mstore(0, 0x40)
        mstore(0x20, 0)
        return(0, 0x40)
      }
      default {
        mstore(0, 0x20)
        mstore(0x20, 1)
        return(0, 0x40)
      }
    }
  }
}

// ┌─ OptionalUintTargetMock ───────────────────────────────────────────────────
contract OptionalUintTargetMock {
  enum Shape {
    Word,
    Long,
    Short,
    Revert
  }

  uint256 internal immutable _value;
  Shape internal immutable _shape;

  // ░░▒▒▓▓██ [ OPTIONAL UINT RESPONSES ] ──────────────────────────────────────

  // ┌─ constructor ─────
  constructor(uint256 value, Shape shape) {
    _value = value;
    _shape = shape;
  }

  // ┌─ fallback ─────
  fallback() external {
    uint256 value = _value;
    Shape shape = _shape;
    assembly ('memory-safe') {
      switch shape
      case 0 {
        mstore(0, value)
        return(0, 0x20)
      }
      case 1 {
        mstore(0, value)
        mstore(0x20, not(value))
        return(0, 0x40)
      }
      case 2 {
        mstore(0, value)
        return(0, 0x1f)
      }
      default {
        revert(0, 0)
      }
    }
  }
}

// ┌─ LensProbeHarness ─────────────────────────────────────────────────────────
contract LensProbeHarness {
  // ░░▒▒▓▓██ [ CAPABILITY PROBES ] ────────────────────────────────────────────

  // ┌─ isV2Market ─────
  function isV2Market(address target) external view returns (bool) {
    return MarketDataLib._isV2Market(target);
  }

  // ┌─ hooksKind ─────
  function hooksKind(address target) external view returns (HooksInstanceKind) {
    return HooksConfigDataLib.kindForHooks(target);
  }

  // ░░▒▒▓▓██ [ METADATA PROBES ] ──────────────────────────────────────────────

  // ┌─ constraints ─────
  function constraints(address target)
    external
    view
    returns (MarketParameterConstraints memory data, bool hasRepaymentBounds)
  {
    return HooksInstanceDataLib._readConstraints(target);
  }

  // ┌─ lifecycle ─────
  function lifecycle(address target, bool isClosed) external view returns (MarketLifecycleData memory data) {
    data.fill(WildcatMarket(target), isClosed);
  }

  // ┌─ pendingAprChange ─────
  function pendingAprChange(
    address target,
    address market
  )
    external
    view
    returns (PeriodicPendingAprChangeData memory data)
  {
    HooksConfigDataLib._fillPendingAprChange(data, target, market);
  }

  // ┌─ decodeFlags ─────
  function decodeFlags(HooksConfig config) external pure returns (HooksConfigData memory data) {
    data.fill(config);
  }

  // ┌─ optionalUint ─────
  function optionalUint(address target, bytes4 selector) external view returns (OptionalUintDataV2_5 memory data) {
    MarketDataLib._tryFillOptionalUint(data, target, selector);
  }
}

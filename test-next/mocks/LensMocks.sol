// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { HooksConfigData, HooksConfigDataLib } from 'src/lens/HooksConfigData.sol';
import { HooksInstanceKind } from 'src/lens/HooksConfigData.sol';
import { HooksTemplate } from 'src/IHooksFactory.sol';
import { MarketDataLib, OptionalUintDataV2_5 } from 'src/lens/MarketData.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { HooksDeploymentConfig } from 'src/types/HooksConfig.sol';

contract LensArchControllerMock {
  address[] internal _controllers;
  mapping(address borrower => bool registered) internal _registeredBorrowers;

  function setControllers(address[] calldata controllers) external {
    _controllers = controllers;
  }

  function setRegisteredBorrower(address borrower, bool registered) external {
    _registeredBorrowers[borrower] = registered;
  }

  function getRegisteredControllers() external view returns (address[] memory) {
    return _controllers;
  }

  function isRegisteredBorrower(address borrower) external view returns (bool) {
    return _registeredBorrowers[borrower];
  }
}

contract LensNonHooksControllerMock {}

contract LensHooksMock {
  address public immutable pendingAdministrator;

  constructor(address pendingAdministrator_) {
    pendingAdministrator = pendingAdministrator_;
  }

  function version() external pure returns (string memory) {
    return 'UnknownHooks';
  }

  function config() external pure returns (HooksDeploymentConfig) {
    return HooksDeploymentConfig.wrap(0);
  }
}

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

  function setReverts(bool probe, bool templates, bool instances, bool markets) external {
    _revertProbe = probe;
    _revertTemplates = templates;
    _revertInstances = instances;
    _revertMarkets = markets;
  }

  function setTemplates(address[] calldata templates) external {
    _templates = templates;
  }

  function setInstances(address[] calldata instances) external {
    _instances = instances;
  }

  function setTemplateDetails(
    address template,
    string calldata name,
    uint24 index,
    uint16 protocolFeeBips,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount
  ) external {
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

  function setInstanceTemplate(address instance, address template) external {
    _instanceTemplates[instance] = template;
  }

  function setMarkets(address template, address[] calldata markets) external {
    _templateMarkets[template] = markets;
  }

  function getHooksTemplatesCount() external view returns (uint256) {
    if (_revertProbe) revert('probe');
    return _templates.length;
  }

  function getHooksTemplates() external view returns (address[] memory) {
    if (_revertTemplates) revert('templates');
    return _templates;
  }

  function getHooksTemplateDetails(address template) external view returns (HooksTemplate memory) {
    return _templateDetails[template];
  }

  function getHooksInstancesForBorrower(address) external view returns (address[] memory) {
    if (_revertInstances) revert('instances');
    return _instances;
  }

  function getHooksTemplateForInstance(address instance) external view returns (address) {
    return _instanceTemplates[instance];
  }

  function getMarketsForHooksInstanceCount(address) external pure returns (uint256) {
    return 1;
  }

  function getMarketsForHooksTemplateCount(address template) external view returns (uint256) {
    if (_revertMarkets) revert('markets');
    return _templateMarkets[template].length;
  }

  function getMarketsForHooksTemplate(address template) external view returns (address[] memory) {
    if (_revertMarkets) revert('markets');
    return _templateMarkets[template];
  }

  function getMarketsForHooksTemplate(
    address template,
    uint256 start,
    uint256 end
  ) external view returns (address[] memory markets) {
    if (_revertMarkets) revert('markets');
    address[] storage source = _templateMarkets[template];
    if (end > source.length) end = source.length;
    markets = new address[](end - start);
    for (uint256 i; i < markets.length; i++) {
      markets[i] = source[start + i];
    }
  }
}

contract LensDelegateTargetMock {
  error DelegatedCallFailed();

  uint256 internal immutable _response;
  bool internal immutable _shouldRevert;

  constructor(uint256 response, bool shouldRevert) {
    _response = response;
    _shouldRevert = shouldRevert;
  }

  fallback() external {
    if (_shouldRevert) revert DelegatedCallFailed();
    uint256 response = _response;
    assembly ('memory-safe') {
      mstore(0, response)
      return(0, 0x20)
    }
  }
}

contract VersionStringMock {
  string internal _version;

  constructor(string memory version_) {
    _version = version_;
  }

  function version() external view returns (string memory) {
    return _version;
  }
}

contract LensV1MarketMock {
  address public immutable asset;
  string public constant name = 'Wildcat V1';
  string public constant symbol = 'WCV1';
  uint8 public constant decimals = 18;

  constructor(address asset_) {
    asset = asset_;
  }

  function version() external pure returns (string memory) {
    return '1.0.0';
  }
}

contract RevertingVersionMock {
  error VersionReadFailed();

  function version() external pure returns (string memory) {
    revert VersionReadFailed();
  }
}

contract MalformedVersionMock {
  enum Shape {
    ShortHead,
    WrongOffset,
    MissingData
  }

  Shape internal immutable _shape;

  constructor(Shape shape) {
    _shape = shape;
  }

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

contract OptionalUintTargetMock {
  enum Shape {
    Word,
    Long,
    Short,
    Revert
  }

  uint256 internal immutable _value;
  Shape internal immutable _shape;

  constructor(uint256 value, Shape shape) {
    _value = value;
    _shape = shape;
  }

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

contract LensProbeHarness {
  function isV2Market(address target) external view returns (bool) {
    return MarketDataLib._isV2Market(target);
  }

  function hooksKind(address target) external view returns (HooksInstanceKind) {
    return HooksConfigDataLib.kindForHooks(target);
  }

  function decodeFlags(HooksConfig config) external pure returns (HooksConfigData memory data) {
    data.fill(config);
  }

  function optionalUint(
    address target,
    bytes4 selector
  ) external view returns (OptionalUintDataV2_5 memory data) {
    MarketDataLib._tryFillOptionalUint(data, target, selector);
  }
}

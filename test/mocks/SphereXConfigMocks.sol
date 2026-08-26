// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SphereXConfig } from 'src/spherex/SphereXConfig.sol';
import { SphereXProtectedRegisteredBase } from 'src/spherex/SphereXProtectedRegisteredBase.sol';

contract SphereXEngineMock {
  bool internal immutable supported;

  event NewSenderOnEngine(address sender);

  constructor(bool _supported) {
    supported = _supported;
  }

  function supportsInterface(bytes4) external view returns (bool) {
    return supported;
  }

  function addAllowedSenderOnChain(address sender) external {
    emit NewSenderOnEngine(sender);
  }
}

contract SphereXConfigHarness is SphereXConfig {
  constructor(
    address admin,
    address operator,
    address engine
  ) SphereXConfig(admin, operator, engine) {}

  function addSender(address sender) external spherexOnlyOperatorOrAdmin {
    _addAllowedSenderOnChain(sender);
  }
}

contract SphereXRegisteredHarness is SphereXProtectedRegisteredBase {
  uint256 public value;

  constructor(address archController, address engine) {
    _archController = archController;
    __SphereXProtectedRegisteredBase_init(engine);
  }

  function setValue(uint256 newValue) external sphereXGuardExternal {
    value = newValue;
  }
}

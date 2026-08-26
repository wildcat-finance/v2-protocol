// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { ISphereXEngine } from 'src/spherex/ISphereXEngine.sol';

contract ArchControllerRegisteredTargetMock {
  error ChangeSphereXEngineBlocked();

  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);

  bool internal immutable _blockEngineUpdates;
  address public sphereXEngine;
  uint256 public updateCount;

  constructor(bool blockEngineUpdates) {
    _blockEngineUpdates = blockEngineUpdates;
  }

  function changeSphereXEngine(address newEngine) external {
    if (_blockEngineUpdates) revert ChangeSphereXEngineBlocked();
    address oldEngine = sphereXEngine;
    sphereXEngine = newEngine;
    updateCount++;
    emit ChangedSpherexEngineAddress(oldEngine, newEngine);
  }
}

contract ArchControllerEngineMock is ISphereXEngine {
  event NewSenderOnEngine(address sender);

  mapping(address sender => uint256 calls) public allowedSenderCalls;

  function sphereXValidatePre(
    int256,
    address,
    bytes calldata
  ) external pure returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  function sphereXValidatePost(
    int256,
    uint256,
    bytes32[] calldata,
    bytes32[] calldata
  ) external pure {}

  function sphereXValidateInternalPre(int256) external pure returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  function sphereXValidateInternalPost(
    int256,
    uint256,
    bytes32[] calldata,
    bytes32[] calldata
  ) external pure {}

  function addAllowedSenderOnChain(address sender) external {
    allowedSenderCalls[sender]++;
    emit NewSenderOnEngine(sender);
  }

  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == type(ISphereXEngine).interfaceId;
  }
}

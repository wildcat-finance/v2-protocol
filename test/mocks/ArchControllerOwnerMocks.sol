// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { ISphereXEngine } from 'src/spherex/ISphereXEngine.sol';

contract ArchControllerOwnerProtocolTargetMock {
  error ExpectedFailure(uint256 value);

  address public immutable archController;
  address public lastCaller;
  uint256 public value;

  constructor(address archController_) {
    archController = archController_;
  }

  function setValue(uint256 value_) external returns (uint256 result) {
    lastCaller = msg.sender;
    value = value_;
    result = value_ + 1;
  }

  function fail(uint256 value_) external pure {
    revert ExpectedFailure(value_);
  }
}

contract ArchControllerOwnerLegacyFactoryMock {
  error CallerNotArchControllerOwner();

  address public immutable archController;
  address public feeRecipient;
  address public originationFeeAsset;
  uint80 public originationFeeAmount;
  uint16 public protocolFeeBips;

  constructor(address archController_) {
    archController = archController_;
  }

  function setProtocolFeeConfiguration(
    address feeRecipient_,
    address originationFeeAsset_,
    uint80 originationFeeAmount_,
    uint16 protocolFeeBips_
  ) external {
    if (msg.sender != WildcatArchController(archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    feeRecipient = feeRecipient_;
    originationFeeAsset = originationFeeAsset_;
    originationFeeAmount = originationFeeAmount_;
    protocolFeeBips = protocolFeeBips_;
  }
}

contract ArchControllerOwnerSphereXEngineMock is AccessControlDefaultAdminRules, ISphereXEngine {
  bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
  bytes32 public constant SENDER_ADDER_ROLE = keccak256('SENDER_ADDER_ROLE');

  constructor(
    uint48 initialDelay,
    address initialDefaultAdmin
  ) AccessControlDefaultAdminRules(initialDelay, initialDefaultAdmin) {
    _grantRole(OPERATOR_ROLE, initialDefaultAdmin);
  }

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

  function addAllowedSenderOnChain(address) external onlyRole(SENDER_ADDER_ROLE) {}

  function supportsInterface(
    bytes4 interfaceId
  ) public view override(AccessControlDefaultAdminRules, ISphereXEngine) returns (bool) {
    return interfaceId == type(ISphereXEngine).interfaceId || super.supportsInterface(interfaceId);
  }
}
